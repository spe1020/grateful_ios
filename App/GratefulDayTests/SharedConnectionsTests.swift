import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// A socket the test drives by hand: it records what the client sent, and
/// the test pushes relay frames or drops it. Closing is terminal, as with
/// `URLSessionWebSocketTask.cancel`.
final class ScriptedSocket: RelayConnection, @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var outbox: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private var isClosed = false
    private(set) var sent: [String] = []
    /// Called with each client frame (after it's recorded).
    var onSend: (@Sendable (String, ScriptedSocket) -> Void)?

    init(url: URL) { self.url = url }

    var closed: Bool { lock.withLock { isClosed } }
    var frames: [String] { lock.withLock { sent } }

    func send(_ text: String) async throws {
        let handler = try lock.withLock { () -> (@Sendable (String, ScriptedSocket) -> Void)? in
            if isClosed { throw URLError(.cancelled) }
            sent.append(text)
            return onSend
        }
        handler?(text, self)
    }

    func push(_ s: String) {
        lock.lock()
        if isClosed { lock.unlock(); return }
        if let w = waiter { waiter = nil; lock.unlock(); w.resume(returning: s); return }
        outbox.append(s)
        lock.unlock()
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            if !outbox.isEmpty { let s = outbox.removeFirst(); lock.unlock(); c.resume(returning: s); return }
            if isClosed { lock.unlock(); c.resume(throwing: URLError(.networkConnectionLost)); return }
            waiter = c
            lock.unlock()
        }
    }

    /// The relay (or network) drops the socket.
    func drop() { close() }

    func close() {
        lock.lock()
        isClosed = true
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(throwing: URLError(.networkConnectionLost))
    }
}

/// Dials a new `ScriptedSocket` each time and keeps them in order.
final class ScriptedTransport: RelayTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var made: [URL: [ScriptedSocket]] = [:]
    var configure: @Sendable (ScriptedSocket) -> Void = { _ in }
    var refuse: Set<URL> = []

    func connect(_ url: URL) async throws -> RelayConnection {
        if lock.withLock({ refuse.contains(url) }) { throw URLError(.cannotConnectToHost) }
        let s = ScriptedSocket(url: url)
        configure(s)
        lock.withLock { made[url, default: []].append(s) }
        return s
    }

    func sockets(_ url: URL) -> [ScriptedSocket] { lock.withLock { made[url] ?? [] } }
}

private func subscription(of frame: String) -> String? {
    SharedConnections.Lease.subscription(in: frame, command: "REQ")
}

private func eventId(of frame: String) -> String? {
    guard frame.hasPrefix("[\"EVENT\""),
          let a = try? JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [Any],
          a.count >= 2, let o = a[1] as? [String: Any] else { return nil }
    return o["id"] as? String
}

/// Seth M (option 2): one socket per relay per pass. Prep's acceptance
/// criteria (PLANS/GRATEFUL_DAY_M_FIRST_SYNC_ACCEPTANCE_2026_11_27.md):
/// I1, I3, F1–F5 and T3.
final class SharedConnectionsTests: XCTestCase {
    private let relay = URL(string: "wss://relay.example")!
    private let other = URL(string: "wss://other.example")!
    private let secret = try! NostrKeys.generatePrivateKey()
    private var pubkey: String { KeyVault.pubkeyHex(for: secret)! }

    private func event(_ text: String, at: Int = 1_000) throws -> NostrEvent {
        try UnsignedEvent(kind: 1, tags: [], content: text).signed(privateKey: secret, createdAt: at)
    }

    private func json(_ e: NostrEvent) throws -> String { String(decoding: try JSONEncoder().encode(e), as: UTF8.self) }

    private func fetcher(_ shared: SharedConnections, timeout: Duration = .seconds(2)) -> RelayFetcher {
        var f = RelayFetcher(transport: shared)
        f.pageTimeout = timeout
        return f
    }

    private func publisher(_ shared: SharedConnections, timeout: Duration = .seconds(2)) -> RelayPublisher {
        var p = RelayPublisher(transport: shared)
        p.timeout = timeout
        return p
    }

