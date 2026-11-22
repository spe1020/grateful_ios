import XCTest
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// A scripted relay: answers REQs from a fixed event list, or misbehaves.
final class FakeRelay: RelayConnection, @unchecked Sendable {
    enum Behavior { case normal, silent, closeWithAuth, refuseConnect }
    let url: URL
    let behavior: Behavior
    var events: [NostrEvent]
    var pageCap: Int
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

    func send(_ text: String) async throws {
        guard let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
              array.first as? String == "REQ", let sub = array[1] as? String, let f = array[2] as? [String: Any] else { return }
        lock.withLock { requests.append(f) }
        switch behavior {
        case .silent, .refuseConnect: return
        case .closeWithAuth: push("[\"CLOSED\",\"\(sub)\",\"auth-required: sign in\"]"); return
        case .normal: break
        }
        let kinds = f["kinds"] as? [Int] ?? []
        let until = f["until"] as? Int ?? Int.max
        let limit = min(f["limit"] as? Int ?? 1000, pageCap)
        let matching = events.filter { kinds.contains($0.kind) && $0.createdAt <= until }
            .sorted { $0.createdAt > $1.createdAt }.prefix(limit)
        for e in matching {
            let data = try JSONEncoder().encode(e)
            push("[\"EVENT\",\"\(sub)\",\(String(decoding: data, as: UTF8.self))]")
        }
        push("[\"EOSE\",\"\(sub)\"]")
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
            if !outbox.isEmpty { let s = outbox.removeFirst(); lock.unlock(); c.resume(returning: s); return }
            waiter = c
            lock.unlock()
        }
    }

    func close() {
        lock.lock()
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

    func testTimeoutIsUnknownNotEmpty() async {
        let quiet = FakeRelay("quiet", behavior: .silent)
        let result = await fetcher([quiet], timeout: .milliseconds(200)).fetch(filter(), from: [quiet.url])
        XCTAssertEqual(result.outcomes[quiet.url], .timedOut)
        XCTAssertFalse(result.allAnswered([quiet.url]), "no answer is unknown, never empty")
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
