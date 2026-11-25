import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// #27: a reflection written while an account is connected belongs to that
/// account from the first save. Switching accounts before it was published
/// must not hand it to the next account (Prep's checks 1–4).
@MainActor
final class OwnerAtWriteTests: XCTestCase {
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

    private func importAccount(_ secret: Data? = nil) throws -> (secret: Data, pubkey: String) {
        let secret = try secret ?? NostrKeys.generatePrivateKey()
        let pubkey = try account.importKey(try NostrKeys.nsec(secret), context: context)
        XCTAssertEqual(account.activeOwner, pubkey)
        return (secret, pubkey)
    }

    private func editor() -> TodayEditorModel {
        TodayEditorModel(repository: JournalRepository(context: context, activeOwner: account.activeOwner), day: day)
    }

    private func repo() -> JournalRepository { JournalRepository(context: context, activeOwner: account.activeOwner) }

    private func rows() throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func write(_ text: String) {
        let today = editor()
        XCTAssertTrue(today.edit(text))
        XCTAssertTrue(today.flush())
    }

    private func service(_ relays: [FakeRelay]) -> SyncService {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        return SyncService(fetcher: fetcher, publisher: publisher)
    }

    private func published(_ relay: FakeRelay) throws -> [NostrEvent] {
        try relay.publishedFrames.map { frame in
            let array = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [Any])
            return try JSONDecoder().decode(NostrEvent.self, from: JSONSerialization.data(withJSONObject: array[1]))
        }
    }

    // MARK: - Tests

    /// Prep check 1: C writes and signs out before any pass; D connects.
    func testAnUnsentDayStaysWithItsAccountWhenAnotherConnects() async throws {
        let (_, c) = try importAccount()
        write("C's words")
        XCTAssertEqual(try rows().first?.ownerPubkey, c)
        XCTAssertEqual(account.signOut(context: context), .signedOut)

        let defaults = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(defaults)
        let (dSecret, d) = try importAccount()

        // D's Today editor is empty; C's text is shown read-only.
        XCTAssertEqual(editor().text, "")
        XCTAssertEqual(try repo().otherAccountText(for: day.dateString), "C's words")
        // D's disclosure doesn't count C's day.
        XCTAssertEqual(try PublishDisclosure(context: context, owner: d).pendingCount(), 0)

        try PublishDisclosure(context: context, owner: d).accept()
        await sync.run(owner: d, secret: dSecret, context: context)

        XCTAssertTrue(defaults.allSatisfy { $0.publishedFrames.isEmpty }, "nothing of C's is sent as D")
        let all = try rows()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].ownerPubkey, c, "not adopted by D")
        XCTAssertEqual(all[0].syncState, .localOnly)
        XCTAssertEqual(all[0].notesText, "C's words")
    }

    /// Prep check 2: D already has that day. D's entry is untouched and no
    /// conflict copy is made.
    func testAnotherAccountsUnsentDayDoesNotTouchTheSameDayOfTheNextAccount() async throws {
        let (_, c) = try importAccount()
        write("C's words")
        XCTAssertEqual(account.signOut(context: context), .signedOut)

        let defaults = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(defaults)
        let (dSecret, d) = try importAccount()
        write("D's words")
        try PublishDisclosure(context: context, owner: d).accept()
        await sync.run(owner: d, secret: dSecret, context: context)

        let mine = try XCTUnwrap(try rows().first { $0.ownerPubkey == d })
        XCTAssertEqual(mine.notesText, "D's words")
        XCTAssertEqual(mine.syncState, .synced)
        XCTAssertTrue(try context.fetch(FetchDescriptor<EarlierVersion>()).isEmpty, "no conflict copy")
        let theirs = try XCTUnwrap(try rows().first { $0.ownerPubkey == c })
        XCTAssertEqual(theirs.notesText, "C's words")
        XCTAssertEqual(theirs.syncState, .localOnly)
        for relay in defaults {
            for event in try published(relay) {
                XCTAssertEqual(event.pubkey, d)
                XCTAssertEqual(try NIP44.decryptFromSelf(event.content, privateKey: dSecret), "D's words")
            }
        }
    }

    /// Prep check 3: when C reconnects, the day is C's and publishes.
    func testTheDayPublishesForItsOwnAccountWhenItReconnects() async throws {
        let (cSecret, c) = try importAccount()
        write("C's words")
        XCTAssertEqual(account.signOut(context: context), .signedOut)
        _ = try importAccount()
        XCTAssertEqual(account.signOut(context: context), .signedOut)

        let defaults = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(defaults)
        _ = try importAccount(cSecret)
        XCTAssertEqual(editor().text, "C's words", "C's own day again")
        try PublishDisclosure(context: context, owner: c).accept()
        await sync.run(owner: c, secret: cSecret, context: context)

        let row = try XCTUnwrap(try rows().first)
        XCTAssertEqual(row.ownerPubkey, c)
        XCTAssertEqual(row.syncState, .synced)
        let relay = try XCTUnwrap(defaults.first { $0.url == RelaySet.defaultWrite[0] })
        let events = try published(relay)
        XCTAssertEqual(events.map(\.id), [try XCTUnwrap(row.remoteEventID)])
        XCTAssertEqual(events[0].pubkey, c)
        XCTAssertEqual(try NIP44.decryptFromSelf(events[0].content, privateKey: cSecret), "C's words")
    }

    /// Prep check 4: the sign-out sheet counts only this account's unsaved
    /// days. Synced days are never counted, and a guest day the pass has
    /// adopted is the account's (synced) day.
    func testSignOutCountsOnlyUnsavedDaysOfThisAccount() async throws {
        let guestDay = JournalDay(containing: day.start.addingTimeInterval(-2 * 86_400 + 43_200), timeZone: zone)
        try JournalRepository(context: context, activeOwner: nil).save(text: "before signing in", for: guestDay)

        let (secret, owner) = try importAccount()
        let sync = service(RelaySet.defaultRead.map { FakeRelay($0.host!) })
        let savedDay = JournalDay(containing: day.start.addingTimeInterval(-86_400 + 43_200), timeZone: zone)
        try repo().save(text: "saved", for: savedDay)
        try PublishDisclosure(context: context, owner: owner).accept()
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertTrue(try rows().allSatisfy { $0.ownerPubkey == owner && $0.syncState == .synced })
        write("not yet sent")

        XCTAssertEqual(account.unsyncedCount(context: context), JournalRepository.SignOutCounts(unsaved: 1, guest: 0))
    }

    /// A guest day not yet adopted is counted apart from the account's.
    func testSignOutCountsGuestDaysNotYetAdopted() throws {
        let guestDay = JournalDay(containing: day.start.addingTimeInterval(-86_400 + 43_200), timeZone: zone)
        try JournalRepository(context: context, activeOwner: nil).save(text: "before signing in", for: guestDay)
        _ = try importAccount()
        write("today")
        XCTAssertEqual(account.unsyncedCount(context: context), JournalRepository.SignOutCounts(unsaved: 1, guest: 1))
    }

    func testSignOutCopy() {
        XCTAssertEqual(AccountCopy.signOutUnsynced(2),
                       "2 reflections haven't been saved to your account yet. They'll stay on this iPhone and will be saved when you sign back in to this account. They won't be saved to any other account.")
        XCTAssertEqual(AccountCopy.signOutGuestUnsaved(3),
                       "3 reflections written before you signed in haven't been saved yet. They'll stay on this iPhone and can be added to the next account you sign in with.")
        XCTAssertEqual(AccountCopy.signOutGuestUnsaved(1),
                       "1 reflection written before you signed in hasn't been saved yet. It'll stay on this iPhone and can be added to the next account you sign in with.")
        XCTAssertEqual(AccountCopy.signOutUnsynced(1),
                       "1 reflection hasn't been saved to your account yet. It'll stay on this iPhone and will be saved when you sign back in to this account. It won't be saved to any other account.")
    }
}
