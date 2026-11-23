import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Relay reliability, Priority B (write-up RESEARCH/GRATEFUL_DAY_IOS_RELAY_RELIABILITY_2026_11_22.md;
/// Chief 2dfa43a6): a relay whose socket never opened is remembered for
/// 10 minutes across passes, and the journal and settings are read in
/// parallel. Neither changes any relay list or any publishing rule.
@MainActor
final class RelayMemoryTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!
    private final class Clock { var value = Date(timeIntervalSince1970: 1_800_000_000) }
    private let clock = Clock()

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    // MARK: - Helpers

    private var band: URL { URL(string: "wss://relay.nostr.band")! }

    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func entry(_ date: String, _ text: String) throws {
        let d = day(date)
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: text, now: clock.value, ownerPubkey: owner))
        try context.save()
    }

    private func row(_ date: String) throws -> JournalEntry {
        let key: String? = JournalEntry.key(owner: owner, dateString: date)
        return try XCTUnwrap(context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first)
    }

    private func accept() throws {
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
    }

    private func service(_ relays: [FakeRelay], pageTimeout: Duration = .milliseconds(300)) -> SyncService {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = pageTimeout
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        let sync = SyncService(fetcher: fetcher, publisher: publisher)
        let clock = clock
        sync.now = { clock.value }
        return sync
    }

    /// The defaults with relay.nostr.band never finishing its connection.
    private func defaults(_ configure: (FakeRelay) -> Void = { _ in }) -> [FakeRelay] {
        RelaySet.defaultRead.map { url in
            let r = FakeRelay(url.host!, behavior: url.host == "relay.nostr.band" ? .neverConnects : .normal)
            configure(r)
            return r
        }
    }

    private func pass(_ sync: SyncService) async {
        await sync.run(owner: owner, secret: secret, context: context)
    }

    private func relayList(_ urls: [String]) throws -> NostrEvent {
        try UnsignedEvent(kind: 10002, tags: urls.map { ["r", $0] }, content: "").signed(privateKey: secret, createdAt: 1)
    }

    // MARK: - Remembering a relay that never connected

    /// Remembered for 10 minutes, then dialed again; a relay that opened is
    /// never remembered.
    func testRelayThatNeverConnectedIsRememberedForTenMinutes() async throws {
        executionTimeAllowance = 60
        let relays = defaults()
        let byHost = Dictionary(uniqueKeysWithValues: relays.map { ($0.url.host!, $0) })
        let sync = service(relays)
        await pass(sync)
        XCTAssertEqual(byHost["relay.nostr.band"]!.connectCount, 1)
        XCTAssertEqual(sync.rememberedUnreachable(), [band])

        // 9 min 59 s later: not dialed at all.
        clock.value += 599
        await pass(sync)
        XCTAssertEqual(byHost["relay.nostr.band"]!.connectCount, 1, "remembered: not dialed")
        XCTAssertEqual(sync.rememberedUnreachable(), [band], "still from the first pass, not renewed")

        // 10 minutes after it was first seen: dialed again, and remembered again.
        clock.value += 1
        XCTAssertEqual(sync.rememberedUnreachable(), [], "expired")
        await pass(sync)
        XCTAssertEqual(byHost["relay.nostr.band"]!.connectCount, 2, "dialed again after 10 minutes")
        XCTAssertEqual(sync.rememberedUnreachable(), [band])
        XCTAssertFalse(sync.rememberedUnreachable().contains(URL(string: "wss://nos.lol")!))
    }

    /// In memory only: forgotten by `reset()` (sign-out, another account,
    /// the store replaced), and a cancelled pass adds nothing, since its
    /// sockets were closed while they were still opening.
    func testMemoryIsForgottenOnResetAndNotLearnedFromAStoppedPass() async throws {
        executionTimeAllowance = 60
        let relays = defaults()
        let sync = service(relays)
        await pass(sync)
        XCTAssertEqual(sync.rememberedUnreachable(), [band])
        sync.reset()
        XCTAssertEqual(sync.rememberedUnreachable(), [], "reset forgets")

        // A pass stopped while every relay is still opening learns nothing.
        let slow = RelaySet.defaultRead.map { FakeRelay($0.host!, behavior: .neverConnects) }
        let stopped = service(slow)
        let task = Task { await self.pass(stopped) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        XCTAssertEqual(stopped.rememberedUnreachable(), [], "nothing learned from a cancelled pass")

        // Nor one whose account changed during the reads.
        let changed = service(defaults())
        await changed.run(owner: owner, secret: secret, context: context, isCurrent: { false })
        XCTAssertEqual(changed.rememberedUnreachable(), [])
    }

    /// The two-answer rule: a remembered relay is never an answer. With only
    /// one bootstrap relay answering, the relay list stays unknown on the
    /// next pass too, and nothing is published to the defaults.
    func testRememberedRelayNeverCountsAsABootstrapAnswer() async throws {
        executionTimeAllowance = 60
        try entry("2026-11-20", "stays here")
        try accept()
        let relays = RelaySet.defaultRead.enumerated().map { FakeRelay($1.host!, behavior: $0 == 0 ? .normal : .neverConnects) }
        let sync = service(relays)
        await pass(sync)
        XCTAssertEqual(sync.rememberedUnreachable().count, 4)
        await pass(sync)
        XCTAssertTrue(relays.dropFirst().allSatisfy { $0.connectCount == 1 }, "remembered: not dialed again")
        XCTAssertEqual(sync.publishDeferral, .relayListUnknown)
        XCTAssertNil(sync.relays?.write, "unknown, never the defaults")
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
    }

    /// The two-answer rule before a send: a remembered write relay is never
    /// "answered", so with one of two write relays reachable nothing is sent.
    func testRememberedWriteRelayNeverCountsAsAnsweredBeforeASend() async throws {
        executionTimeAllowance = 60
        try entry("2026-11-20", "stays here")
        try accept()
        let list = try relayList(["wss://nos.lol", "wss://relay.nostr.band"])
        let relays = RelaySet.defaultRead.map {
            FakeRelay($0.host!, events: [list], behavior: $0.host == "relay.nostr.band" ? .neverConnects : .normal)
        }
        let sync = service(relays)
        await pass(sync)
        clock.value += 120
        await pass(sync)
        XCTAssertEqual(relays.first { $0.url == band }!.connectCount, 1)
        XCTAssertEqual(sync.lastPublish?.sent, 0)
        XCTAssertEqual(sync.lastPublish?.deferred, 1, "one of two write relays answered: unknown, not sent")
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
    }

    /// The two-acknowledgement rule: a remembered write relay is never an
    /// acknowledgement. Three write relays; one never connects, one rejects:
    /// one OK, so the day isn't synced on either pass, and the remembered
    /// relay is neither dialed nor counted on the retry.
    func testRememberedWriteRelayIsNeverAnAcknowledgement() async throws {
        executionTimeAllowance = 60
        try entry("2026-11-20", "half saved")
        try accept()
        let list = try relayList(["wss://nos.lol", "wss://relay.primal.net", "wss://relay.nostr.band"])
        let relays = RelaySet.defaultRead.map { url -> FakeRelay in
            let r = FakeRelay(url.host!, events: [list], behavior: url.host == "relay.nostr.band" ? .neverConnects : .normal)
            if url.host == "relay.primal.net" { r.okReply = .reject }
            return r
        }
        let sync = service(relays)
        await pass(sync)
        XCTAssertEqual(sync.lastPublish?.sent, 1)
        XCTAssertEqual(sync.lastPublish?.synced, 0)
        // Past the 30 s backoff, still inside the 10 minutes.
        clock.value += 31
        await pass(sync)
        let bandRelay = relays.first { $0.url == band }!
        XCTAssertEqual(bandRelay.connectCount, 1, "remembered: not dialed for the retry")
        XCTAssertTrue(bandRelay.publishedFrames.isEmpty)
        XCTAssertEqual(sync.lastPublish?.synced, 0, "one acknowledgement of three: not synced")
        let live = try XCTUnwrap(Outbox(context: context, owner: owner).liveRow(dateString: "2026-11-20"))
        XCTAssertEqual(live.ackedRelays, ["wss://nos.lol"], "the remembered relay is never an acknowledgement")
        XCTAssertNotEqual(try row("2026-11-20").syncState, .synced)
    }

    // MARK: - Journal and settings read in parallel

    /// Two queries on one pass transport at once: each keeps its own events
    /// and its own outcome per relay, and an unanswered relay stays unknown
    /// in each (the `.unresolved` rule per source).
    func testParallelReadsKeepTheirOwnOutcomes() async throws {
        executionTimeAllowance = 60
        let journalEvent = try DailyEntry.privateTemplate(day: day("2026-11-20"), notes: ["hi"], privateKey: secret)
            .signed(privateKey: secret, createdAt: 1_000)
        let good = FakeRelay("a", events: [journalEvent])
        let silent = FakeRelay("b", behavior: .silent)
        let hung = FakeRelay("c", behavior: .neverConnects)
        let relays = [good, silent, hung]
        var fetcher = RelayFetcher(transport: PassTransport(
            base: FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) })), unreachable: .init()))
        fetcher.pageTimeout = .seconds(2)
        let urls = relays.map(\.url)
        let reader = fetcher, owner = owner
        async let journal = reader.fetch(RelayFilter(authors: [owner], kinds: [DailyEntry.kind, 5]), from: urls)
        async let settings = reader.fetch(RelayFilter(authors: [owner], kinds: [AppSettings.kind], tagD: [AppSettings.dTag]), from: urls)
        let (j, s) = await (journal, settings)
        // Both REQs reached the silent relay well inside one page timeout:
        // the second didn't wait for the first to time out.
        XCTAssertEqual(silent.requestTimes.count, 2)
        XCTAssertLessThan(abs(silent.requestTimes[1].timeIntervalSince(silent.requestTimes[0])), 1.5, "the reads overlap")
        for result in [j, s] {
            XCTAssertEqual(result.outcomes[good.url], .answered)
            XCTAssertEqual(result.outcomes[silent.url], .timedOut, "unknown, never read as empty")
            XCTAssertNotEqual(result.outcomes[hung.url], .answered)
            XCTAssertFalse(result.allAnswered(urls))
        }
        XCTAssertEqual(j.events.map(\.id), [journalEvent.id])
        XCTAssertTrue(s.events.isEmpty, "the journal's events never land in the settings read")
        XCTAssertEqual(good.connectCount, 2, "each read on its own socket")
    }

    /// End to end: the pass sends its journal and settings reads together,
    /// and the day is still published only
    /// after both write relays answered the read before the send.
    func testPassReadsJournalAndSettingsAtTheSameTime() async throws {
        executionTimeAllowance = 60
        try entry("2026-11-20", "saved")
        try accept()
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!, behavior: $0.host == "nostr.wine" ? .silent : .normal) }
        let sync = service(relays, pageTimeout: .seconds(2))
        await pass(sync)
        // nostr.wine never answers, so each read waits its page timeout
        // (2 s) there. Its journal and settings REQs arrive together, not
        // one page timeout apart.
        let wine = relays.first { $0.url.host == "nostr.wine" }!
        let journalAt = try XCTUnwrap(zip(wine.requests, wine.requestTimes).first { ($0.0["kinds"] as? [Int]) == [DailyEntry.kind, 5] }?.1)
        let settingsAt = try XCTUnwrap(zip(wine.requests, wine.requestTimes).first { ($0.0["kinds"] as? [Int]) == [AppSettings.kind] }?.1)
        XCTAssertLessThan(abs(journalAt.timeIntervalSince(settingsAt)), 1.5, "the two reads overlap")
        XCTAssertEqual(sync.lastPublish?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }
}
