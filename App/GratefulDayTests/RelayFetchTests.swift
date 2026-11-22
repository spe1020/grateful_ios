import XCTest
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// A scripted relay: answers REQs from a fixed event list, or misbehaves.
final class FakeRelay: RelayConnection, @unchecked Sendable {
    enum Behavior { case normal, silent, closeWithAuth, refuseConnect, eventsNoEose }
    let url: URL
    let behavior: Behavior
    var events: [NostrEvent]
    var pageCap: Int
    /// Per-request page sizes (first REQ uses [0]); past the end, `pageCap`.
    var pageCaps: [Int] = []
    private var outbox: [String] = []
    private var waiter: CheckedContinuation<String, Error>?
    private let lock = NSLock()
    private(set) var requests: [[String: Any]] = []

    init(_ host: String, events: [NostrEvent] = [], behavior: Behavior = .normal, pageCap: Int = 1000) {
        url = URL(string: "wss://\(host)")!
        self.events = events
        self.behavior = behavior
        self.pageCap = pageCap
    }

    /// Like `URLSessionWebSocketTask.cancel`, closing is terminal: any send
    /// or receive afterwards throws (Audit, #14 early read).
    private var isClosed = false
    private(set) var closeCount = 0

    func send(_ text: String) async throws {
        if lock.withLock({ isClosed }) { throw URLError(.cancelled) }
        guard let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
              array.first as? String == "REQ", let sub = array[1] as? String, let f = array[2] as? [String: Any] else { return }
        let index = lock.withLock { requests.append(f); return requests.count - 1 }
        switch behavior {
        case .silent, .refuseConnect: return
        case .closeWithAuth: push("[\"CLOSED\",\"\(sub)\",\"auth-required: sign in\"]"); return
        case .normal, .eventsNoEose: break
        }
        let kinds = f["kinds"] as? [Int] ?? []
        let until = f["until"] as? Int ?? Int.max
        let cap = index < pageCaps.count ? pageCaps[index] : pageCap
        let limit = min(f["limit"] as? Int ?? 1000, cap)
        // Newest first; ties by id so a capped second is deterministic.
        let matching = events.filter { kinds.contains($0.kind) && $0.createdAt <= until }
            .sorted { $0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id < $1.id }.prefix(limit)
        for e in matching {
            let data = try JSONEncoder().encode(e)
            push("[\"EVENT\",\"\(sub)\",\(String(decoding: data, as: UTF8.self))]")
        }
        if behavior != .eventsNoEose { push("[\"EOSE\",\"\(sub)\"]") }
    }

    private func push(_ s: String) {
        lock.lock()
        if let w = waiter { waiter = nil; lock.unlock(); w.resume(returning: s); return }
        outbox.append(s)
        lock.unlock()
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { c in
            lock.lock()
            if isClosed { lock.unlock(); c.resume(throwing: URLError(.cancelled)); return }
            if !outbox.isEmpty { let s = outbox.removeFirst(); lock.unlock(); c.resume(returning: s); return }
            waiter = c
            lock.unlock()
        }
    }

    /// A new `connect` is a new socket (fetches here are sequential).
    func reopen() { lock.withLock { isClosed = false } }

    func close() {
        lock.lock()
        isClosed = true
        closeCount += 1
        let w = waiter
        waiter = nil
        lock.unlock()
        w?.resume(throwing: URLError(.cancelled))
    }
}

struct FakeTransport: RelayTransport {
    let relays: [URL: FakeRelay]
    func connect(_ url: URL) async throws -> RelayConnection {
        guard let r = relays[url], r.behavior != .refuseConnect else { throw URLError(.cannotConnectToHost) }
        r.reopen()
        return r
    }
}

