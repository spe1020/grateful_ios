import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Spec B step 3 / M5b plan §4.1: days written without an account, sorted
/// against the account's days before anything is published.
@MainActor
final class FirstConnectSortTests: XCTestCase {
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

    private var sort: FirstConnectSort { FirstConnectSort(context: context, owner: owner, now: { self.t0 }) }
    private var review: ConflictReview { ConflictReview(context: context, owner: owner, now: { self.t0 }) }

    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func remote(_ date: String, _ text: String, at: Int) throws -> NostrEvent {
        try DailyEntry.privateTemplate(day: day(date), notes: [text], privateKey: secret).signed(privateKey: secret, createdAt: at)
    }

    private func guest(_ date: String, _ text: String, deleted: Bool = false) throws {
        let d = day(date)
        let row = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                               timeZoneID: zone.identifier, notesText: text, now: t0, ownerPubkey: nil)
        if deleted { row.deletedAt = t0 }
        context.insert(row)
        try context.save()
    }

    private func importRemote(_ events: [NostrEvent]) throws {
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: events, owner: owner, privateKey: secret), zone: zone)
    }

    private func rows(_ date: String) throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>()).filter { $0.dateString == date }
    }

    private func mine(_ date: String) throws -> JournalEntry {
        try XCTUnwrap(rows(date).first { $0.ownerPubkey == owner })
    }

    func testOnlyHereBecomesTheAccountsAndIsPublishedNext() throws {
        try guest("2026-11-20", "written here")
        XCTAssertEqual(try sort.run().adopted, 1)
        let r = try rows("2026-11-20")
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r.first?.ownerPubkey, owner)
        XCTAssertEqual(r.first?.entryKey, JournalEntry.key(owner: owner, dateString: "2026-11-20"))
        XCTAssertEqual(r.first?.syncState, .localOnly)
        XCTAssertEqual(r.first?.notesText, "written here")
    }

    func testSameTextNeedsNothing() throws {
        try importRemote([try remote("2026-11-20", "same", at: 100)])
        try guest("2026-11-20", "same")
        XCTAssertEqual(try sort.run().same, 1)
        XCTAssertEqual(try rows("2026-11-20").count, 1)
        XCTAssertEqual(try mine("2026-11-20").syncState, .synced)
    }

    func testDifferentTextIsAConflictWithBothTexts() throws {
        try importRemote([try remote("2026-11-20", "from the account", at: 100)])
        try guest("2026-11-20", "written here")
        XCTAssertEqual(try sort.run().conflicts, 1)
        XCTAssertEqual(try rows("2026-11-20").count, 1)
        let item = try XCTUnwrap(review.load().items.first)
        XCTAssertEqual(item.kind, .bothChanged)
        XCTAssertEqual(item.accountText, "from the account")
        XCTAssertEqual(item.iPhoneText, "written here")
        // Keep both: published next, signed after the account's version.
        try review.apply(["2026-11-20": .keepBoth])
        let r = try mine("2026-11-20")
        XCTAssertEqual(EntryNotes.split(r.notesText), ["from the account", "written here"])
        XCTAssertEqual(r.syncState, .localOnly)
        XCTAssertEqual(r.remoteCreatedAt, 100)
    }

    func testAccountDeletedDayIsADeletedFromAccountRow() throws {
        let v = try remote("2026-11-20", "old", at: 100)
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: v.id)
            .signed(privateKey: secret, createdAt: 200)
        try importRemote([v])
        try importRemote([v, k5])
        XCTAssertNotNil(try mine("2026-11-20").deletedAt)
        try guest("2026-11-20", "written here")
        try sort.run()
        XCTAssertEqual(try review.load().items.map(\.kind), [.deletedFromAccount])
        try review.apply(["2026-11-20": .keepThisIPhone])
        let r = try mine("2026-11-20")
        XCTAssertEqual(r.syncState, .localOnly)
        XCTAssertEqual(r.remoteCreatedAt, 200, "signed after the deletion")
        // Meeting the same deletion again is nothing new.
        try importRemote([v, k5])
        XCTAssertEqual(try mine("2026-11-20").syncState, .localOnly)
        XCTAssertEqual(try mine("2026-11-20").notesText, "written here")
    }

    func testUnreadableAccountDayIsListedApart() throws {
        try RemoteImporter(context: context, owner: owner)
            .apply(["2026-11-21": .blocked(eventId: String(repeating: "a", count: 64), createdAt: 400)], zone: zone)
        try guest("2026-11-21", "written here")
        try sort.run()
        XCTAssertEqual(try review.load().blocked.map(\.dateString), ["2026-11-21"])
        XCTAssertEqual(try mine("2026-11-21").notesText, "written here")
    }

    func testDayDeletedHereBeforeConnectingIsLeftAlone() throws {
        try guest("2026-11-20", "", deleted: true)
        XCTAssertEqual(try sort.run(), FirstConnectSort.Summary())
        XCTAssertNil(try rows("2026-11-20").first?.ownerPubkey)
    }

    func testOwnersUnsentWritingKeepsBoth() throws {
        let d = day("2026-11-20")
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: "account's draft", now: t0, ownerPubkey: owner))
        try context.save()
        try guest("2026-11-20", "written as guest")
        try sort.run()
        XCTAssertEqual(try rows("2026-11-20").count, 1)
        XCTAssertEqual(EntryNotes.split(try mine("2026-11-20").notesText), ["account's draft", "written as guest"])
    }

    /// G1 (Prep #17): the account's unsent day is public, the guest's is
    /// private: the merged day is private.
    func testMergedDayIsPrivateIfEitherWas() throws {
        let d = day("2026-11-20")
        let r = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                             timeZoneID: zone.identifier, notesText: "public, edited here", now: t0, ownerPubkey: owner)
        r.isPrivate = false
        context.insert(r)
        try context.save()
        try guest("2026-11-20", "private, as a guest")
        try sort.run()
        let m = try mine("2026-11-20")
        XCTAssertTrue(m.isPrivate, "private wins")
        XCTAssertEqual(EntryNotes.split(m.notesText), ["public, edited here", "private, as a guest"])
    }

    /// Audit #17 H1: a private guest note merged into a public account day
    /// the person edited after connecting stays private.
    func testPrivateGuestNoteIntoEditedPublicDayStaysPrivate() throws {
        let pub = try DailyEntry.template(day: day("2026-11-20"), notes: ["public on web"]).signed(privateKey: secret, createdAt: 100)
        try guest("2026-11-20", "my private guest note")          // guest rows default private
        try importRemote([pub])                                    // owner row, public, synced
        let m = try mine("2026-11-20")
        XCTAssertFalse(m.isPrivate)
        // The editor now prefers the owner row: the person edits it before Continue.
        m.notesText = EntryNotes.join(["public on web", "edited after connecting"])
        m.syncStateRaw = SyncState.localOnly.rawValue
        try context.save()
        try sort.run()
        let after = try mine("2026-11-20")
        XCTAssertTrue(EntryNotes.split(after.notesText).contains("my private guest note"))
        XCTAssertTrue(after.isPrivate, "private guest text is never published in a public event")
    }

    /// Audit #17 M1: a day deleted under the account stays deleted; the
    /// guest text goes to Set aside.
    func testDeletedAccountDayStaysDeletedAndGuestTextIsSetAside() throws {
        let e = try remote("2026-11-21", "account text", at: 100)
        try guest("2026-11-21", "hidden guest text")
        try importRemote([e])
        let m = try mine("2026-11-21")
        m.notesText = ""; m.deletedAt = t0; m.syncStateRaw = SyncState.localOnly.rawValue
        try context.save()
        try sort.run()
        XCTAssertNotNil(try mine("2026-11-21").deletedAt, "the person's delete stands")
        XCTAssertEqual(try mine("2026-11-21").notesText, "")
        let aside = try JournalRepository(context: context, activeOwner: owner).setAsideVersions()
        XCTAssertEqual(aside.map(\.notesText), ["hidden guest text"])
        XCTAssertEqual(aside.map(\.reason), [.writtenBeforeConnectingDeleted])
        XCTAssertEqual(ConflictCopy.setAsideReason(.writtenBeforeConnectingDeleted),
                       "Written before you connected your account. You'd deleted this day, so it wasn't put back.")
        // §12: nowhere else. No conflict row, no day-view line, no Today line.
        XCTAssertTrue(try review.load().items.isEmpty)
        XCTAssertNil(try review.dayLine("2026-11-21", isToday: true))
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertTrue(try repo.dayLineSetAsideVersions("2026-11-21").isEmpty)
        XCTAssertTrue(try repo.surfacedEarlierVersions().isEmpty, "no Today line")
        // Never purged: still there after another pass and a later sort.
        try sort.run()
        XCTAssertEqual(try JournalRepository(context: context, activeOwner: owner).setAsideVersions().map(\.notesText),
                       ["hidden guest text"])
        XCTAssertNil(try context.fetch(FetchDescriptor<OutboxEvent>()).first { $0.dateString == "2026-11-21" && $0.kind == DailyEntry.kind },
                     "nothing is published for it")
    }
}
