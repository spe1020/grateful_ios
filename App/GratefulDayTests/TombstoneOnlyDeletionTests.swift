import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// D7 (S3 web → iOS, run e806a3; Chief f98fa116; Audit e3af928d): relays
/// that honour NIP-09 drop the 36669 a kind 5 covers, so the account holds
/// the kind 5 alone. Before the fix the importer never saw that day as
/// deleted and the iPhone kept the text.
///
/// Every test runs the real read → import → publish path through
/// `SyncService` against fake relays that hold only what nos.lol and primal
/// held in the S3 run.
@MainActor
final class TombstoneOnlyDeletionTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private let otherSecret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!
    private let date = "2026-11-27"

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    // MARK: - Helpers

    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func remote(_ text: String, at: Int) throws -> NostrEvent {
        try DailyEntry.privateTemplate(day: day(date), notes: [text], privateKey: secret).signed(privateKey: secret, createdAt: at)
    }

    /// The kind 5 web publishes (`a` + `e` + `k`), signed by `key`.
    private func kind5(target: String, at: Int, key: Data? = nil, addressOwner: String? = nil) throws -> NostrEvent {
        try EntryDeletion.template(pubkey: addressOwner ?? owner, dateString: date, eventId: target)
            .signed(privateKey: key ?? secret, createdAt: at)
    }

    /// A kind 5 from another client that names only the event (`e`), no `a`.
    private func eOnlyKind5(target: String, at: Int, key: Data? = nil) throws -> NostrEvent {
        try UnsignedEvent(kind: 5, tags: [["e", target], ["k", String(DailyEntry.kind)]], content: "")
            .signed(privateKey: key ?? secret, createdAt: at)
    }

    /// An owner row based on `base` (`.synced`), as an import leaves it.
    @discardableResult
    private func syncedRow(_ text: String, base: NostrEvent) throws -> JournalEntry {
        let d = day(date)
        let row = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                               timeZoneID: zone.identifier, notesText: text, now: .now, ownerPubkey: owner)
        row.remoteEventID = base.id
        row.remoteCreatedAt = base.createdAt
        row.syncStateRaw = SyncState.synced.rawValue
        context.insert(row)
        try context.save()
        return row
    }

    private func row() throws -> JournalEntry {
        let key: String? = JournalEntry.key(owner: owner, dateString: date)
        return try XCTUnwrap(context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first)
    }

    /// An edit on the iPhone that hasn't synced yet.
    private func editOnIPhone(_ text: String) throws {
        let r = try row()
        r.notesText = text
        r.deletedAt = nil
        r.updatedAt = .now
        r.syncStateRaw = SyncState.localOnly.rawValue
        try context.save()
    }

    private func relays(_ events: [NostrEvent]) -> [FakeRelay] {
        RelaySet.defaultRead.map { FakeRelay($0.host!, events: events) }
    }

    private func service(_ relays: [FakeRelay]) -> SyncService {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        return SyncService(fetcher: fetcher, publisher: publisher)
    }

    private func allowPublishing() throws {
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
    }

    private func published(_ relays: [FakeRelay]) throws -> [NostrEvent] {
        try relays.flatMap(\.publishedFrames).map { frame in
            let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [Any])
            return try JSONDecoder().decode(NostrEvent.self, from: JSONSerialization.data(withJSONObject: array[1]))
        }
    }

    private func archived(_ reason: EarlierVersionReason) throws -> [EarlierVersion] {
        let o: String? = owner, raw = reason.rawValue, d = date
        return try context.fetch(FetchDescriptor<EarlierVersion>(predicate: #Predicate {
            $0.ownerPubkey == o && $0.dateString == d && $0.reasonRaw == raw
        }))
    }

    // MARK: - Rule 4 / S3: a kind 5 alone deletes a clean copy

    /// The S3 failure: the iPhone imported web's reflection; web deleted
    /// it; the relays now hold only the kind 5. The day is deleted on the
    /// iPhone, its text kept in Set aside, and nothing is published.
    func testKindFiveAloneDeletesACleanCopyAndPublishesNothing() async throws {
        let v = try remote("from web", at: 100)
        try syncedRow("from web", base: v)
        let k5 = try kind5(target: v.id, at: 200)
        try allowPublishing()
        let rs = relays([k5])
        let sync = service(rs)
        await sync.run(owner: owner, secret: secret, context: context)

        let r = try row()
        XCTAssertNotNil(r.deletedAt, "the day is deleted")
        XCTAssertEqual(r.notesText, "")
        XCTAssertEqual(r.syncState, .synced)
        XCTAssertEqual(r.remoteEventID, k5.id, "D5: based on this deletion")
        XCTAssertEqual(r.remoteCreatedAt, 200)
        XCTAssertEqual(try archived(.replacedByRemote).map(\.notesText), ["from web"], "the text is set aside first")
        XCTAssertTrue(try archived(.deletedInAccountInConflict).isEmpty, "no review for a clean copy")
        XCTAssertEqual(sync.lastPublish?.signed ?? 0, 0)
        XCTAssertTrue(try published(rs).isEmpty, "nothing is re-published")

        // The next pass (a relaunch) meets the same kind 5: nothing changes.
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertNotNil(try row().deletedAt)
        XCTAssertEqual(try archived(.replacedByRemote).count, 1)
        XCTAssertTrue(try published(rs).isEmpty)
    }

    // MARK: - Rule 2: edits the deletion never saw go to §7 review

    /// Audit point 6 (silent resurrection): the iPhone edited the day while
    /// offline; the relays hold the kind 5 alone. The day goes to the §7
    /// "deleted from your account" review with the iPhone's text intact,
    /// and no 36669 is published over the deletion.
    func testKindFiveAloneAgainstAnUnsyncedEditGoesToReviewAndNeverPublishes() async throws {
        let v = try remote("from web", at: 100)
        try syncedRow("from web", base: v)
        try editOnIPhone("written on the iPhone")
        let k5 = try kind5(target: v.id, at: 200)
        try allowPublishing()
        let rs = relays([k5])
        let sync = service(rs)
        await sync.run(owner: owner, secret: secret, context: context)

        let r = try row()
        XCTAssertEqual(r.syncState, .conflict)
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "written on the iPhone", "unsynced text is never dropped")
        let marker = try archived(.deletedInAccountInConflict)
        XCTAssertEqual(marker.count, 1, "listed for the §7 review")
        XCTAssertEqual(marker.first?.eventId, k5.id)
        XCTAssertEqual(marker.first?.eventCreatedAt, 200)
        XCTAssertFalse(try published(rs).contains { $0.kind == DailyEntry.kind }, "never published over the deletion")
    }

    /// Audit point 2: the local copy is based on a version newer than the
    /// kind 5 (written again after the deletion), and that version isn't on
    /// these relays. A missing 36669 means nothing; the older kind 5 doesn't
    /// touch the day.
    func testALocalBaseNewerThanTheKindFiveStaysAsItIs() async throws {
        let v1 = try remote("first", at: 100)
        let v2 = try remote("written again", at: 300)
        try syncedRow("written again", base: v2)
        let k5 = try kind5(target: v1.id, at: 200)
        let sync = service(relays([k5]))
        await sync.run(owner: owner, secret: secret, context: context)

        let r = try row()
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "written again")
        XCTAssertEqual(r.syncState, .synced)
        XCTAssertEqual(r.remoteEventID, v2.id)
        XCTAssertTrue(try archived(.replacedByRemote).isEmpty)
        XCTAssertTrue(try archived(.deletedInAccountInConflict).isEmpty)
    }

    /// Rule 4: no 36669 and no kind 5 for a day the iPhone has: nothing.
    func testAMissingEntryAloneMeansNothing() async throws {
        let v = try remote("from web", at: 100)
        try syncedRow("from web", base: v)
        let sync = service(relays([]))
        await sync.run(owner: owner, secret: secret, context: context)
        let r = try row()
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "from web")
        XCTAssertEqual(r.syncState, .synced)
    }

    // MARK: - Rule 1: owner only, exact address

    func testAnotherAuthorsKindFiveIsIgnored() async throws {
        let v = try remote("from web", at: 100)
        try syncedRow("from web", base: v)
        // Signed by someone else, naming this account's address.
        let forged = try kind5(target: v.id, at: 200, key: otherSecret)
        let sync = service(relays([forged]))
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertNil(try row().deletedAt)
        XCTAssertEqual(try row().notesText, "from web")
    }

    func testAnOwnKindFiveForAnotherPubkeysAddressIsIgnored() async throws {
        let v = try remote("from web", at: 100)
        try syncedRow("from web", base: v)
        let other = KeyVault.pubkeyHex(for: otherSecret)!
        let k5 = try kind5(target: v.id, at: 200, addressOwner: other)
        let sync = service(relays([k5]))
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertNil(try row().deletedAt)
    }

    // MARK: - Rule 3: `e`-only kind 5s match the recorded event id only

    func testAnEOnlyKindFiveNamingTheLocalBaseDeletesTheDay() async throws {
        let v = try remote("from another client", at: 100)
        try syncedRow("from another client", base: v)
        let k5 = try eOnlyKind5(target: v.id, at: 200)
        let sync = service(relays([k5]))
        await sync.run(owner: owner, secret: secret, context: context)
        let r = try row()
        XCTAssertNotNil(r.deletedAt)
        XCTAssertEqual(r.remoteEventID, k5.id)
        XCTAssertEqual(try archived(.replacedByRemote).map(\.notesText), ["from another client"])
    }

    func testAnEOnlyKindFiveNamingAnotherEventIsIgnored() async throws {
        let v = try remote("kept", at: 100)
        let unrelated = try remote("some other version", at: 50)
        try syncedRow("kept", base: v)
        let k5 = try eOnlyKind5(target: unrelated.id, at: 200)
        let sync = service(relays([k5]))
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertNil(try row().deletedAt)
        XCTAssertEqual(try row().notesText, "kept")
    }

    /// M7 (Audit, #53): rule 1 holds for rule 3 too. An `e`-only kind 5
    /// signed by someone else, naming exactly the local base, deletes
    /// nothing. The address path is owner-checked in `EntryDeletion`, so
    /// only the `deletions` owner filter guards this one.
    func testAnotherAuthorsEOnlyKindFiveNamingTheLocalBaseIsIgnored() async throws {
        let v = try remote("from another client", at: 100)
        try syncedRow("from another client", base: v)
        let forged = try eOnlyKind5(target: v.id, at: 200, key: otherSecret)
        let sync = service(relays([forged]))
        await sync.run(owner: owner, secret: secret, context: context)
        let r = try row()
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "from another client")
        XCTAssertEqual(r.remoteEventID, v.id, "still based on the owner's event")
        XCTAssertEqual(try archived(.replacedByRemote).count, 0)
    }

    /// M7 at the reader: `RemoteJournal.days` gives no entry for the day.
    func testRemoteJournalIgnoresAnotherAuthorsEOnlyKindFive() throws {
        let v = try remote("from another client", at: 100)
        let forged = try eOnlyKind5(target: v.id, at: 200, key: otherSecret)
        let days = RemoteJournal.days(from: [forged], owner: owner, privateKey: secret, localBases: [date: v.id])
        XCTAssertNil(days[date])
    }

    /// An `e`-only kind 5 names one event; when a different version of the
    /// day is on the relays, it says nothing about the day.
    func testAnEOnlyKindFiveIsIgnoredWhenAnotherVersionIsOnTheRelays() async throws {
        let v1 = try remote("old", at: 100)
        let v2 = try remote("new", at: 300)
        try syncedRow("old", base: v1)
        let k5 = try eOnlyKind5(target: v1.id, at: 200)
        let sync = service(relays([v2, k5]))
        await sync.run(owner: owner, secret: secret, context: context)
        let r = try row()
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "new", "the newer version is taken as before")
    }

    // MARK: - Audit point 4: this device's own deletion

    /// The iPhone deleted the day and delivered its kind 5; the relays then
    /// dropped the 36669. Meeting its own kind 5 alone is nothing new: no
    /// conflict, no review, nothing archived again.
    func testOwnDeliveredDeletionSeenAloneIsANoOp() async throws {
        let v = try remote("from web", at: 100)
        try syncedRow("from web", base: v)
        let r0 = try row()
        r0.notesText = ""
        r0.deletedAt = .now
        r0.updatedAt = .now
        r0.syncStateRaw = SyncState.localOnly.rawValue
        try context.save()
        try allowPublishing()
        let rs = relays([v])
        let sync = service(rs)
        await sync.run(owner: owner, secret: secret, context: context)
        let own = try XCTUnwrap(try published(rs).first { $0.kind == 5 }, "the deletion was sent")
        XCTAssertEqual(try row().syncState, .synced)

        // The relays honour it: only the kind 5 is left.
        for relay in rs { relay.events = [own] }
        await sync.run(owner: owner, secret: secret, context: context)
        let r = try row()
        XCTAssertNotNil(r.deletedAt)
        XCTAssertEqual(r.syncState, .synced)
        XCTAssertTrue(try archived(.deletedInAccountInConflict).isEmpty)
        XCTAssertEqual(sync.lastPublish?.conflicts ?? 0, 0)
    }

    // MARK: - RemoteJournal, directly

    /// The day of a tombstone with no 36669 is `.deleted`, and `by` carries
    /// the kind 5 id (Audit point 3).
    func testRemoteJournalReadsATombstoneAloneAsDeleted() throws {
        let v = try remote("x", at: 100)
        let k5 = try kind5(target: v.id, at: 200)
        let days = RemoteJournal.days(from: [k5], owner: owner, privateKey: secret)
        XCTAssertEqual(days[date], .deleted(at: 200, by: [k5.id]))
        XCTAssertEqual(days.count, 1)
    }
}
