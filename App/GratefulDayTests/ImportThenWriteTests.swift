import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Importing an account and writing straight away (Phase 1 device test,
/// 2026-11-24).
///
/// On the iPhone, a reflection written ten seconds after an nsec import was
/// stored with no owner until the next publish pass, so a different account
/// connected before that pass could adopt it (#27). Since #27 a day written
/// while an account is connected is that account's from the moment it is
/// saved. These tests pin the path end to end:
///
/// - the row is the imported account's, owned by it, from the start,
/// - nothing is signed or sent before spec A's disclosure is accepted,
/// - the first pass after it adopts the row, signs it with the imported key
///   and sends it to that account's own relays (its NIP-65 list), and
/// - another account's day on this iPhone is never touched or sent.
@MainActor
final class ImportThenWriteTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var account: AccountModel!
    private let zone = TimeZone(identifier: "America/New_York")!
    private var day: JournalDay {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return JournalDay(containing: cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 18))!, timeZone: zone)
    }

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        account = AccountModel(vault: KeyVault(keychain: FakeKeychain()))
        account.refresh(context: context)
    }

    // MARK: - Helpers

    /// Import a new key, as "Use my Nostr account" does. Returns its secret
    /// and pubkey.
    private func importAccount() throws -> (secret: Data, pubkey: String) {
        let secret = try NostrKeys.generatePrivateKey()
        let pubkey = try account.importKey(try NostrKeys.nsec(secret), context: context)
        XCTAssertEqual(account.activeOwner, pubkey)
        return (secret, pubkey)
    }

    /// The editor as Today rebuilds it when the connected account changes.
    private func editor() -> TodayEditorModel {
        TodayEditorModel(repository: JournalRepository(context: context, activeOwner: account.activeOwner), day: day)
    }

    private func rows() throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func relays(_ hosts: [String], events: [NostrEvent] = []) -> [FakeRelay] {
        hosts.map { FakeRelay($0, events: events) }
    }

    private func service(_ relays: [FakeRelay]) -> SyncService {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        return SyncService(fetcher: fetcher, publisher: publisher)
    }

    /// The signed events a relay received, decoded from its EVENT frames.
    private func published(_ relay: FakeRelay) throws -> [NostrEvent] {
        try relay.publishedFrames.map { frame in
            let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [Any])
            return try JSONDecoder().decode(NostrEvent.self, from: JSONSerialization.data(withJSONObject: array[1]))
        }
    }

    // MARK: - Tests

    /// The device sequence: import, write at once, accept the disclosure.
    /// Before the disclosure nothing leaves the iPhone; the first pass after
    /// it signs the day as the imported account and saves it.
    func testReflectionWrittenRightAfterImportIsOwnedAtOnceAndPublishedByTheFirstAuthorizedPass() async throws {
        let (secret, owner) = try importAccount()
        let defaults = relays(RelaySet.defaultRead.map { $0.host! })
        let sync = service(defaults)

        // Written before any pass has run for this account.
        let today = editor()
        XCTAssertTrue(today.edit("thankful"))
        XCTAssertTrue(today.flush())

        // Owned by the connected account from the first save (#27).
        var all = try rows()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].ownerPubkey, owner)
        XCTAssertEqual(all[0].entryKey, JournalEntry.key(owner: owner, dateString: day.dateString))
        XCTAssertEqual(all[0].syncState, .localOnly)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertEqual(try repo.text(for: day), "thankful")
        XCTAssertEqual(repo.dayMark(day.dateString), .localOnly, "nothing is being sent before the disclosure")
        XCTAssertEqual(try PublishDisclosure(context: context, owner: owner).pendingCount(), 1, "the sheet counts it")

        // A pass before the disclosure: read only. Nothing is adopted,
        // signed or sent.
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.publishDeferral, .notAllowedYet)
        XCTAssertTrue(defaults.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try rows()[0].syncState, .localOnly)
        XCTAssertTrue(try context.fetch(FetchDescriptor<OutboxEvent>()).isEmpty)

        // Continue on the sheet, then the pass the app starts after it.
        try PublishDisclosure(context: context, owner: owner).accept()
        XCTAssertEqual(repo.dayMark(day.dateString), .saving, "Saving shows while the day waits for its pass")
        await sync.run(owner: owner, secret: secret, context: context)

        XCTAssertEqual(repo.dayMark(day.dateString), .none, "saved to the account")
        XCTAssertNil(sync.publishDeferral)
        XCTAssertEqual(sync.lastPublish?.signed, 1)
        XCTAssertEqual(sync.lastPublish?.synced, 1)
        all = try rows()
        XCTAssertEqual(all.count, 1, "no second row for the day")
        XCTAssertEqual(all[0].ownerPubkey, owner)
        XCTAssertEqual(all[0].entryKey, JournalEntry.key(owner: owner, dateString: day.dateString))
        XCTAssertEqual(all[0].syncState, .synced)
        XCTAssertEqual(all[0].notesText, "thankful")

        // One private event, signed by the imported key, on the write relays.
        for url in RelaySet.defaultWrite {
            let relay = try XCTUnwrap(defaults.first { $0.url == url })
            let events = try published(relay)
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events[0].pubkey, owner)
            XCTAssertEqual(events[0].id, all[0].remoteEventID)
            XCTAssertTrue(events[0].isValid)
            XCTAssertTrue(DailyEntry.isPrivate(events[0]))
            XCTAssertEqual(events[0].tagValue("d"), day.dateString)
            XCTAssertEqual(try NIP44.decryptFromSelf(events[0].content, privateKey: secret), "thankful")
        }
    }

    /// An imported account that has its own relay list (kind 10002), as the
    /// account in the device test did: its day goes to the relays it lists
    /// and to none of the defaults.
    func testImportedAccountsDayGoesOnlyToItsOwnListedRelays() async throws {
        let (secret, owner) = try importAccount()
        let listed = ["relay-one.example", "relay-two.example", "relay-three.example"]
        let list = try UnsignedEvent(kind: 10002, tags: listed.map { ["r", "wss://\($0)"] }, content: "")
            .signed(privateKey: secret, createdAt: 1_794_398_127)
        let defaults = relays(RelaySet.defaultRead.map { $0.host! }, events: [list])
        let own = relays(listed)
        let sync = service(defaults + own)

        let today = editor()
        XCTAssertTrue(today.edit("thankful"))
        XCTAssertTrue(today.flush())
        try PublishDisclosure(context: context, owner: owner).accept()
        await sync.run(owner: owner, secret: secret, context: context)

        XCTAssertEqual(sync.relays?.write, own.map(\.url))
        let row = try XCTUnwrap(try rows().first)
        XCTAssertEqual(row.ownerPubkey, owner)
        XCTAssertEqual(row.syncState, .synced)
        for relay in own {
            XCTAssertEqual(try published(relay).map(\.id), [try XCTUnwrap(row.remoteEventID)])
        }
        XCTAssertTrue(defaults.allSatisfy { $0.publishedFrames.isEmpty }, "the account's list is used as is")
    }

    /// Two accounts on one iPhone, the same day (as on the test device):
    /// the earlier account's saved day is not shown to, changed by or sent
    /// for the account imported after it.
    func testAnotherAccountsDayIsNeitherAdoptedNorSent() async throws {
        // The first account writes, publishes, and signs out.
        let (firstSecret, first) = try importAccount()
        let defaults = relays(RelaySet.defaultRead.map { $0.host! })
        let sync = service(defaults)
        let earlier = editor()
        XCTAssertTrue(earlier.edit("first account's words"))
        XCTAssertTrue(earlier.flush())
        try PublishDisclosure(context: context, owner: first).accept()
        await sync.run(owner: first, secret: firstSecret, context: context)
        XCTAssertEqual(try rows().first?.syncState, .synced)
        XCTAssertEqual(account.signOut(context: context), .signedOut)
        sync.reset()
        let sentForFirst = defaults.map(\.publishedFrames.count)

        // A second account is imported and writes the same day at once.
        let (secret, owner) = try importAccount()
        XCTAssertNotEqual(owner, first)
        let today = editor()
        XCTAssertEqual(today.text, "", "the other account's day is not this account's")
        XCTAssertTrue(today.edit("second account's words"))
        XCTAssertTrue(today.flush())
        try PublishDisclosure(context: context, owner: owner).accept()
        await sync.run(owner: owner, secret: secret, context: context)

        let all = try rows()
        XCTAssertEqual(all.count, 2)
        let firstRow = try XCTUnwrap(all.first { $0.ownerPubkey == first })
        let secondRow = try XCTUnwrap(all.first { $0.ownerPubkey == owner })
        XCTAssertEqual(firstRow.notesText, "first account's words")
        XCTAssertEqual(firstRow.syncState, .synced)
        XCTAssertEqual(secondRow.notesText, "second account's words")
        XCTAssertEqual(secondRow.syncState, .synced)
        XCTAssertNotEqual(firstRow.remoteEventID, secondRow.remoteEventID)

        // Everything sent in the second account's pass is its own event.
        for (relay, before) in zip(defaults, sentForFirst) {
            for event in try published(relay).dropFirst(before) {
                XCTAssertEqual(event.pubkey, owner)
                XCTAssertEqual(try NIP44.decryptFromSelf(event.content, privateKey: secret), "second account's words")
            }
        }
        XCTAssertEqual(try published(try XCTUnwrap(defaults.first { $0.url == RelaySet.defaultWrite[1] })).count, 2)
    }
}
