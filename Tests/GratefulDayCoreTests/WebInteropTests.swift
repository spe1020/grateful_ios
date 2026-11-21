import XCTest
@testable import GratefulDayCore
import NostrCore

/// Fixtures produced by running the web app's own code at gratefulday a33f42c
/// (see Fixtures/README.md). iOS must read what web writes, and write what web reads.
final class WebInteropTests: XCTestCase {
    struct Events: Decodable {
        struct Entry: Decodable { let name: String; let event: NostrEvent; let plaintext: String?; let notes: [String]; let isPrivate: Bool; let replaces: String? }
        struct Settings: Decodable { let event: NostrEvent; let plaintextJson: String }
        struct NotesCase: Decodable { let input: String; let split: [String]; let normalized: String }
        struct Merge: Decodable { let local: Raw; let remote: Raw?; let reconciled: Raw }
        struct Parse: Decodable { let json: String; let parsed: Raw }
        struct Raw: Decodable, Equatable {
            let privacyDefault: Bool?; let celebratedMilestones: [Int]; let lastSeenNotifications: Int?
            var settings: AppSettings { AppSettings(privacyDefault: privacyDefault, celebratedMilestones: celebratedMilestones, lastSeenNotifications: lastSeenNotifications) }
        }
        let secretKeyHex: String; let pubkey: String
        let entries: [Entry]; let deletion: NostrEvent
        let settings: Settings; let settingsMinimal: Settings
        let notes: [NotesCase]; let settingsMerge: [Merge]; let settingsParse: [Parse]
    }

