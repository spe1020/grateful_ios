import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Holds matching client frames until opened, so a test can change the
/// account while a pass is waiting on a relay.
final class RelayGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var held = 0
    let matches: @Sendable ([Any]) -> Bool

    init(matches: @escaping @Sendable ([Any]) -> Bool) { self.matches = matches }

    var heldCount: Int { lock.withLock { held } }

    func pass(_ text: String) async {
        guard let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any], matches(array) else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.lock()
            held += 1
            if opened { lock.unlock(); c.resume(); return }
            waiters.append(c)
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let all = waiters
        waiters = []
        lock.unlock()
        all.forEach { $0.resume() }
    }

    /// The pass's journal read (36669 and 5, every day).
    static func journalRead() -> RelayGate {
        RelayGate { array in
            guard array.first as? String == "REQ", array.count >= 3, let f = array[2] as? [String: Any] else { return false }
            return (f["kinds"] as? [Int])?.contains(DailyEntry.kind) == true && f["#d"] == nil
        }
    }

    /// The pre-send refetch of one day (36669 with a `#d` tag).
    static func preSendRefetch() -> RelayGate {
        RelayGate { array in
            guard array.first as? String == "REQ", array.count >= 3, let f = array[2] as? [String: Any] else { return false }
            return (f["kinds"] as? [Int]) == [DailyEntry.kind] && f["#d"] != nil
        }
    }
}

struct GatedTransport: RelayTransport {
    let base: FakeTransport
    let gate: RelayGate
    func connect(_ url: URL) async throws -> RelayConnection {
        GatedSocket(inner: try await base.connect(url), gate: gate)
    }
}

final class GatedSocket: RelayConnection, @unchecked Sendable {
    let inner: RelayConnection
    let gate: RelayGate
    var url: URL { inner.url }
    init(inner: RelayConnection, gate: RelayGate) { self.inner = inner; self.gate = gate }
    func send(_ text: String) async throws {
        await gate.pass(text)
        try await inner.send(text)
    }
    func receive() async throws -> String { try await inner.receive() }
    func close() { inner.close() }
}

