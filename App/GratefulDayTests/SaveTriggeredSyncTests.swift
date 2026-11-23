import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Passes after a local save (Seth's Priority A, 2026-11-22; Prep §2.2
/// R1–R5): debounced, foreground only, never before the disclosure, never
/// overlapping, and keeping every publishing rule of the pass itself.
@MainActor
final class SaveTriggeredSyncTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!
    private var day: JournalDay {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return JournalDay(containing: cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!, timeZone: zone)
    }

    /// How many passes the service asked the app for, and whether one was
    /// asked for while another was still reading.
    private var runs = 0
    private var overlapped = false

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        runs = 0
        overlapped = false
    }

    // MARK: - Helpers

    private var repository: JournalRepository { JournalRepository(context: context, activeOwner: owner) }

    private func acceptDisclosure() throws {
        try PublishDisclosure(context: context, owner: owner).accept()
    }

    /// The default relays as fakes; `slow` hosts never answer a REQ, so each
    /// read of a pass waits out the 0.3 s page timeout.
    private func defaults(slow: Set<String> = [], configure: (FakeRelay) -> Void = { _ in }) -> [String: FakeRelay] {
        Dictionary(uniqueKeysWithValues: RelaySet.defaultRead.map { url -> (String, FakeRelay) in
            let r = FakeRelay(url.host!, behavior: slow.contains(url.host!) ? .silent : .normal)
            configure(r)
            return (url.host!, r)
        })
    }

    /// A service wired as the app wires it: in the foreground, with the
    /// disclosure check and a runner that starts a pass.
    private func service(_ relays: [String: FakeRelay], debounce: Duration = .milliseconds(200)) -> SyncService {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.values.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        let sync = SyncService(fetcher: fetcher, publisher: publisher)
        sync.saveDebounce = debounce
        sync.isForeground = true
        sync.isActive = true
        let context = context, owner = owner, secret = secret
        sync.publishAllowed = { (try? PublishDisclosure(context: context, owner: owner).isAccepted()) ?? false }
        sync.runner = { [unowned self, unowned sync] in
            runs += 1
            if sync.status == .reading { overlapped = true }
            sync.start(owner: owner, secret: secret, context: context) { true }
        }
        return sync
    }

    /// Save as the editor does, then signal as the app does.
    private func save(_ text: String, _ sync: SyncService) throws {
        try repository.save(text: text, for: day)
        sync.localChangeSaved()
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let started = Date()
        while !condition(), Date().timeIntervalSince(started) < timeout { try await Task.sleep(for: .milliseconds(20)) }
    }

    private func settle(_ seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }

    private func syncState() throws -> SyncState? { try repository.entry(for: day.dateString)?.syncState }

    private func frames(_ relays: [String: FakeRelay]) -> Int { relays.values.map(\.publishedFrames.count).reduce(0, +) }

    // MARK: - Tests

    /// R2: a burst of saves (the editor saves every 0.5 s while typing)
    /// makes one pass and one publish, after the quiet time.
    func testRapidSavesMakeOnePassAndOnePublish() async throws {
        try acceptDisclosure()
        let relays = defaults()
        let sync = service(relays)
        for i in 1...6 {
            try save("typing \(i)", sync)
            try await settle(0.05)
        }
        XCTAssertEqual(runs, 0, "no pass while saves keep coming")
        try await waitUntil { sync.lastPublish != nil }
        try await settle(0.5)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(sync.lastPublish?.signed, 1)
        XCTAssertEqual(relays["nos.lol"]!.publishedFrames.count, 1, "one version, not one per save")
        XCTAssertEqual(try syncState(), .synced)
        XCTAssertFalse(overlapped)
    }

    /// R2: the quiet time is about 30 s and never under 15 s.
    func testQuietTimeIsAtLeastFifteenSeconds() {
        XCTAssertGreaterThanOrEqual(SyncService.saveQuietTime, .seconds(15))
        XCTAssertEqual(SyncService().saveDebounce, SyncService.saveQuietTime)
    }

    /// R1: before the disclosure, a save starts no pass, reads no relay and
    /// never brings up the sheet (no `.notAllowedYet` from a save).
    func testSaveBeforeDisclosureStartsNothing() async throws {
        let relays = defaults()
        let sync = service(relays)
        try save("private until told", sync)
        try await settle(0.6)
        sync.flushPendingSave()
        try await settle(0.2)
        XCTAssertEqual(runs, 0)
        XCTAssertNil(sync.publishDeferral, "the state that opens the sheet is never set by a save")
        XCTAssertTrue(relays.values.allSatisfy { $0.requests.isEmpty && $0.publishedFrames.isEmpty })
        XCTAssertEqual(try syncState(), .localOnly)
    }

    /// Foreground only: a save in the background starts nothing, and going to
    /// the background cancels a pass that's waiting for the quiet time.
    func testNoPassOutsideTheForeground() async throws {
        try acceptDisclosure()
        let relays = defaults()
        let sync = service(relays)
        sync.isForeground = false
        try save("written while leaving", sync)
        try await settle(0.5)
        XCTAssertEqual(runs, 0)

        sync.isForeground = true
        try save("written, then locked", sync)
        sync.isForeground = false
        sync.stop()
        try await settle(0.5)
        XCTAssertEqual(runs, 0, "the waiting pass was cancelled")
        XCTAssertEqual(frames(relays), 0)
        XCTAssertEqual(try syncState(), .localOnly, "R5: the text stays on disk, still Saving")
    }

    /// R2: leaving Today (or the app becoming inactive) starts the waiting
    /// pass now, not after the quiet time.
    func testLeavingTheEditorStartsTheWaitingPassNow() async throws {
        try acceptDisclosure()
        let relays = defaults()
        let sync = service(relays, debounce: .seconds(60))
        try save("done for today", sync)
        sync.flushPendingSave()
        try await waitUntil { sync.lastPublish != nil }
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(try syncState(), .synced)
        sync.flushPendingSave()
        try await settle(0.3)
        XCTAssertEqual(runs, 1, "nothing waiting, nothing started")
    }

    /// R2: a save that lands as the app goes inactive (the editor flushing)
    /// starts its pass now, whichever of the two scene-phase handlers runs first.
    func testSaveWhileInactiveStartsThePassNow() async throws {
        try acceptDisclosure()
        let relays = defaults()
        let sync = service(relays, debounce: .seconds(60))
        sync.isActive = false
        sync.flushPendingSave()
        try save("last words before the lock", sync)
        try await waitUntil { sync.lastPublish != nil }
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(try syncState(), .synced)
    }

    /// No overlapping passes: a save while a pass is reading queues exactly
    /// one more pass, which starts after the first has finished.
    func testSaveDuringAPassRunsOneMorePassAfterIt() async throws {
        try acceptDisclosure()
        // nostr.wine (read only) never answers: each read takes 0.3 s.
        let relays = defaults(slow: ["nostr.wine"])
        let sync = service(relays, debounce: .milliseconds(50))
        try save("first thought", sync)
        try await waitUntil { sync.status == .reading }
        XCTAssertEqual(runs, 1)
        try save("first thought, and a second", sync)
        try save("first thought, and a second, and a third", sync)
        try await waitUntil { sync.followUpRequested }
        XCTAssertTrue(sync.followUpRequested)
        try await waitUntil(10) { runs == 2 && !sync.followUpRequested && sync.status != .reading && sync.lastPublish != nil }
        try await settle(0.3)
        XCTAssertEqual(runs, 2, "one pass queued, not one per save")
        XCTAssertFalse(overlapped, "the second pass started only after the first finished")
        XCTAssertEqual(try syncState(), .synced, "the newest text was published")
        XCTAssertEqual(try repository.entry(for: day.dateString)?.notesText, "first thought, and a second, and a third")
    }

    /// Interrupted pass (R5): leaving the foreground mid-pass cancels it and
    /// drops the queued pass; the day stays Saving, never synced.
    func testBackgroundMidPassDropsTheQueuedPassAndKeepsTheDaySaving() async throws {
        try acceptDisclosure()
        let relays = defaults(slow: ["nostr.wine"])
        let sync = service(relays, debounce: .milliseconds(50))
        try save("half a thought", sync)
        try await waitUntil { sync.status == .reading }
        try save("half a thought, more", sync)
        try await waitUntil { sync.followUpRequested }
        sync.isForeground = false
        sync.stop()
        XCTAssertFalse(sync.followUpRequested)
        try await waitUntil { sync.status != .reading }
        try await settle(0.5)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(frames(relays), 0, "cancelled before the send")
        XCTAssertEqual(try syncState(), .localOnly)
        XCTAssertFalse(sync.retryPending)
    }

    /// Offline (R4): a save while no relay connects runs one pass, publishes
    /// nothing, shows the existing couldn't-reach state and doesn't loop.
    func testOfflineSaveRunsOnePassAndDoesNotLoop() async throws {
        try acceptDisclosure()
        let relays = Dictionary(uniqueKeysWithValues: RelaySet.defaultRead.map { ($0.host!, FakeRelay($0.host!, behavior: .refuseConnect)) })
        let sync = service(relays)
        sync.minimumRetryDelay = 0.1
        try save("on a plane", sync)
        try await waitUntil { runs == 1 && sync.status != .reading && sync.couldNotReach }
        try await settle(0.8)
        XCTAssertEqual(runs, 1)
        XCTAssertTrue(sync.couldNotReach)
        XCTAssertFalse(sync.retryPending, "an incomplete read schedules no retry")
        XCTAssertEqual(try syncState(), .localOnly)
    }

    /// Retries (R4): a day acknowledged by one write relay of three waits its
    /// backoff (30 s), then a foreground retry resends the same signed event,
    /// and two acknowledgements make it synced. Nothing retries after that.
    func testForegroundRetryWaitsTheBackoffAndResendsTheSameEvent() async throws {
        try acceptDisclosure()
        let relays = defaults { r in
            if r.url.host == "relay.primal.net" || r.url.host == "relay.damus.io" { r.okReply = .reject }
        }
        let sync = service(relays)
        final class Clock { var value = Date() }
        let clock = Clock()
        var waits: [TimeInterval] = []
        sync.now = { clock.value }
        sync.retrySleep = { seconds in
            waits.append(seconds)
            clock.value += seconds
            try? await Task.sleep(for: .milliseconds(20))
        }
        try save("worth keeping", sync)
        try await waitUntil { sync.lastPublish != nil && sync.retryPending }
        XCTAssertEqual(sync.lastPublish?.synced, 0, "one acknowledgement of three")
        XCTAssertEqual(try syncState(), .localOnly)
        let first = try XCTUnwrap(relays["nos.lol"]!.publishedFrames.first)
        relays["relay.primal.net"]!.okReply = .accept
        try await waitUntil { runs == 2 && sync.status != .reading && sync.lastPublish?.synced == 1 }
        try await settle(0.3)
        XCTAssertEqual(waits.first ?? 0, DeliveryRules.backoff(afterAttempts: 1), accuracy: 1)
        XCTAssertEqual(relays["relay.primal.net"]!.publishedFrames.last, first, "the same signed event, byte for byte")
        XCTAssertEqual(try syncState(), .synced)
        XCTAssertFalse(sync.retryPending, "nothing left to retry")
        XCTAssertEqual(runs, 2)
    }

    /// The signal the app listens for: posted for a changed save or a
    /// delete, not for a save that changes nothing.
    func testRepositoryPostsJournalEditedOnlyForRealChanges() throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        var posts: Int { counter.value }
        let token = NotificationCenter.default.addObserver(forName: .journalEdited, object: nil, queue: nil) { _ in counter.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }
        try repository.save(text: "one", for: day)
        XCTAssertEqual(posts, 1)
        try repository.save(text: "one", for: day)
        XCTAssertEqual(posts, 1, "unchanged text: no signal")
        try repository.save(text: "one, two", for: day)
        XCTAssertEqual(posts, 2)
        try repository.delete(day)
        XCTAssertEqual(posts, 3)
    }

    /// Prep §2.3 copy, word for word.
    func testDisclosureCopyForAutomaticBackup() {
        XCTAssertEqual(DisclosureCopy.automatic, "After this, what you write is backed up to your account automatically.")
        let seen = DisclosureCopy.learnMoreSections.first { $0.title == "Can be seen by others" }
        XCTAssertTrue(seen?.after.contains("Grateful Day backs up a reflection a little while after you stop writing, so one sitting usually shows as one edit.") == true)
    }
}