    var f: Events!
    var sk: Data!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web_events", withExtension: "json", subdirectory: "Fixtures"))
        f = try JSONDecoder().decode(Events.self, from: Data(contentsOf: url))
        sk = try XCTUnwrap(NostrKeys.data(hex: f.secretKeyHex))
        XCTAssertEqual(NostrKeys.hex(try NostrKeys.publicKey(for: sk)), f.pubkey)
    }

    func testEveryWebEntryValidatesAndDecodes() throws {
        XCTAssertEqual(f.entries.count, 8)
        for e in f.entries {
            XCTAssertTrue(DailyEntry.isValid(e.event, owner: f.pubkey), e.name)
            XCTAssertFalse(DailyEntry.isValid(e.event, owner: String(repeating: "a", count: 64)), "\(e.name): other owner")
            XCTAssertEqual(DailyEntry.isPrivate(e.event), e.isPrivate, e.name)
            let text = e.isPrivate ? try NIP44.decryptFromSelf(e.event.content, privateKey: sk) : e.event.content
            XCTAssertEqual(EntryNotes.split(text), e.notes, e.name)
            if let plaintext = e.plaintext { XCTAssertEqual(text, plaintext, e.name) }
        }
    }

    /// Rebuild each web entry from its notes with the iOS builder. Public
    /// entries must match web's tags and content exactly; private entries must
    /// match tags (ciphertext differs by random nonce) and decrypt to the same text.
    func testIOSBuildsTheSameEventsWebDoes() throws {
        for e in f.entries where e.name != "crlf_read_only" {
            let d = try XCTUnwrap(e.event.tagValue("d"))
            let day = try XCTUnwrap(dayFrom(e.event))
            XCTAssertEqual(day.dateString, d, e.name)
            let built = e.isPrivate
                ? try DailyEntry.privateTemplate(day: day, notes: e.notes, privateKey: sk)
                : try DailyEntry.template(day: day, notes: e.notes)
            XCTAssertEqual(built.kind, 36669)
            XCTAssertEqual(built.tags, e.event.tags, e.name)
            if e.isPrivate {
                XCTAssertEqual(try NIP44.decryptFromSelf(built.content, privateKey: sk), e.plaintext, e.name)
            } else {
                XCTAssertEqual(built.content, e.event.content, e.name)
                // Same inputs, same created_at => identical id to web's.
                let signed = try built.signed(privateKey: sk, createdAt: e.event.createdAt)
                XCTAssertEqual(signed.id, e.event.id, e.name)
                XCTAssertTrue(signed.isValid)
            }
        }
    }

    /// The fixtures were generated in America/Chicago; rebuild the Day there.
    private func dayFrom(_ event: NostrEvent) -> DailyEntry.Day? {
        guard let p = event.tagValue("published_at").flatMap(Int.init) else { return nil }
        return DailyEntry.Day(containing: Date(timeIntervalSince1970: TimeInterval(p) + 3600), timeZone: TimeZone(identifier: "America/Chicago")!)
    }

    func testEditedEntryReplacesOlderVersion() throws {
        let v1 = try XCTUnwrap(f.entries.first { $0.name == "edited_v1" }?.event)
        let v2 = try XCTUnwrap(f.entries.first { $0.name == "edited_v2" }?.event)
        XCTAssertEqual(DailyEntry.latestPerDay([v2, v1])["2026-11-24"]?.id, v2.id)
        XCTAssertEqual(DailyEntry.latestPerDay([v1, v2])["2026-11-24"]?.id, v2.id)
    }

    func testTieBreaksOnLowestId() throws {
        let a = try XCTUnwrap(f.entries.first { $0.name == "public_single" }?.event)
        var b = a; b.id = String(repeating: "0", count: 64)
        var c = a; c.id = String(repeating: "f", count: 64)
        XCTAssertEqual(DailyEntry.latestPerDay([c, a, b])[try XCTUnwrap(a.tagValue("d"))]?.id, b.id)
    }

    func testWebDeletionIsReadAndAppliedToCoveredVersionsOnly() throws {
        XCTAssertTrue(f.deletion.isValid)
        let v1 = try XCTUnwrap(f.entries.first { $0.name == "edited_v1" }?.event) // created 1795539200
        let v2 = try XCTUnwrap(f.entries.first { $0.name == "edited_v2" }?.event) // created 1795539300
        let t = EntryDeletion.tombstones(from: [f.deletion], owner: f.pubkey)       // deletion 1795540000
        XCTAssertTrue(EntryDeletion.isDeleted(v1, tombstones: t))
        XCTAssertTrue(EntryDeletion.isDeleted(v2, tombstones: t))
        var recreated = v2; recreated.createdAt = 1795540001
        XCTAssertFalse(EntryDeletion.isDeleted(recreated, tombstones: t))
        // Someone else's deletion never counts.
        XCTAssertTrue(EntryDeletion.tombstones(from: [f.deletion], owner: String(repeating: "b", count: 64)).isEmpty)
    }

    /// L1: a version whose created_at equals the deletion's is deleted (web uses `<=`).
    func testDeletionAtTheSameSecondDeletesTheEntry() throws {
        let entry = try XCTUnwrap(f.entries.first { $0.name == "public_single" }?.event)
        let d = try XCTUnwrap(entry.tagValue("d"))
        let del = try EntryDeletion.template(pubkey: f.pubkey, dateString: d, eventId: entry.id)
            .signed(privateKey: sk, createdAt: entry.createdAt)
        let t = EntryDeletion.tombstones(from: [del], owner: f.pubkey)
        XCTAssertEqual(t[EntryDeletion.address(pubkey: f.pubkey, dateString: d)], entry.createdAt)
        XCTAssertTrue(EntryDeletion.isDeleted(entry, tombstones: t))
        var oneLater = entry; oneLater.createdAt += 1
        XCTAssertFalse(EntryDeletion.isDeleted(oneLater, tombstones: t))
    }

    /// L2: the `day` tag must be an integer 1–366; anything else is rejected
    /// even when the event is correctly signed by the owner.
    func testDayTagOutsideOneTo366IsRejected() throws {
        func entry(day: String) throws -> NostrEvent {
            try UnsignedEvent(kind: 36669, tags: [["d", "2028-12-31"], ["published_at", "1830240000"], ["day", day], ["alt", "x"]], content: "x")
                .signed(privateKey: sk, createdAt: 1_830_300_000)
        }
        for bad in ["0", "367", "-1", "1000", "abc", "", "1.5"] {
            XCTAssertFalse(DailyEntry.isValid(try entry(day: bad), owner: f.pubkey), "day=\(bad)")
        }
        for good in ["1", "365", "366"] {
            XCTAssertTrue(DailyEntry.isValid(try entry(day: good), owner: f.pubkey), "day=\(good)")
        }
    }

    func testIOSDeletionHasWebShape() throws {
        let t = EntryDeletion.template(pubkey: f.pubkey, dateString: "2026-11-24", eventId: try XCTUnwrap(f.deletion.tagValue("e")))
        XCTAssertEqual(t.kind, 5)
        XCTAssertEqual(t.tags, f.deletion.tags)
        XCTAssertEqual(t.content, f.deletion.content)
        XCTAssertEqual(try t.signed(privateKey: sk, createdAt: f.deletion.createdAt).id, f.deletion.id)
    }

    func testWebSettingsEventDecodesAndReserializesIdentically() throws {
        for s in [f.settings, f.settingsMinimal] {
            XCTAssertTrue(s.event.isValid)
            XCTAssertEqual(s.event.tags, [["d", "gratefulday:settings"], ["encrypted", "nip44"], ["alt", "Encrypted gratefulday settings"]])
            let parsed = try AppSettings.read(s.event, privateKey: sk)
            XCTAssertFalse(parsed.isReadOnly)
            XCTAssertEqual(parsed.settings.serialized(), s.plaintextJson)
            let ios = try parsed.settings.template(privateKey: sk)
            XCTAssertEqual(ios.tags, s.event.tags)
            XCTAssertEqual(AppSettings.parse(try NIP44.decryptFromSelf(ios.content, privateKey: sk)).settings, parsed.settings)
        }
    }

    func testUndecryptableSettingsAreAnErrorNotEmpty() throws {
        var broken = f.settings.event
        broken.content = "AgAAAA" + String(broken.content.dropFirst(6))
        XCTAssertThrowsError(try AppSettings.read(broken, privateKey: sk)) { XCTAssertEqual($0 as? AppSettings.ReadError, .undecryptable) }
        XCTAssertThrowsError(try AppSettings.read(f.settings.event, privateKey: try NostrKeys.generatePrivateKey()))
    }

    func testSettingsVersionAboveOneIsReadOnly() {
        XCTAssertTrue(AppSettings.parse(#"{"version":2,"celebratedMilestones":[7]}"#).isReadOnly)
        XCTAssertFalse(AppSettings.parse(#"{"version":1,"celebratedMilestones":[7]}"#).isReadOnly)
    }

    func testNotesMatchWeb() {
        XCTAssertEqual(f.notes.count, 10)
        for c in f.notes {
            XCTAssertEqual(EntryNotes.split(c.input), c.split, c.input.debugDescription)
            XCTAssertEqual(EntryNotes.normalize(c.input), c.normalized, c.input.debugDescription)
        }
    }

    func testSettingsMergeMatchesWebReconcile() {
        for c in f.settingsMerge {
            XCTAssertEqual(AppSettings.reconcile(local: c.local.settings, remote: c.remote?.settings), c.reconciled.settings)
        }
    }

    func testSettingsParseMatchesWeb() {
        for c in f.settingsParse { XCTAssertEqual(AppSettings.parse(c.json).settings, c.parsed.settings, c.json) }
    }

    func testBuildRejectsEmptyAndOversizedContent() {
        let day = DailyEntry.Day(containing: Date(timeIntervalSince1970: 1_795_280_000), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertThrowsError(try DailyEntry.template(day: day, notes: ["  ", ""])) { XCTAssertEqual($0 as? DailyEntry.BuildError, .empty) }
        XCTAssertThrowsError(try DailyEntry.template(day: day, notes: [String(repeating: "é", count: 40_000)]))
        XCTAssertNoThrow(try DailyEntry.template(day: day, notes: [String(repeating: "a", count: 65_535)]))
    }

    func testPublishCreatedAtNeverGoesBackwards() {
        XCTAssertEqual(DailyEntry.publishCreatedAt(now: 100, remoteCreatedAt: nil), 100)
        XCTAssertEqual(DailyEntry.publishCreatedAt(now: 100, remoteCreatedAt: 50), 100)
        XCTAssertEqual(DailyEntry.publishCreatedAt(now: 100, remoteCreatedAt: 100), 101)
        XCTAssertEqual(DailyEntry.publishCreatedAt(now: 100, remoteCreatedAt: 150), 151)
    }

    func testDateValidation() {
        XCTAssertTrue(DailyEntry.isValidDateString("2028-02-29"))
        XCTAssertFalse(DailyEntry.isValidDateString("2026-02-29"))
        XCTAssertFalse(DailyEntry.isValidDateString("2026-13-01"))
        XCTAssertFalse(DailyEntry.isValidDateString("2026-1-01"))
    }
}
