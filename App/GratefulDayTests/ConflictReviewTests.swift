import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// M6: the conflict screen's model, copy and the V7 archive fields (Prep's
/// "M6 conflict screen"; Chief P31).
@MainActor
final class ConflictReviewTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private var review: ConflictReview { ConflictReview(context: context, owner: owner, now: { self.t0 }) }

    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func remote(_ date: String, _ text: String, at: Int, private isPrivate: Bool = true) throws -> NostrEvent {
        let d = day(date)
        let template = isPrivate
            ? try DailyEntry.privateTemplate(day: d, notes: [text], privateKey: secret)
            : try DailyEntry.template(day: d, notes: [text])
        return try template.signed(privateKey: secret, createdAt: at)
    }

    /// A row with a pending local edit, then the relay version arrives
    /// through the importer: the real path to a conflict.
    @discardableResult
    private func conflict(_ date: String, local: String, localPrivate: Bool = true,
                          account: String, accountPrivate: Bool = true, at: Int = 500) throws -> NostrEvent {
        let d = day(date)
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: local, now: t0, ownerPubkey: owner)
        entry.isPrivate = localPrivate
        context.insert(entry)
        try context.save()
        let event = try remote(date, account, at: at, private: accountPrivate)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [event], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row(date).syncState, .conflict)
        return event
    }

    private func row(_ date: String) throws -> JournalEntry {
        let key: String? = JournalEntry.key(owner: owner, dateString: date)
        return try XCTUnwrap(context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first)
    }

    private func setAside() throws -> [EarlierVersion] {
        try JournalRepository(context: context, activeOwner: owner).setAsideVersions()
    }

    // MARK: - Loading

    func testImporterKeepsAccountPrivacyAndCreatedAt() throws {
        let event = try conflict("2026-11-20", local: "here", account: "there", accountPrivate: false, at: 777)
        let archive = try XCTUnwrap(context.fetch(FetchDescriptor<EarlierVersion>()).first { $0.reason == .remoteInConflict })
        XCTAssertFalse(archive.isPrivate)
        XCTAssertEqual(archive.eventCreatedAt, 777)
        XCTAssertEqual(archive.eventId, event.id)
    }

    func testLoadListsBothTextsWithLabelsAccountFirst() throws {
        try conflict("2026-11-20", local: "from this iPhone", account: "from web")
        let days = try review.load()
        XCTAssertEqual(days.items.count, 1)
        XCTAssertEqual(days.items[0].accountText, "from web")
        XCTAssertEqual(days.items[0].iPhoneText, "from this iPhone")
        XCTAssertFalse(days.items[0].afterSaving, "found on connecting/reading, not after saving")
        XCTAssertTrue(days.blocked.isEmpty)
    }

    /// §5: a blocked day with pending edits is listed apart, with no choice.
    func testBlockedConflictIsListedApartAndNeverChanged() throws {
        let d = day("2026-11-21")
        let row = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                               timeZoneID: zone.identifier, notesText: "written here", now: t0, ownerPubkey: owner)
        context.insert(row)
        try context.save()
        try RemoteImporter(context: context, owner: owner)
            .apply(["2026-11-21": .blocked(eventId: String(repeating: "a", count: 64), createdAt: 400)], zone: zone)
        let days = try review.load()
        XCTAssertEqual(days.blocked.map(\.dateString), ["2026-11-21"])
        XCTAssertTrue(days.items.isEmpty)
        try review.apply(["2026-11-21": .keepBoth])
        _ = try review.keepBothForAll()
        XCTAssertEqual(try self.row("2026-11-21").syncState, .conflict, "never changed here")
        XCTAssertEqual(try self.row("2026-11-21").notesText, "written here")
    }

    /// §6: a conflict found after the day was saved uses the re-check heading.
    func testAfterSavingWhenTheDayHadBeenAcknowledged() throws {
        try conflict("2026-11-20", local: "saved here", account: "changed elsewhere")
        let e = try remote("2026-11-20", "saved here", at: 450)
        let ob = try Outbox(context: context, owner: owner).enqueue(e, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        ob.ackedRelays = ["wss://a"]
        try context.save()
        XCTAssertTrue(try review.load().allAfterSaving)
    }

    /// Chief P33: the Today and day-view links only open the screen for a
    /// day it lists: never for a blocked today or a today deleted elsewhere.
    func testListsDayOnlyForDaysWithAChoice() throws {
        try conflict("2026-11-20", local: "mine", account: "theirs")
        XCTAssertTrue(try review.listsDay("2026-11-20"))

        let d = day("2026-11-21")
        let blocked = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                   timeZoneID: zone.identifier, notesText: "written here", now: t0, ownerPubkey: owner)
        context.insert(blocked)
        try context.save()
        try RemoteImporter(context: context, owner: owner)
            .apply(["2026-11-21": .blocked(eventId: String(repeating: "a", count: 64), createdAt: 400)], zone: zone)
        XCTAssertEqual(try row("2026-11-21").syncState, .conflict)
        XCTAssertFalse(try review.listsDay("2026-11-21"), "blocked today: no link to a screen of blocked rows")

        let base = try remote("2026-11-22", "old", at: 100)
        let e = day("2026-11-22")
        let deleted = JournalEntry(dateString: e.dateString, dayOfYear: e.dayOfYear, publishedAt: e.publishedAt,
                                   timeZoneID: zone.identifier, notesText: "old", now: t0, ownerPubkey: owner)
        deleted.remoteEventID = base.id
        deleted.remoteCreatedAt = base.createdAt
        context.insert(deleted)
        try context.save()
        deleted.notesText = "edited here"
        deleted.syncStateRaw = SyncState.localOnly.rawValue
        try context.save()
        let del = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-22", eventId: base.id)
            .signed(privateKey: secret, createdAt: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, del], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-22").syncState, .conflict)
        XCTAssertFalse(try review.listsDay("2026-11-22"), "deleted elsewhere: no link to an empty screen")
    }

    // MARK: - Choices

    func testKeepBothJoinsAccountFirstAndPublishesNext() throws {
        let event = try conflict("2026-11-20", local: "iPhone 1\n\niPhone 2", account: "web 1")
        try review.apply(["2026-11-20": .keepBoth])
        let r = try row("2026-11-20")
        XCTAssertEqual(EntryNotes.split(r.notesText), ["web 1", "iPhone 1", "iPhone 2"])
        XCTAssertEqual(r.syncState, .localOnly, "published next, then shows Saving")
        XCTAssertEqual(r.remoteEventID, event.id, "based on the account's version")
        XCTAssertEqual(r.remoteCreatedAt, event.createdAt)
        XCTAssertTrue(try setAside().isEmpty, "nothing set aside: every word is on the day")
        XCTAssertTrue(try review.load().items.isEmpty)
    }

    /// Chief P31: only the account's text was private, so the combined day is.
    func testCombinedDayIsPrivateWhenOnlyAccountTextWasPrivate() throws {
        try conflict("2026-11-20", local: "public here", localPrivate: false, account: "private there", accountPrivate: true)
        XCTAssertTrue(try review.load().items[0].keepBothBecomesPrivate)
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(try row("2026-11-20").isPrivate)
    }

    func testCombinedDayIsPrivateWhenOnlyIPhoneTextWasPrivate() throws {
        try conflict("2026-11-20", local: "private here", localPrivate: true, account: "public there", accountPrivate: false)
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(try row("2026-11-20").isPrivate)
    }

    func testKeepOneKeepsItsOwnPrivacy() throws {
        try conflict("2026-11-20", local: "public here", localPrivate: false, account: "private there", accountPrivate: true)
        try review.apply(["2026-11-20": .keepThisIPhone])
        XCTAssertFalse(try row("2026-11-20").isPrivate)
        try conflict("2026-11-21", local: "private here", localPrivate: true, account: "public there", accountPrivate: false)
        try review.apply(["2026-11-21": .keepAccount])
        XCTAssertFalse(try row("2026-11-21").isPrivate)
    }

    func testKeepThisIPhoneSetsAccountTextAside() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "theirs")
        try review.apply(["2026-11-20": .keepThisIPhone])
        let r = try row("2026-11-20")
        XCTAssertEqual(r.notesText, "mine")
        XCTAssertEqual(r.syncState, .localOnly)
        XCTAssertEqual(r.remoteEventID, event.id)
        let aside = try setAside()
        XCTAssertEqual(aside.map(\.notesText), ["theirs"])
        XCTAssertEqual(aside.first?.reason, .notKept)
        XCTAssertTrue(try JournalRepository(context: context, activeOwner: owner).surfacedEarlierVersions().isEmpty,
                      "no 'replaced' Today line for a text the person chose not to keep")
    }

    func testKeepAccountSetsIPhoneTextAsideAndNeedsNoPublish() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "theirs", accountPrivate: false)
        try review.apply(["2026-11-20": .keepAccount])
        let r = try row("2026-11-20")
        XCTAssertEqual(r.notesText, "theirs")
        XCTAssertFalse(r.isPrivate)
        XCTAssertEqual(r.syncState, .synced, "already the account's version")
        XCTAssertEqual(r.remoteEventID, event.id)
        XCTAssertEqual(try setAside().map(\.notesText), ["mine"])
    }

    func testQueuedEventsFromBeforeTheChoiceAreNeverSent() throws {
        try conflict("2026-11-20", local: "mine", account: "theirs")
        let e = try remote("2026-11-20", "mine", at: 450)
        try Outbox(context: context, owner: owner).enqueue(e, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertNil(try Outbox(context: context, owner: owner).liveRow(dateString: "2026-11-20"))
    }

    /// Not now: loading changes nothing.
    func testLoadingChangesNothing() throws {
        try conflict("2026-11-20", local: "mine", account: "theirs")
        _ = try review.load()
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    // MARK: - Keep both for all

    func testKeepBothForAllAppliesToEveryChoiceAndSavesTheNotice() throws {
        try conflict("2026-11-20", local: "a", localPrivate: false, account: "b", accountPrivate: true)
        try conflict("2026-11-21", local: "c", account: "d")
        let kept = try review.keepBothForAll()
        XCTAssertEqual(kept.dates, ["2026-11-20", "2026-11-21"])
        XCTAssertTrue(kept.madePrivate)
        try review.saveKeptBothNotice(kept)
        XCTAssertEqual(try review.keptBothNotice(), kept)
        XCTAssertEqual(EntryNotes.split(try row("2026-11-21").notesText), ["d", "c"])
        try review.clearKeptBothNotice()
        XCTAssertNil(try review.keptBothNotice())
    }

    // MARK: - Publishing after a choice

    /// The kept day publishes: the pre-send check treats the account's
    /// version as the base, not as a new conflict.
    func testKeptDayPublishesAndIsNotStoppedByTheAccountVersion() async throws {
        let event = try conflict("2026-11-20", local: "mine", account: "theirs")
        try review.apply(["2026-11-20": .keepBoth])
        let relays = ["a", "b"].map { FakeRelay($0, events: [event]) }
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        let pass = PublishPass(context: context, owner: owner, secret: secret,
                               set: RelaySet(read: relays.map(\.url), write: relays.map(\.url)),
                               fetcher: fetcher, publisher: publisher, now: { self.t0 })
        let s = try await pass.run()
        XCTAssertEqual(s?.conflicts, 0)
        XCTAssertEqual(s?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }

    // MARK: - Copy

    func testHeadingsAndLines() {
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20"], afterSaving: false), "You wrote on November 20 in both places.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], afterSaving: false),
                       "You wrote on 3 days in both places.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20"], afterSaving: true),
                       "Your reflection for November 20 was also changed elsewhere.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], afterSaving: true),
                       "3 reflections were also changed elsewhere.")
        XCTAssertEqual(ConflictCopy.keptBoth(dates: ["2026-11-20"], madePrivate: false), "Kept both versions on November 20.")
        XCTAssertEqual(ConflictCopy.keptBoth(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], madePrivate: true),
                       "Kept both versions on 3 days. Days where either version was private are now private.")
        XCTAssertEqual(ConflictCopy.comeBack(dates: ["2026-11-20"]),
                       "Your reflection from November 20 was also changed elsewhere. Choose what to keep.")
        XCTAssertEqual(ConflictCopy.comeBack(dates: ["2026-11-20", "2026-11-21"]),
                       "2 reflections were also changed elsewhere. Choose what to keep.")
        for text in [ConflictCopy.subheading, ConflictCopy.keepBothLine, ConflictCopy.keepThisIPhoneLine, ConflictCopy.keepAccountLine,
                     ConflictCopy.privateWins, ConflictCopy.cantOpenAccount, ConflictCopy.cantCompareLine, ConflictCopy.notKeptReason] {
            for term in ["relay", "event", "sync", "key", "Nostr"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(term), "\(term) in \(text)")
            }
        }
    }

    // MARK: - V6 → V7

    func testV6StoreMigratesToV7AndOldArchivesReadAsPrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "v6-journal", withExtension: "store"))
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: location.storeURL)
        let store = JournalStore(location: location, defaults: UserDefaults(suiteName: "v7-\(UUID().uuidString)")!)
        store.openIfPossible(protectedDataAvailable: true)
        let ctx = try XCTUnwrap(store.container, "\(store.state)").mainContext
        let rows = try ctx.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
        let o = String(repeating: "b", count: 64)
        XCTAssertEqual(rows.map(\.notesText), ["Guest note", "iPhone note"])
        XCTAssertEqual(rows[1].syncState, .conflict)
        let archive = try XCTUnwrap(ctx.fetch(FetchDescriptor<EarlierVersion>()).first)
        XCTAssertEqual(archive.notesText, "Account note")
        XCTAssertTrue(archive.isPrivate, "archived before V7: the stricter choice")
        XCTAssertNil(archive.eventCreatedAt)
        let outbox = try XCTUnwrap(ctx.fetch(FetchDescriptor<OutboxEvent>()).first)
        XCTAssertTrue(outbox.supersededByRemote)
        XCTAssertEqual(outbox.ackedRelays, ["wss://nos.lol"])
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AccountMarker>()).first?.pubkey, o)
        // The migrated conflict can be reviewed and kept private.
        let days = try ConflictReview(context: ctx, owner: o).load()
        XCTAssertEqual(days.items.first?.accountText, "Account note")
        XCTAssertTrue(days.allAfterSaving)
        try ConflictReview(context: ctx, owner: o).apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(rows[1].isPrivate)
        XCTAssertEqual(EntryNotes.split(rows[1].notesText), ["Account note", "iPhone note"])
    }

    // MARK: - Audit FAIL at 7f2dc6f

    /// M1: a resolved conflict's archive is never offered for a later one.
    func testResolvedArchiveIsNotReusedForLaterDeletionConflict() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "old account text", at: 500)
        try review.apply(["2026-11-20": .keepThisIPhone])
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
        // Before this iPhone's edit is sent, another device deletes the day.
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: event.id)
            .signed(privateKey: secret, createdAt: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [event, k5], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertTrue(try review.load().items.isEmpty, "no stale 'Your account' text")
        XCTAssertFalse(try review.listsDay("2026-11-20"))
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict, "never marked synced with stale text")
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    /// M1: a second, newer remote version after a resolved conflict is shown,
    /// not the first one.
    func testSecondConflictShowsTheNewerAccountText() throws {
        try conflict("2026-11-20", local: "mine", account: "first", at: 500)
        try review.apply(["2026-11-20": .keepThisIPhone])
        let second = try remote("2026-11-20", "second", at: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [second], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try review.load().items.map(\.accountText), ["second"])
    }

    /// M2: deleted on this iPhone, edited elsewhere: kept off the screen,
    /// never "kept" into an empty pending day; it stays a conflict.
    func testLocalDeleteVsRemoteEditIsNotOfferedOrChanged() throws {
        let base = try remote("2026-11-20", "v1", at: 100)
        let d = day("2026-11-20")
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: "", now: t0, ownerPubkey: owner)
        entry.remoteEventID = base.id; entry.remoteCreatedAt = 100; entry.deletedAt = t0
        context.insert(entry); try context.save()
        let edit = try remote("2026-11-20", "edited elsewhere", at: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, edit], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertTrue(try review.load().items.isEmpty)
        XCTAssertFalse(try review.listsDay("2026-11-20"))
        try review.apply(["2026-11-20": .keepThisIPhone])
        _ = try review.keepBothForAll()
        let r = try row("2026-11-20")
        XCTAssertNotNil(r.deletedAt, "the person's delete stands")
        XCTAssertEqual(r.syncState, .conflict, "nothing published until Prep's copy lands")
        XCTAssertEqual(try earlier("2026-11-20"), ["edited elsewhere"], "the account's text is kept")
    }

    /// P34: deleted on the account, edited here: off the screen, unchanged.
    func testAccountDeleteVsLocalEditIsNotOfferedOrChanged() throws {
        let base = try remote("2026-11-20", "v1", at: 100)
        let d = day("2026-11-20")
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: "edited here", now: t0, ownerPubkey: owner)
        entry.remoteEventID = base.id; entry.remoteCreatedAt = 100
        context.insert(entry); try context.save()
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: base.id)
            .signed(privateKey: secret, createdAt: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, k5], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertTrue(try review.load().items.isEmpty)
        XCTAssertFalse(try review.listsDay("2026-11-20"))
        try review.apply(["2026-11-20": .keepAccount])
        _ = try review.keepBothForAll()
        let r = try row("2026-11-20")
        XCTAssertEqual(r.notesText, "edited here")
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.syncState, .conflict)
    }

    /// M1/P34: an open conflict the account then deletes. The earlier
    /// account text is no longer the account's; the day leaves the screen.
    func testOpenConflictThenAccountDeleteLeavesTheScreen() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "account text", at: 500)
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: event.id)
            .signed(privateKey: secret, createdAt: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [event, k5], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertTrue(try review.load().items.isEmpty, "the deleted account text isn't offered")
        XCTAssertFalse(try review.listsDay("2026-11-20"))
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict, "never marked synced with deleted text")
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    /// The same, found by the pre-send check rather than on connecting.
    func testOpenConflictThenAccountDeleteFoundBeforeSendingLeavesTheScreen() throws {
        _ = try conflict("2026-11-20", local: "mine", account: "account text", at: 500)
        try RemoteImporter(context: context, owner: owner)
            .conflict(dateString: "2026-11-20", remote: .deleted(at: 900, by: []))
        XCTAssertTrue(try review.load().items.isEmpty)
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    private func earlier(_ date: String) throws -> [String] {
        try context.fetch(FetchDescriptor<EarlierVersion>()).filter { $0.dateString == date && $0.reason == .remoteInConflict }.map(\.notesText)
    }
}