/// Audit L1 (account isolation post-merge review, 2026-11-25; Chief P87/P88):
/// a pass running for account A when the person switches to B imports
/// nothing, signs nothing and sends nothing for A, and forgets A's relays.
/// The account really switches (a real `AccountModel`, sign-out then import);
/// `isCurrent` is built the way `GratefulDayApp.readFromRelays` builds it,
/// and `reset()` is what `GratefulDayApp`'s `onChange(of: activeOwner)` calls.
///
/// Gap (Chief P88, PR-1): these tests call `reset()` and build `isCurrent`
/// themselves, so removing the App's `onChange` or changing its closure
/// would not fail them.
///
/// Audit L2: a guest day deleted while an account is connected stays a guest
/// tombstone. No account adopts or publishes it.
@MainActor
final class AccountSwitchIsolationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var account: AccountModel!
    private let zone = TimeZone(identifier: "America/New_York")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        account = AccountModel(vault: KeyVault(keychain: FakeKeychain()))
        account.refresh(context: context)
    }

    // MARK: - Helpers

    private func day(_ d: Int) -> JournalDay {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return JournalDay(containing: cal.date(from: DateComponents(year: 2026, month: 11, day: d, hour: 18))!, timeZone: zone)
    }

    private func importAccount(_ secret: Data? = nil) throws -> (secret: Data, pubkey: String) {
        let secret = try secret ?? NostrKeys.generatePrivateKey()
        let pubkey = try account.importKey(try NostrKeys.nsec(secret), context: context)
        XCTAssertEqual(account.activeOwner, pubkey)
        return (secret, pubkey)
    }

    private func repo() -> JournalRepository { JournalRepository(context: context, activeOwner: account.activeOwner) }

    private func rows() throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
    }

    private func outbox() throws -> [OutboxEvent] { try context.fetch(FetchDescriptor<OutboxEvent>()) }

    private func relays(events: [NostrEvent] = []) -> [FakeRelay] {
        RelaySet.defaultRead.map { FakeRelay($0.host!, events: events) }
    }

    private func service(_ relays: [FakeRelay], gate: RelayGate? = nil) -> SyncService {
        let base = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        let transport: RelayTransport = gate.map { GatedTransport(base: base, gate: $0) } ?? base
        // Long enough that a held read is never timed out (which would make
        // the pass unresolved and hide what the switch did).
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .seconds(20)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .seconds(5)
        return SyncService(fetcher: fetcher, publisher: publisher)
    }

    /// `GratefulDayApp.readFromRelays`'s closure, over this test's store and account.
    private func isCurrent(for owner: String) -> @MainActor () -> Bool {
        let container = container!, account = account!, context = context
        return { container.mainContext === context && account.activeOwner == owner }
    }

    private func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
        let started = Date()
        while !condition() {
            if Date().timeIntervalSince(started) > 10 { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func sentFrames(_ relays: [FakeRelay]) -> [String] { relays.flatMap(\.publishedFrames) }

    /// A: a local unsent day (would be signed and sent), the disclosure
    /// accepted, and a day of A's on the relays (would be imported).
    private struct Setup { let a: String; let aSecret: Data; let relays: [FakeRelay] }

    private func setUpAccountA() throws -> Setup {
        let (aSecret, a) = try importAccount()
        try repo().save(text: "A's unsent words", for: day(24))
        try PublishDisclosure(context: context, owner: a).accept()
        let remote = try DailyEntry.privateTemplate(day: day(20).day, notes: ["A's words from web"], privateKey: aSecret)
            .signed(privateKey: aSecret, createdAt: 100)
        return Setup(a: a, aSecret: aSecret, relays: relays(events: [remote]))
    }

    /// Sign A out and connect B, as the person does in Account.
    private func switchToB() throws -> String {
        XCTAssertEqual(account.signOut(context: context), .signedOut)
        let (_, b) = try importAccount()
        XCTAssertNotEqual(account.activeOwner, nil)
        return b
    }

    private func assertNothingDoneForA(_ s: Setup, _ sync: SyncService, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(sentFrames(s.relays).isEmpty, "nothing sent for A", file: file, line: line)
        XCTAssertTrue(try outbox().isEmpty, "nothing signed for A", file: file, line: line)
        let all = try rows()
        XCTAssertEqual(all.map(\.dateString), [day(24).dateString], "A's day on the relays wasn't imported", file: file, line: line)
        XCTAssertEqual(all.first?.ownerPubkey, s.a, file: file, line: line)
        XCTAssertEqual(all.first?.syncState, .localOnly, file: file, line: line)
        XCTAssertNil(sync.relays, "A's relays aren't kept", file: file, line: line)
        XCTAssertNil(sync.lastPublish, file: file, line: line)
    }

    // MARK: - L1: switching accounts while a pass is running

    /// Control: with no switch, the same setup imports A's day, signs A's
    /// unsent day and sends it. Without this, the tests below could pass
    /// because the pass never got that far.
    func testControlWithoutASwitchThePassImportsSignsAndSends() async throws {
        let s = try setUpAccountA()
        let gate = RelayGate.journalRead()
        let sync = service(s.relays, gate: gate)
        sync.start(owner: s.a, secret: s.aSecret, context: context, isCurrent: isCurrent(for: s.a))
        try await waitUntil("the journal read") { gate.heldCount > 0 }
        gate.open()
        try await waitUntil("the pass") { if case .done = sync.status { return true }; return false }
        XCTAssertEqual(try rows().count, 2, "A's web day imported")
        XCTAssertFalse(try outbox().isEmpty, "A's day signed")
        XCTAssertFalse(sentFrames(s.relays).isEmpty, "A's day sent")
        XCTAssertNotNil(sync.relays)
    }

    /// The App's two steps together: the account changes during the read,
    /// `onChange(of: activeOwner)` resets sync, and the pass's `isCurrent`
    /// follows the real account.
    func testSwitchingAccountsDuringTheReadImportsSignsAndSendsNothingForTheOldAccount() async throws {
        let s = try setUpAccountA()
        let gate = RelayGate.journalRead()
        let sync = service(s.relays, gate: gate)
        sync.start(owner: s.a, secret: s.aSecret, context: context, isCurrent: isCurrent(for: s.a))
        try await waitUntil("the journal read") { gate.heldCount > 0 }

        _ = try switchToB()
        sync.reset()
        gate.open()
        try await waitUntil("the pass to stop") { sync.status == .idle }
        try await Task.sleep(for: .milliseconds(300))

        try assertNothingDoneForA(s, sync)
    }

    /// `reset()` on its own stops the running pass before it imports, signs
    /// or sends, even if the pass's own account check would let it continue.
    func testResetAloneStopsARunningPassBeforeItSignsOrSends() async throws {
        let s = try setUpAccountA()
        let gate = RelayGate.journalRead()
        let sync = service(s.relays, gate: gate)
        sync.start(owner: s.a, secret: s.aSecret, context: context) { true }
        try await waitUntil("the journal read") { gate.heldCount > 0 }

        _ = try switchToB()
        sync.reset()
        gate.open()
        try await waitUntil("the pass to stop") { sync.status == .idle }
        try await Task.sleep(for: .milliseconds(300))

        try assertNothingDoneForA(s, sync)
    }

    /// The real account's switch, seen through `isCurrent`, stops the pass
    /// after its read, before it imports or signs, even without `reset()`.
    func testTheAccountSwitchAloneStopsThePassAfterItsRead() async throws {
        let s = try setUpAccountA()
        let gate = RelayGate.journalRead()
        let sync = service(s.relays, gate: gate)
        sync.start(owner: s.a, secret: s.aSecret, context: context, isCurrent: isCurrent(for: s.a))
        try await waitUntil("the journal read") { gate.heldCount > 0 }

        _ = try switchToB()
        gate.open()
        try await waitUntil("the pass to stop") { sync.status == .idle }
        try await Task.sleep(for: .milliseconds(300))

        try assertNothingDoneForA(s, sync)
    }

    /// The account changes during the pre-send refetch, after A's day was
    /// signed: the signed event is never sent, and stays queued for A.
    func testTheAccountSwitchDuringThePreSendRefetchSendsNothing() async throws {
        let s = try setUpAccountA()
        let gate = RelayGate.preSendRefetch()
        let sync = service(s.relays, gate: gate)
        sync.start(owner: s.a, secret: s.aSecret, context: context, isCurrent: isCurrent(for: s.a))
        try await waitUntil("the pre-send refetch") { gate.heldCount > 0 }
        XCTAssertEqual(try outbox().count, 1, "signed before the switch")

        _ = try switchToB()
        gate.open()
        try await waitUntil("the pass") { if case .done = sync.status { return true }; return false }
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(sentFrames(s.relays).isEmpty, "nothing sent for A after the switch")
        let row = try XCTUnwrap(try rows().first { $0.dateString == day(24).dateString })
        XCTAssertEqual(row.ownerPubkey, s.a)
        XCTAssertNotEqual(row.syncState, .synced)
        XCTAssertEqual(try outbox().filter(\.isLive).count, 1, "still queued for A")
    }

    // MARK: - L2: a guest day deleted while an account is connected

    func testAGuestDayDeletedWhileSignedInStaysAGuestTombstoneAndIsNeverAdopted() async throws {
        let guestDay = day(22)
        try repo().save(text: "written before signing in", for: guestDay)
        XCTAssertNil(try rows().first?.ownerPubkey)

        let (aSecret, a) = try importAccount()
        try repo().delete(guestDay)
        var row = try XCTUnwrap(try rows().first)
        XCTAssertNil(row.ownerPubkey, "deleting doesn't make it A's")
        XCTAssertEqual(row.entryKey, JournalEntry.key(owner: nil, dateString: guestDay.dateString))
        XCTAssertNotNil(row.deletedAt)
        XCTAssertEqual(row.notesText, "")

        // A's pass: not adopted, nothing signed or sent (no kind 5 for it).
        let aRelays = relays()
        try PublishDisclosure(context: context, owner: a).accept()
        await service(aRelays).run(owner: a, secret: aSecret, context: context)
        XCTAssertEqual(try FirstConnectSort(context: context, owner: a).run(), FirstConnectSort.Summary())
        row = try XCTUnwrap(try rows().first)
        XCTAssertNil(row.ownerPubkey, "A's pass didn't adopt it")
        XCTAssertNotNil(row.deletedAt)
        XCTAssertTrue(sentFrames(aRelays).isEmpty, "nothing published for a guest tombstone")
        XCTAssertTrue(try outbox().isEmpty)

        // Then B: the same.
        XCTAssertEqual(account.signOut(context: context), .signedOut)
        let (bSecret, b) = try importAccount()
        let bRelays = relays()
        try PublishDisclosure(context: context, owner: b).accept()
        await service(bRelays).run(owner: b, secret: bSecret, context: context)
        let all = try rows()
        XCTAssertEqual(all.count, 1)
        XCTAssertNil(all[0].ownerPubkey, "B's pass didn't adopt it")
        XCTAssertNotNil(all[0].deletedAt)
        XCTAssertEqual(all[0].notesText, "")
        XCTAssertTrue(sentFrames(bRelays).isEmpty)
        XCTAssertTrue(try outbox().isEmpty)
        XCTAssertEqual(account.unsyncedCount(context: context), JournalRepository.SignOutCounts(unsaved: 0, guest: 0),
                       "not counted as anyone's unsaved day")
    }
}