final class RelayFetchTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var pubkey: String { KeyVault.pubkeyHex(for: secret)! }
    private let zone = TimeZone(identifier: "America/Chicago")!

    private func entry(_ date: String, _ text: String, at: Int, private isPrivate: Bool = true, key: Data? = nil) throws -> NostrEvent {
        let k = key ?? secret
        let d = day(date)
        let tmpl = isPrivate ? try DailyEntry.privateTemplate(day: d, notes: [text], privateKey: k)
                             : try DailyEntry.template(day: d, notes: [text])
        return try tmpl.signed(privateKey: k, createdAt: at)
    }

    /// Noon on a Gregorian date in `zone`, as a day.
    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func fetcher(_ relays: [FakeRelay], timeout: Duration = .seconds(2)) -> RelayFetcher {
        var f = RelayFetcher(transport: FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) })))
        f.pageTimeout = timeout
        return f
    }

    private func filter() -> RelayFilter { RelayFilter(authors: [pubkey], kinds: [36669, 5]) }

    func testFetchPagesUntilNoNewEvents() async throws {
        let events = try (1...7).map { try entry(String(format: "2026-11-%02d", $0), "day \($0)", at: 1_000 + $0) }
        let relay = FakeRelay("a", events: events, pageCap: 3)
        let result = await fetcher([relay]).fetch(filter(), from: [relay.url])
        XCTAssertEqual(Set(result.events.map(\.id)), Set(events.map(\.id)), "every page collected")
        XCTAssertEqual(result.outcomes[relay.url], .answered)
        XCTAssertGreaterThanOrEqual(relay.requests.count, 3, "paged by until")
    }

    /// Audit, #14 early read: closing is terminal on a real socket, so
    /// paging must reuse one open connection and still end `.answered`.
    func testPagingKeepsConnectionOpenAndEndsAnswered() async throws {
        let events = try (1...5).map { try entry(String(format: "2026-10-%02d", $0), "day \($0)", at: 2_000 + $0) }
        let relay = FakeRelay("paged", events: events, pageCap: 2)
        let result = await fetcher([relay]).fetch(filter(), from: [relay.url])
        XCTAssertEqual(result.outcomes[relay.url], .answered, "more than one page, still answered")
        XCTAssertEqual(Set(result.events.map(\.id)), Set(events.map(\.id)))
        XCTAssertGreaterThanOrEqual(relay.requests.count, 3, "pages 1–3 plus the empty confirming page")
        XCTAssertEqual(relay.closeCount, 1, "closed once, after the last page")
    }

    /// Chief P26: a cancelled fetch (app backgrounded) closes its socket at
    /// once rather than waiting out the page timeout, and isn't "answered".
    func testCancelledFetchClosesConnectionPromptly() async {
        let quiet = FakeRelay("quiet", behavior: .silent)
        let f = fetcher([quiet], timeout: .seconds(30))
        let started = Date()
        let query = filter()
        let url = quiet.url
        let task = Task { await f.fetch(query, from: [url]) }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "didn't wait for the 30 s timeout")
        XCTAssertNotEqual(result.outcomes[quiet.url], .answered)
        XCTAssertGreaterThanOrEqual(quiet.closeCount, 1, "socket closed")
    }

    /// Audit L1 / Chief P27: `until` is inclusive, so events cut off in the
    /// middle of a second are still fetched; a page of only known ids from
    /// one second steps past it instead of looping, and paging still reaches
    /// older seconds and ends answered.
    func testPageBoundaryInsideOneSecondIsNotSkippedAndStops() async throws {
        let sameSecond = try (1...3).map { try entry(String(format: "2026-09-%02d", $0), "s\($0)", at: 5_000) }
        let older = try entry("2026-08-01", "older", at: 4_000)
        let relay = FakeRelay("edge", events: sameSecond + [older], pageCap: 2)
        let result = await fetcher([relay]).fetch(filter(), from: [relay.url])
        XCTAssertEqual(result.outcomes[relay.url], .unresolved("saturated second"), "a second it couldn't finish: never answered")
        XCTAssertFalse(result.allAnswered([relay.url]))
        XCTAssertTrue(result.events.contains { $0.id == older.id }, "older second still reached")

        let cut = try (1...3).map { try entry(String(format: "2026-06-%02d", $0), "c\($0)", at: 7_000 + ($0 == 1 ? 1 : 0)) }
        let mid = FakeRelay("mid", events: cut, pageCap: 2)
        let r1 = await fetcher([mid]).fetch(filter(), from: [mid.url])
        XCTAssertEqual(Set(r1.events.map(\.id)), Set(cut.map(\.id)), "a page cut mid-second loses nothing")
        // Its last full page was all one second, so it might have held more
        // there: conservatively unresolved, though nothing was missed here.
        XCTAssertNotEqual(r1.outcomes[mid.url], .answered)

        // The ordinary end of paging (the last second read in full) is answered.
        let spread = try (1...3).map { try entry(String(format: "2026-05-%02d", $0), "p\($0)", at: 8_000 + $0) }
        let done = FakeRelay("done", events: spread, pageCap: 2)
        let r3 = await fetcher([done]).fetch(filter(), from: [done.url])
        XCTAssertEqual(r3.outcomes[done.url], .answered)
        XCTAssertEqual(Set(r3.events.map(\.id)), Set(spread.map(\.id)))

        let full = try (1...4).map { try entry(String(format: "2026-07-%02d", $0), "f\($0)", at: 6_000) }
        let stuck = FakeRelay("stuck", events: full, pageCap: 2)
        let r2 = await fetcher([stuck]).fetch(filter(), from: [stuck.url])
        XCTAssertEqual(r2.outcomes[stuck.url], .unresolved("saturated second"), "stops, never loops, never answered")
        XCTAssertLessThan(stuck.requests.count, 10)
    }

    /// Audit L3 / Chief P28: a relay with a page size of 1 caps every page,
    /// so a second with two events loses one. The page after the step-back
    /// holds an older event, which proves the page before it was capped.
    func testPageSizeOneSecondWithMoreThanOneEventIsUnresolved() async throws {
        let sameSecond = try (1...2).map { try entry(String(format: "2026-04-%02d", $0), "one\($0)", at: 5_000) }
        let older = try entry("2026-03-01", "older", at: 4_000)
        let relay = FakeRelay("one", events: sameSecond + [older], pageCap: 1)
        let result = await fetcher([relay]).fetch(filter(), from: [relay.url])
        XCTAssertEqual(result.outcomes[relay.url], .unresolved("saturated second"), "missed one of the second's two: never answered")
        XCTAssertFalse(result.allAnswered([relay.url]))
        XCTAssertTrue(result.events.contains { $0.id == older.id }, "older second still reached")
    }

    /// Audit L3 / Chief P28: a relay whose page shrinks (3, then 1) returns a
    /// capped page smaller than its largest, which the page-size check misses.
    func testShrinkingPageCappedSecondIsUnresolved() async throws {
        let newer = try (1...2).map { try entry(String(format: "2026-02-%02d", $0), "n\($0)", at: 8_000 - $0 * 1_000) }
        let sameSecond = try (1...2).map { try entry(String(format: "2026-01-%02d", $0), "s\($0)", at: 5_000) }
        let older = try entry("2025-12-01", "older", at: 4_000)
        let relay = FakeRelay("shrink", events: newer + sameSecond + [older], pageCap: 1)
        relay.pageCaps = [3]
        let result = await fetcher([relay]).fetch(filter(), from: [relay.url])
        XCTAssertLessThan(result.events.count, 5, "the scenario really drops an event")
        XCTAssertEqual(result.outcomes[relay.url], .unresolved("saturated second"))
        XCTAssertFalse(result.allAnswered([relay.url]))
    }

    func testTimeoutIsUnknownNotEmpty() async {
        let quiet = FakeRelay("quiet", behavior: .silent)
        let result = await fetcher([quiet], timeout: .milliseconds(200)).fetch(filter(), from: [quiet.url])
        XCTAssertEqual(result.outcomes[quiet.url], .timedOut)
        XCTAssertFalse(result.allAnswered([quiet.url]), "no answer is unknown, never empty")
    }

    func testEventsWithoutEoseAreKeptButRelayIsUnresolved() async throws {
        let e = try entry("2026-11-13", "partial", at: 3_000)
        let r = FakeRelay("slow", events: [e], behavior: .eventsNoEose)
        let result = await fetcher([r], timeout: .milliseconds(300)).fetch(filter(), from: [r.url])
        XCTAssertEqual(result.outcomes[r.url], .timedOut)
        XCTAssertEqual(result.events.map(\.id), [e.id], "what it sent is still merged")
    }

    func testAuthClosedAndRefusedConnectAreUnknown() async {
        let auth = FakeRelay("auth", behavior: .closeWithAuth)
        let down = FakeRelay("down", behavior: .refuseConnect)
        let result = await fetcher([auth, down]).fetch(filter(), from: [auth.url, down.url])
        XCTAssertEqual(result.outcomes[auth.url], .closed("auth-required: sign in"))
        XCTAssertEqual(result.outcomes[down.url], .failed("connect"))
        XCTAssertFalse(result.allAnswered([auth.url, down.url]))
    }

    func testDedupesAcrossRelaysAndDropsInvalid() async throws {
        let e = try entry("2026-11-10", "same", at: 2_000)
        var forged = e
        forged.content = "tampered"
        let a = FakeRelay("a", events: [e]), b = FakeRelay("b", events: [e, forged])
        let result = await fetcher([a, b]).fetch(filter(), from: [a.url, b.url])
        XCTAssertEqual(result.events.map(\.id), [e.id], "deduped by id, bad signature dropped")
    }

    func testTieBreakLowestIdAndKind5HidesOlderVersionsOnly() throws {
        let v1 = try entry("2026-11-10", "first", at: 100)
        let v2a = try entry("2026-11-10", "tie a", at: 200)
        let v2b = try entry("2026-11-10", "tie b", at: 200)
        let lowest = [v2a, v2b].min { $0.id < $1.id }!
        var days = RemoteJournal.days(from: [v1, v2a, v2b], owner: pubkey, privateKey: secret)
        guard case .entry(_, _, let id, _, _) = days["2026-11-10"] else { return XCTFail() }
        XCTAssertEqual(id, lowest.id)

        let del = try EntryDeletion.template(pubkey: pubkey, dateString: "2026-11-10", eventId: lowest.id).signed(privateKey: secret, createdAt: 250)
        days = RemoteJournal.days(from: [v1, v2a, v2b, del], owner: pubkey, privateKey: secret)
        XCTAssertEqual(days["2026-11-10"], .deleted(at: 250))

        let v3 = try entry("2026-11-10", "rewritten", at: 300)
        days = RemoteJournal.days(from: [v1, v2a, v2b, del, v3], owner: pubkey, privateKey: secret)
        guard case .entry(let text, _, _, _, _) = days["2026-11-10"] else { return XCTFail("a newer re-creation stays visible") }
        XCTAssertEqual(text, "rewritten")
    }

    func testUndecryptableDateIsBlockedNeverEmpty() throws {
        let other = try NostrKeys.generatePrivateKey()
        // Signed by the owner but encrypted to someone else: decrypt fails.
        let d = day("2026-11-11")
        let payload = try NIP44.encryptToSelf("hidden", privateKey: other)
        let event = try DailyEntry.template(day: d, notes: ["x"], encryptedContent: payload).signed(privateKey: secret, createdAt: 10)
        let days = RemoteJournal.days(from: [event], owner: pubkey, privateKey: secret)
        XCTAssertEqual(days["2026-11-11"], .blocked(eventId: event.id, createdAt: 10))
    }

    func testOtherAuthorsEventsIgnored() throws {
        let other = try NostrKeys.generatePrivateKey()
        let theirs = try entry("2026-11-12", "not mine", at: 10, key: other)
        XCTAssertTrue(RemoteJournal.days(from: [theirs], owner: pubkey, privateKey: secret).isEmpty)
    }

    // Settings (interop §2.4, addendum)

    private func settingsEvent(_ json: String, at: Int = 10) throws -> NostrEvent {
        let payload = try NIP44.encryptToSelf(json, privateKey: secret)
        return try UnsignedEvent(kind: 30078, tags: [["d", "gratefulday:settings"], ["encrypted", "nip44"], ["alt", "Encrypted gratefulday settings"]],
                                 content: payload).signed(privateKey: secret, createdAt: at)
    }

    func testSettingsNonObjectIsUnknown() throws {
        for json in ["not json", "[1,2]", "null", "42"] {
            XCTAssertEqual(RemoteSettings.read([try settingsEvent(json)], owner: pubkey, privateKey: secret), .unknown, json)
        }
    }

    func testSettingsUndecryptableIsUnknownAndNoneIsNone() throws {
        let other = try NostrKeys.generatePrivateKey()
        let bad = try UnsignedEvent(kind: 30078, tags: [["d", "gratefulday:settings"]],
                                    content: try NIP44.encryptToSelf("{}", privateKey: other)).signed(privateKey: secret, createdAt: 1)
        XCTAssertEqual(RemoteSettings.read([bad], owner: pubkey, privateKey: secret), .unknown)
        XCTAssertEqual(RemoteSettings.read([], owner: pubkey, privateKey: secret), RemoteSettings.none)
    }

    func testSettingsVersion2IsReadOnly() throws {
        guard case .known(_, _, let readOnly) = RemoteSettings.read([try settingsEvent(#"{"version":2,"celebratedMilestones":[7]}"#)],
                                                                  owner: pubkey, privateKey: secret) else { return XCTFail() }
        XCTAssertTrue(readOnly)
    }

    func testUnknownSettingsKeysPreserved() throws {
        let json = #"{"version":1,"privacyDefault":true,"celebratedMilestones":[7,30],"lastSeenNotifications":1795280000,"futureField":{"a":[1,"b"]}}"#
        guard case .known(let s, let raw, let readOnly) = RemoteSettings.read([try settingsEvent(json)], owner: pubkey, privateKey: secret)
        else { return XCTFail() }
        XCTAssertFalse(readOnly)
        XCTAssertEqual(s.celebratedMilestones, [7, 30])
        XCTAssertEqual(raw["futureField"], .object(["a": .array([.number(1), .string("b")])]))
    }
}
