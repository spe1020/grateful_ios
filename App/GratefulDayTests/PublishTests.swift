import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// M5b-2 slice 1: the publish client, the outbox and the §0.1 rules
/// (M5b plan r2 (a)/(b), r2.1; Seth 5c471a7e, 3f1c5fd4).
@MainActor
final class PublishTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private var outbox: Outbox { Outbox(context: container.mainContext, owner: owner) }

    private func fakes(_ relays: [FakeRelay]) -> FakeTransport {
        FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
    }

    private func day(_ date: String) -> DailyEntry.Day {
        let zone = TimeZone(identifier: "America/Chicago")!
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func signed(_ date: String, _ text: String, at: Int, key: Data? = nil) throws -> NostrEvent {
        let k = key ?? secret
        return try DailyEntry.privateTemplate(day: day(date), notes: [text], privateKey: k).signed(privateKey: k, createdAt: at)
    }

    private func publisher(_ relays: [FakeRelay]) -> RelayPublisher {
        var p = RelayPublisher(transport: fakes(relays)); p.timeout = .milliseconds(300); return p
    }

    private func urls(_ relays: [FakeRelay]) -> [URL] { relays.map(\.url) }

    // Acknowledgements

    func testOkTrueCountsDuplicateCountsOkFalseAndNoticeDoNot() async throws {
        let event = try signed("2026-11-20", "hello", at: 1_000)
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        let replies: [(String, FakeRelay.OkReply)] = [("a", .accept), ("b", .duplicate), ("c", .reject), ("d", .noticeOnly), ("e", .otherId)]
        let relays = replies.map { name, reply -> FakeRelay in let r = FakeRelay(name); r.okReply = reply; return r }
        let out = await publisher(relays).publish(json: json, eventId: event.id, to: urls(relays))
        XCTAssertEqual(out[relays[0].url], .accepted)
        XCTAssertEqual(out[relays[1].url], .accepted, "duplicate: the relay holds that exact event")
        XCTAssertEqual(out[relays[2].url], .rejected("blocked: no"))
        XCTAssertEqual(out[relays[3].url], .timedOut, "a NOTICE never counts")
        XCTAssertEqual(out[relays[4].url], .timedOut, "an OK for another id never counts")
        for r in relays { XCTAssertGreaterThanOrEqual(r.closeCount, 1, "socket closed") }
    }

    /// Stuck-on-Saving fix: the EVENT send sat outside the timeout. A write
    /// relay whose socket never finishes connecting held the whole publish,
    /// and the acknowledgements other relays had already given, until
    /// URLSession gave up (60 s). It is timed out with the rest, and a
    /// timeout is never an acknowledgement.
    func testWriteRelayThatNeverConnectsTimesOutAndIsNeverAnAcknowledgement() async throws {
        let event = try signed("2026-11-20", "hello", at: 1_000)
        let json = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        let good = FakeRelay("a"), hung = FakeRelay("b", behavior: .neverConnects)
        let started = Date()
        let out = await publisher([good, hung]).publish(json: json, eventId: event.id, to: [good.url, hung.url])
        XCTAssertLessThan(Date().timeIntervalSince(started), 3, "bounded by the publish timeout")
        XCTAssertEqual(out[good.url], .accepted)
        XCTAssertEqual(out[hung.url], .timedOut, "unknown: not accepted, not rejected")
        XCTAssertTrue(hung.publishedFrames.isEmpty, "nothing reached it")
        XCTAssertGreaterThanOrEqual(hung.closeCount, 1, "the socket is closed, not left connecting")
        let write = [good.url, hung.url]
        let row = try outbox.enqueue(event, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        try outbox.record(out, for: row, write: write)
        XCTAssertEqual(row.ackedRelays, [good.url.absoluteString])
        XCTAssertEqual(DeliveryRules.state(acked: row.ackedRelays, write: write), .sent, "one of two: not synced")
    }

    func testSyncedNeedsTwoDistinctRelays() {
        let write = ["wss://a", "wss://b", "wss://c"].map { URL(string: $0)! }
        XCTAssertEqual(DeliveryRules.state(acked: [], write: write), .localOnly)
        XCTAssertEqual(DeliveryRules.state(acked: ["wss://a"], write: write), .sent)
        XCTAssertEqual(DeliveryRules.state(acked: ["wss://a", "wss://a"], write: write), .sent)
        XCTAssertEqual(DeliveryRules.state(acked: ["wss://a", "wss://elsewhere"], write: write), .sent,
                       "only the write set's relays count")
        XCTAssertEqual(DeliveryRules.state(acked: ["wss://a", "wss://c"], write: write), .synced)
    }

    func testSingleWriteRelayOneAckIsSynced() {
        let write = [URL(string: "wss://only")!]
        XCTAssertEqual(DeliveryRules.required(write: write), 1)
        XCTAssertEqual(DeliveryRules.state(acked: ["wss://only"], write: write), .synced)
    }

    func testZeroOrUnknownWriteRelaysNeverRequireOrSync() {
        XCTAssertNil(DeliveryRules.required(write: []))
        XCTAssertNil(DeliveryRules.required(write: nil))
        XCTAssertEqual(DeliveryRules.state(acked: ["wss://a", "wss://b"], write: nil), .sent, "an unknown set confirms nothing")
    }

    // Outbox

    func testRetryResendsSameSignedEventByteForByte() async throws {
        let event = try signed("2026-11-20", "hello", at: 1_000)
        let row = try outbox.enqueue(event, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        let relay = FakeRelay("a"); relay.okReply = .silent
        let p = publisher([relay])
        _ = await p.publish(json: row.eventJSON, eventId: row.eventId, to: [relay.url])
        relay.okReply = .accept
        _ = await p.publish(json: row.eventJSON, eventId: row.eventId, to: [relay.url])
        XCTAssertEqual(relay.publishedFrames.count, 2)
        XCTAssertEqual(relay.publishedFrames[0], relay.publishedFrames[1], "same frame byte for byte")
        XCTAssertEqual(relay.publishedFrames[0], "[\"EVENT\"," + row.eventJSON + "]")
        let sent = try JSONDecoder().decode(NostrEvent.self, from: Data(row.eventJSON.utf8))
        XCTAssertEqual(sent, event, "same id, created_at and sig")
    }

    func testNewerEditSupersedesQueuedEventWhichIsNeverResent() throws {
        let first = try signed("2026-11-20", "one", at: 1_000)
        let second = try signed("2026-11-20", "two", at: 1_001)
        let other = try signed("2026-11-21", "other", at: 1_000)
        let a = try outbox.enqueue(first, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        try outbox.record([URL(string: "wss://a")!: .accepted], for: a, write: nil)
        let b = try outbox.enqueue(second, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        try outbox.enqueue(other, dateString: "2026-11-21", baseEventId: nil, baseCreatedAt: nil)
        XCTAssertTrue(a.superseded, "partly delivered, still superseded")
        XCTAssertEqual(try outbox.liveRow(dateString: "2026-11-20")?.eventId, b.eventId)
        let due = try outbox.due(write: nil, now: .distantFuture).map(\.eventId)
        XCTAssertFalse(due.contains(first.id), "never sent again")
        XCTAssertEqual(Set(due), [second.id, other.id])
        XCTAssertEqual(try outbox.state(dateString: "2026-11-20", write: nil), .localOnly,
                       "only the newest row's acknowledgements count")
    }

    func testFailedAttemptBacksOffAndSyncedRowIsNotDue() throws {
        let write = ["wss://a", "wss://b"].map { URL(string: $0)! }
        let row = try outbox.enqueue(try signed("2026-11-20", "x", at: 1), dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        try outbox.record([write[0]: .accepted, write[1]: .timedOut], for: row, write: write, now: t0)
        XCTAssertEqual(row.nextAttemptAt, t0.addingTimeInterval(30))
        XCTAssertTrue(try outbox.due(write: write, now: t0).isEmpty, "not before its backoff")
        XCTAssertEqual(try outbox.due(write: write, now: t0.addingTimeInterval(31)).count, 1)
        try outbox.record([write[1]: .accepted], for: row, write: write, now: t0.addingTimeInterval(31))
        XCTAssertEqual(try outbox.state(dateString: "2026-11-20", write: write), .synced)
        XCTAssertTrue(try outbox.due(write: write, now: .distantFuture).isEmpty)
        XCTAssertEqual([1, 2, 3, 4, 9].map(DeliveryRules.backoff(afterAttempts:)), [30, 120, 600, 3600, 3600])
    }

    func testOutboxRowsAreOwnedByTheirAccount() throws {
        let other = try NostrKeys.generatePrivateKey()
        let otherOwner = KeyVault.pubkeyHex(for: other)!
        try Outbox(context: container.mainContext, owner: otherOwner)
            .enqueue(try signed("2026-11-20", "theirs", at: 1, key: other), dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        XCTAssertTrue(try outbox.due(write: nil, now: .distantFuture).isEmpty, "another account's rows are never sent")
        XCTAssertNil(try outbox.liveRow(dateString: "2026-11-20"))
    }

    // §0.1 pre-send check (r2.1 item 2; E6/E7)

    private func check(base: String? = nil, own: Set<String> = [], events: [NostrEvent] = [],
                       outcomes: [String: RelayOutcome], write: [String]?) -> DeliveryRules.Check {
        let fetched = FetchResult(events: events, outcomes: Dictionary(uniqueKeysWithValues: outcomes.map { (URL(string: $0.key)!, $0.value) }))
        return DeliveryRules.preSendCheck(day: "2026-11-20", owner: owner, baseEventId: base, ownEventIds: own,
                                          fetched: fetched, write: write?.map { URL(string: $0)! })
    }

    func testTwoEmptyWriteRelaysAllowPublish() {
        XCTAssertEqual(check(outcomes: ["wss://a": .answered, "wss://b": .answered, "wss://c": .timedOut],
                             write: ["wss://a", "wss://b", "wss://c"]), .clear)
    }

    func testOneEmptyWriteRelayOfThreeBlocks() {
        XCTAssertEqual(check(outcomes: ["wss://a": .answered, "wss://b": .timedOut, "wss://c": .closed("auth-required")],
                             write: ["wss://a", "wss://b", "wss://c"]), .unresolved)
    }

    func testReadRelaysNeverCountTowardNoCopy() {
        XCTAssertEqual(check(outcomes: ["wss://a": .answered, "wss://read1": .answered, "wss://read2": .answered],
                             write: ["wss://a", "wss://b"]), .unresolved)
    }

    func testSaturatedRelayNeverCountsTowardNoCopy() {
        XCTAssertEqual(check(outcomes: ["wss://a": .answered, "wss://b": .unresolved("saturated second")],
                             write: ["wss://a", "wss://b"]), .unresolved)
    }

    func testSingleWriteRelayOneEmptyLookupPublishes() {
        XCTAssertEqual(check(outcomes: ["wss://only": .answered], write: ["wss://only"]), .clear)
    }

    func testSingleWriteRelayTimeoutDefers() {
        XCTAssertEqual(check(outcomes: ["wss://only": .timedOut], write: ["wss://only"]), .unresolved)
    }

    func testZeroOrUnknownWriteRelaysNeverClear() {
        XCTAssertEqual(check(outcomes: ["wss://r": .answered], write: []), .unresolved)
        XCTAssertEqual(check(outcomes: ["wss://r": .answered], write: nil), .unresolved)
    }

    func testNewerCopyOnAnyReadRelayStopsTheSend() throws {
        let web = try signed("2026-11-20", "from web", at: 2_000)
        XCTAssertEqual(check(events: [web], outcomes: ["wss://read": .answered], write: ["wss://a", "wss://b"]),
                       .unbasedRemote(web), "found on a read relay, with write relays silent")
    }

    func testFirstSendAlsoRechecksAndStopsOnUnseenVersion() throws {
        let older = try signed("2026-11-20", "B's older edit", at: 500)
        XCTAssertEqual(check(base: nil, events: [older], outcomes: ["wss://a": .answered, "wss://b": .answered],
                             write: ["wss://a", "wss://b"]), .unbasedRemote(older), "any timestamp, not just newer")
    }

    func testBaseAndOwnEventsDoNotStopTheSend() throws {
        let base = try signed("2026-11-20", "base", at: 500)
        let mine = try signed("2026-11-20", "mine", at: 600)
        let otherDay = try signed("2026-11-21", "other day", at: 700)
        let stranger = try signed("2026-11-20", "not the owner", at: 900, key: try NostrKeys.generatePrivateKey())
        XCTAssertEqual(check(base: base.id, own: [mine.id], events: [base, mine, otherDay, stranger],
                             outcomes: ["wss://a": .answered, "wss://b": .answered], write: ["wss://a", "wss://b"]), .clear)
    }

    func testUnresolvedPreSendRefetchDefersQuietly() throws {
        let base = try signed("2026-11-20", "base", at: 500)
        XCTAssertEqual(check(base: base.id, events: [base], outcomes: ["wss://a": .answered, "wss://b": .timedOut],
                             write: ["wss://a", "wss://b"]), .unresolved)
    }
}

/// V5 (M5b-1-built fixture) -> V6.
@MainActor
final class V6MigrationTests: XCTestCase {
    func testV5StoreMigratesToV6() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "v5-journal", withExtension: "store"))
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: location.storeURL)
        let store = JournalStore(location: location, defaults: UserDefaults(suiteName: "v6-\(UUID().uuidString)")!)
        store.openIfPossible(protectedDataAvailable: true)
        let ctx = try XCTUnwrap(store.container, "\(store.state)").mainContext
        let rows = try ctx.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
        let owner = String(repeating: "b", count: 64)
        XCTAssertEqual(rows.map(\.notesText), ["Guest note", "Synced note"])
        XCTAssertEqual(rows.map(\.ownerPubkey), [nil, owner])
        XCTAssertEqual(rows[1].syncState, .synced)
        XCTAssertEqual(rows[1].remoteEventID, String(repeating: "c", count: 64))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AccountMarker>()).first?.state, .connected)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<EarlierVersion>()).map(\.notesText), ["Earlier note"])
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<OutboxEvent>()).isEmpty)
        XCTAssertTrue(try JournalRepository(context: ctx).flag(JournalFlag.reminderOfferShown))
    }
}