    private func waitFor(_ what: String, _ condition: () -> Bool) async throws {
        let started = Date()
        while !condition() {
            if Date().timeIntervalSince(started) > 3 { XCTFail("timed out waiting for \(what)"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: I1: queries on one socket keep their own results

    /// Two queries at once on one socket, their EOSEs interleaved (B's
    /// first): neither clears the other, and each gets only its own events.
    func testInterleavedQueriesOnOneSocketKeepTheirOwnResults() async throws {
        executionTimeAllowance = 60
        let base = ScriptedTransport()
        let shared = SharedConnections(base: base)
        let f = fetcher(shared)
        let a = RelayFilter(authors: [pubkey], kinds: [1], tagD: ["a"])
        let b = RelayFilter(authors: [pubkey], kinds: [1], tagD: ["b"])
        let ea = try event("for a"), eb = try event("for b", at: 1_001)
        let url = relay
        async let ra = f.fetch(a, from: [url])
        async let rb = f.fetch(b, from: [url])
        try await waitFor("both REQs") { base.sockets(relay).first?.frames.filter { $0.hasPrefix("[\"REQ\"") }.count == 2 }
        let socket = try XCTUnwrap(base.sockets(relay).first)
        let reqs = socket.frames.filter { $0.hasPrefix("[\"REQ\"") }
        let subA = try XCTUnwrap(reqs.first { $0.contains("\"a\"") }.flatMap(subscription))
        let subB = try XCTUnwrap(reqs.first { $0.contains("\"b\"") }.flatMap(subscription))
        XCTAssertNotEqual(subA, subB, "each query has its own subscription id")
        // B's event, then B's EOSE, then A's: B must not end A's page.
        socket.push("[\"EVENT\",\"\(subB)\",\(try json(eb))]")
        socket.push("[\"EOSE\",\"\(subB)\"]")
        try await waitFor("B's CLOSE") { socket.frames.contains { $0.contains("CLOSE") && $0.contains(subB) } }
        // B's second page.
        try await waitFor("B's page 2") { socket.frames.filter { $0.hasPrefix("[\"REQ\"") }.count == 3 }
        let subB2 = try XCTUnwrap(socket.frames.filter { $0.hasPrefix("[\"REQ\"") }.last.flatMap(subscription))
        socket.push("[\"EOSE\",\"\(subB2)\"]")
        let resultB = await rb
        XCTAssertEqual(resultB.outcomes[relay], .answered)
        XCTAssertEqual(resultB.events.map(\.id), [eb.id])
        socket.push("[\"EVENT\",\"\(subA)\",\(try json(ea))]")
        socket.push("[\"EOSE\",\"\(subA)\"]")
        try await waitFor("A's page 2") { socket.frames.filter { $0.hasPrefix("[\"REQ\"") }.count == 4 }
        let subA2 = try XCTUnwrap(socket.frames.filter { $0.hasPrefix("[\"REQ\"") }.last.flatMap(subscription))
        socket.push("[\"EOSE\",\"\(subA2)\"]")
        let resultA = await ra
        XCTAssertEqual(resultA.outcomes[relay], .answered)
        XCTAssertEqual(resultA.events.map(\.id), [ea.id], "B's event never lands in A's result")
        XCTAssertEqual(base.sockets(relay).count, 1, "one socket for both")
        shared.closeAll()
    }

    /// One query's EOSE never answers a query that is still waiting: A
    /// times out while B is answered on the same socket.
    func testAnotherQuerysEoseNeverAnswersAWaitingQuery() async throws {
        executionTimeAllowance = 60
        let base = ScriptedTransport()
        base.configure = { s in
            s.onSend = { frame, socket in
                // Answer only the "b" query, at once.
                if frame.hasPrefix("[\"REQ\""), frame.contains("\"b\""), let sub = subscription(of: frame) {
                    socket.push("[\"EOSE\",\"\(sub)\"]")
                }
            }
        }
        let shared = SharedConnections(base: base)
        let f = fetcher(shared, timeout: .milliseconds(400))
        let fa = RelayFilter(authors: [pubkey], kinds: [1], tagD: ["a"]), fb = RelayFilter(authors: [pubkey], kinds: [1], tagD: ["b"]), url = relay
        async let ra = f.fetch(fa, from: [url])
        async let rb = f.fetch(fb, from: [url])
        let (a, b) = await (ra, rb)
        XCTAssertEqual(b.outcomes[relay], .answered)
        XCTAssertEqual(a.outcomes[relay], .timedOut, "unknown, never answered by B's EOSE")
        XCTAssertEqual(base.sockets(relay).count, 1)
        // A's subscription is closed on the relay; the socket stays up.
        let socket = try XCTUnwrap(base.sockets(relay).first)
        let subA = try XCTUnwrap(socket.frames.first { $0.hasPrefix("[\"REQ\"") && $0.contains("\"a\"") }.flatMap(subscription))
        try await waitFor("A's CLOSE") { socket.frames.contains { $0.hasPrefix("[\"CLOSE\"") && $0.contains(subA) } }
        XCTAssertFalse(socket.closed, "a timed-out query doesn't close the socket for others")
        shared.closeAll()
        XCTAssertTrue(socket.closed)
    }

    // MARK: I3: acknowledgements

    /// An OK for another id, or on another relay's socket, never counts.
    func testOkForAnotherIdOrOnAnotherSocketIsNotAnAck() async throws {
        executionTimeAllowance = 60
        let e = try event("x")
        let base = ScriptedTransport()
        base.configure = { [relay, other] s in
            s.onSend = { frame, socket in
                guard let id = eventId(of: frame) else { return }
                if socket.url == relay {
                    socket.push("[\"OK\",\"\(String(repeating: "0", count: 64))\",true,\"\"]")
                } else if socket.url == other {
                    // `other` acks for itself; nothing arrives for `relay`.
                    socket.push("[\"OK\",\"\(id)\",true,\"\"]")
                }
            }
        }
        let shared = SharedConnections(base: base)
        let out = await publisher(shared, timeout: .milliseconds(400)).publish(json: try json(e), eventId: e.id, to: [relay, other])
        XCTAssertEqual(out[other], .accepted)
        XCTAssertEqual(out[relay], .timedOut, "an OK for another id isn't an ack, and other's OK isn't relay's")
        shared.closeAll()
    }

    /// An OK that arrives after the send timed out doesn't count, and isn't
    /// taken by the next send on the same socket.
    func testLateOkDoesNotCount() async throws {
        executionTimeAllowance = 60
        let e1 = try event("one"), e2 = try event("two", at: 1_001)
        let base = ScriptedTransport()
        let shared = SharedConnections(base: base)
        let p = publisher(shared, timeout: .milliseconds(300))
        let first = await p.publish(json: try json(e1), eventId: e1.id, to: [relay])
        XCTAssertEqual(first[relay], .timedOut)
        let socket = try XCTUnwrap(base.sockets(relay).first)
        socket.push("[\"OK\",\"\(e1.id)\",true,\"\"]")   // late
        socket.onSend = { frame, s in
            if let id = eventId(of: frame), id == e2.id { s.push("[\"OK\",\"\(id)\",false,\"blocked: test\"]") }
        }
        let second = await p.publish(json: try json(e2), eventId: e2.id, to: [relay])
        XCTAssertEqual(second[relay], .rejected("blocked: test"), "only e2's own OK answers e2")
        XCTAssertEqual(base.sockets(relay).count, 1, "the send reused the socket")
        shared.closeAll()
    }

    // MARK: F1/F5: drops and redials

    /// F1: a drop mid-query fails that query (unknown), the next query
    /// redials once, and a second drop makes the relay unreachable.
    func testDropFailsInFlightQueryRedialsOnceThenUnreachable() async throws {
        executionTimeAllowance = 60
        let base = ScriptedTransport()
        let shared = SharedConnections(base: base)
        let f = fetcher(shared)
        let filter = RelayFilter(authors: [pubkey], kinds: [1])
        let url = relay
        async let inFlight = f.fetch(filter, from: [url])
        try await waitFor("REQ") { base.sockets(relay).first?.frames.isEmpty == false }
        base.sockets(relay)[0].push("[\"EVENT\",\"x\",\(try json(try event("y")))]")
        base.sockets(relay)[0].drop()
        let r1 = await inFlight
        XCTAssertEqual(r1.outcomes[relay], .failed("closed"), "a query in flight on a dropped socket is unknown")
        XCTAssertFalse(r1.allAnswered([relay]))

        // Redial (once): this one answers.
        base.configure = { s in
            s.onSend = { frame, socket in if let sub = subscription(of: frame) { socket.push("[\"EOSE\",\"\(sub)\"]") } }
        }
        let r2 = await f.fetch(filter, from: [relay])
        XCTAssertEqual(r2.outcomes[relay], .answered)
        XCTAssertEqual(base.sockets(relay).count, 2, "redialed once")

        // F5: the relay closes the redialed socket cleanly between queries.
        base.sockets(relay)[1].drop()
        try await Task.sleep(for: .milliseconds(50))
        let r3 = await f.fetch(filter, from: [relay])
        XCTAssertEqual(r3.outcomes[relay], .failed("connect"), "unreachable for the rest of the pass")
        XCTAssertEqual(base.sockets(relay).count, 2, "never more than 1 + 1 redial")
        XCTAssertEqual(shared.statistics[relay], .init(dials: 2, drops: 2, handshakeStatuses: []))
        shared.closeAll()
    }

    /// F1: a send that had no OK before the drop isn't acknowledged.
    func testSendWithoutOkBeforeDropIsNotAcked() async throws {
        executionTimeAllowance = 60
        let e = try event("x")
        let base = ScriptedTransport()
        base.configure = { s in s.onSend = { frame, socket in if eventId(of: frame) != nil { socket.drop() } } }
        let shared = SharedConnections(base: base)
        let out = await publisher(shared).publish(json: try json(e), eventId: e.id, to: [relay])
        XCTAssertEqual(out[relay], .failed("closed"))
        shared.closeAll()
    }

    /// I7: a socket that never opened isn't dialed again in the pass (no
    /// redial: only a socket that had opened gets one).
    func testSocketThatNeverOpenedIsNotRedialed() async throws {
        executionTimeAllowance = 60
        let hung = FakeRelay("hung.example", behavior: .neverConnects)
        let shared = SharedConnections(base: FakeTransport(relays: [hung.url: hung]))
        var f = RelayFetcher(transport: PassTransport(base: shared, unreachable: .init()))
        f.pageTimeout = .milliseconds(300)
        let filter = RelayFilter(authors: [pubkey], kinds: [1])
        let r1 = await f.fetch(filter, from: [hung.url])
        XCTAssertEqual(r1.outcomes[hung.url], .timedOut)
        let r2 = await f.fetch(filter, from: [hung.url])
        XCTAssertEqual(r2.outcomes[hung.url], .failed("connect"))
        XCTAssertEqual(hung.connectCount, 1)
        XCTAssertGreaterThanOrEqual(hung.closeCount, 1, "closed, not left connecting")
        shared.closeAll()
    }

    // MARK: F2: refusals

    /// A CLOSED for one subscription fails only that query; the socket and
    /// the other query carry on.
    func testRefusalFailsOnlyItsOwnQuery() async throws {
        executionTimeAllowance = 60
        let base = ScriptedTransport()
        base.configure = { s in
            s.onSend = { frame, socket in
                guard let sub = subscription(of: frame) else { return }
                if frame.contains("\"a\"") { socket.push("[\"CLOSED\",\"\(sub)\",\"rate-limited: slow down\"]") }
                else { socket.push("[\"EOSE\",\"\(sub)\"]") }
            }
        }
        let shared = SharedConnections(base: base)
        let f = fetcher(shared)
        let fa = RelayFilter(authors: [pubkey], kinds: [1], tagD: ["a"]), fb = RelayFilter(authors: [pubkey], kinds: [1], tagD: ["b"]), url = relay
        async let ra = f.fetch(fa, from: [url])
        async let rb = f.fetch(fb, from: [url])
        let (a, b) = await (ra, rb)
        XCTAssertEqual(a.outcomes[relay], .closed("rate-limited: slow down"), "a refusal is never answered")
        XCTAssertEqual(b.outcomes[relay], .answered)
        XCTAssertEqual(base.sockets(relay).count, 1)
        XCTAssertFalse(base.sockets(relay)[0].closed)
        shared.closeAll()
    }

    /// An `OK false` fails only that send.
    func testRejectedSendDoesNotCloseTheSocket() async throws {
        executionTimeAllowance = 60
        let e1 = try event("one"), e2 = try event("two", at: 1_001)
        let base = ScriptedTransport()
        base.configure = { [e1] s in
            s.onSend = { frame, socket in
                guard let id = eventId(of: frame) else { return }
                socket.push("[\"OK\",\"\(id)\",\(id != e1.id),\"\(id == e1.id ? "blocked: no" : "")\"]")
            }
        }
        let shared = SharedConnections(base: base)
        let p = publisher(shared)
        let out1 = await p.publish(json: try json(e1), eventId: e1.id, to: [relay])
        let out2 = await p.publish(json: try json(e2), eventId: e2.id, to: [relay])
        XCTAssertEqual(out1[relay], .rejected("blocked: no"))
        XCTAssertEqual(out2[relay], .accepted)
        XCTAssertEqual(base.sockets(relay).count, 1)
        shared.closeAll()
    }

    // MARK: closeAll (F3/F4)

    /// `closeAll` ends queries in flight (unknown) and later connects fail.
    func testCloseAllEndsEverythingAndLaterConnectsFail() async throws {
        executionTimeAllowance = 60
        let base = ScriptedTransport()
        let shared = SharedConnections(base: base)
        let f = fetcher(shared)
        let filter = RelayFilter(authors: [pubkey], kinds: [1])
        let urls = [relay, other]
        async let inFlight = f.fetch(filter, from: urls)
        try await waitFor("REQs") { base.sockets(relay).count == 1 && base.sockets(other).count == 1 }
        shared.closeAll()
        let r = await inFlight
        XCTAssertNotEqual(r.outcomes[relay], .answered)
        XCTAssertNotEqual(r.outcomes[other], .answered)
        XCTAssertTrue(base.sockets(relay).allSatisfy(\.closed) && base.sockets(other).allSatisfy(\.closed))
        let after = await f.fetch(filter, from: [relay])
        XCTAssertEqual(after.outcomes[relay], .failed("connect"))
        XCTAssertEqual(base.sockets(relay).count, 1, "nothing dialed after the pass closed")
    }
}

/// Pass-level checks through `SyncService` (T3, F3, F4).
@MainActor
final class SharedConnectionsPassTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private func entry(_ date: String, _ text: String) throws {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let d = DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: text, now: Date(), ownerPubkey: owner))
        try context.save()
    }

    private func service(_ relays: [FakeRelay], transport: RelayTransport? = nil) -> SyncService {
        let base = transport ?? FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: base); fetcher.pageTimeout = .seconds(2)
        var publisher = RelayPublisher(transport: base); publisher.timeout = .seconds(2)
        return SyncService(fetcher: fetcher, publisher: publisher)
    }

