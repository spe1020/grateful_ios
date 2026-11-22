import Foundation
import NostrCore

/// Per-relay outcome of a query. Only `.answered` (EOSE before the timeout)
/// lets an empty result mean "nothing there" (interop spec §0).
enum RelayOutcome: Equatable, Sendable {
    case answered
    case timedOut
    case failed(String)
    /// CLOSED, e.g. auth-required: unknown, never empty.
    case closed(String)
}

struct FetchResult: Sendable {
    /// Every valid event seen, deduped by id.
    var events: [NostrEvent]
    var outcomes: [URL: RelayOutcome]

    func allAnswered(_ relays: [URL]) -> Bool {
        relays.allSatisfy { outcomes[$0] == .answered }
    }
}

/// Paged queries across relays (interop spec §0, §1.5).
struct RelayFetcher: Sendable {
    let transport: RelayTransport
    var pageTimeout: Duration = .seconds(8)
    var pageLimit = 500

    /// Query `relays` with `filter`, paging each relay by `until` until a page
    /// brings nothing new. A relay that times out, errors or closes on any
    /// page is recorded as such; its events so far are still kept.
    func fetch(_ filter: RelayFilter, from relays: [URL]) async -> FetchResult {
        await withTaskGroup(of: (URL, [NostrEvent], RelayOutcome).self) { group in
            for url in relays {
                group.addTask { await fetchAll(filter, from: url) }
            }
            var byId: [String: NostrEvent] = [:]
            var outcomes: [URL: RelayOutcome] = [:]
            for await (url, events, outcome) in group {
                outcomes[url] = outcome
                for e in events where e.isValid { byId[e.id] = e }
            }
            return FetchResult(events: Array(byId.values), outcomes: outcomes)
        }
    }

    private func fetchAll(_ filter: RelayFilter, from url: URL) async -> (URL, [NostrEvent], RelayOutcome) {
        let connection: RelayConnection
        do { connection = try await transport.connect(url) } catch { return (url, [], .failed("connect")) }
        // One connection for every page; closed once, here. Cancelling the
        // fetch (the app went to the background) closes it at once, which
        // also ends a pending receive, so no socket outlives the foreground.
        defer { connection.close() }
        return await withTaskCancellationHandler {
            await pages(filter, from: url, on: connection)
        } onCancel: {
            connection.close()
        }
    }

    private func pages(_ filter: RelayFilter, from url: URL, on connection: RelayConnection) async -> (URL, [NostrEvent], RelayOutcome) {
        var seen: [String: NostrEvent] = [:]
        var until: Int? = nil
        var page = 0
        while true {
            if Task.isCancelled { return (url, Array(seen.values), .failed("cancelled")) }
            page += 1
            var f = filter
            f.until = until
            f.limit = pageLimit
            let (events, outcome) = await fetchPage(f, on: connection, subscription: "gd\(page)")
            guard outcome == .answered else {
                for e in events { seen[e.id] = e }
                return (url, Array(seen.values), outcome)
            }
            let new = events.filter { seen[$0.id] == nil }
            for e in new { seen[e.id] = e }
            // Stop when a page brings nothing new; otherwise continue below
            // the oldest event seen so far.
            guard !new.isEmpty, let oldest = seen.values.map(\.createdAt).min() else {
                return (url, Array(seen.values), .answered)
            }
            let next = oldest - 1
            if let until, next >= until { return (url, Array(seen.values), .answered) }
            until = next
            if page > 200 { return (url, Array(seen.values), .failed("paging limit")) }
        }
    }

    private func fetchPage(_ filter: RelayFilter, on connection: RelayConnection,
                           subscription: String) async -> ([NostrEvent], RelayOutcome) {
        if Task.isCancelled { return ([], .failed("cancelled")) }
        do {
            try await connection.send(filter.reqMessage(subscription: subscription))
        } catch {
            return ([], .failed("send"))
        }
        let timeout = pageTimeout
        // Events received before a timeout or close are kept: a relay that
        // never sends EOSE is unresolved, but what it did send still counts
        // as a remote version to merge (Audit test plan B7).
        let collected = EventCollector()
        return await withTaskGroup(of: RelayOutcome?.self) { group in
            group.addTask {
                while true {
                    guard let text = try? await connection.receive() else { return .failed("closed") }
                    switch RelayMessage.parse(text) {
                    case .event(let sub, let e) where sub == subscription: collected.append(e)
                    case .eose(let sub) where sub == subscription:
                        try? await connection.send("[\"CLOSE\",\"\(subscription)\"]")
                        return .answered
                    case .closed(let sub, let reason) where sub == subscription: return .closed(reason)
                    default: continue
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            if Task.isCancelled { connection.close(); return (collected.events, .failed("cancelled")) }
            // The socket stays open across pages; each page ends its own
            // subscription with CLOSE (Audit, #14 early read). Only an
            // unresolved page closes it, which also ends the pending
            // receive so the group can finish; `fetchAll` stops there.
            if first != .answered { connection.close() }
            return (collected.events, first ?? .timedOut)
        }
    }
}

/// Thread-safe accumulator for one page's events.
final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [NostrEvent] = []
    func append(_ e: NostrEvent) { lock.withLock { items.append(e) } }
    var events: [NostrEvent] { lock.withLock { items } }
}
