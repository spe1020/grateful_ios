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
}