    /// T3: a pass over 12 days opens one socket per relay, for every read
    /// (relay list, journal, settings, each day's refetch) and every send,
    /// and closes it when the pass ends. Each day still gets its own
    /// pre-send read (I1) and two acks.
    func testPassOverManyDaysOpensOneSocketPerRelay() async throws {
        executionTimeAllowance = 120
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        for i in 1...12 { try entry(String(format: "2026-10-%02d", i), "day \(i)") }
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.lastPublish?.synced, 12, "every day synced")
        for r in relays {
            XCTAssertEqual(r.connectCount, 1, "\(r.url.host!): one socket for the whole pass")
            XCTAssertEqual(r.closeCount, 1, "\(r.url.host!): closed when the pass ended")
        }
        let writes = RelaySet.defaultWrite
        for r in relays where writes.contains(r.url) {
            XCTAssertEqual(r.publishedFrames.count, 12, "\(r.url.host!): each day sent once")
            // Relay list + journal + settings, then one pre-send read per day
            // (at least; paging adds more), all on that one socket.
            XCTAssertGreaterThanOrEqual(r.requests.count, 3 + 12)
        }
        XCTAssertTrue(SyncLog.recent.contains { $0.hasPrefix("sockets this pass:") })
        // The next pass dials again: nothing is reused across passes (I5).
        await sync.run(owner: owner, secret: secret, context: context)
        for r in relays { XCTAssertEqual(r.connectCount, 2, "\(r.url.host!): a new socket for the next pass") }
    }

    /// F3/F4: cancelling the pass (background, sign-out or an account
    /// switch all cancel it) closes every socket at once, mid-read.
    func testCancellingThePassClosesEverySocketAtOnce() async throws {
        executionTimeAllowance = 60
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!, behavior: .silent) }
        let sync = service(relays)
        let task = Task { await sync.run(owner: owner, secret: secret, context: context) }
        let started = Date()
        while relays.contains(where: { $0.connectCount == 0 }), Date().timeIntervalSince(started) < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "stopped at once, not after the 2 s read timeout")
        for r in relays {
            XCTAssertEqual(r.connectCount, 1)
            XCTAssertEqual(r.closeCount, 1, "\(r.url.host!): closed by the cancel")
        }
    }
}
