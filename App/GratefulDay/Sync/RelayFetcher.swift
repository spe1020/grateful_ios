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
    /// It answered, but we know we couldn't get everything: some second held
    /// more events than it returns per page (Chief P27). Like a timeout,
    /// never counted as answered, because in M5b-2 an answered empty result
    /// is what permits a publish.
    case unresolved(String)
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
    var transport: RelayTransport
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
        var saturated = false
        /// The largest page this relay returned: its page size, as far as we
        /// can tell (relays may return fewer than `limit`).
        var largestPage = 0
        /// The last page held only known ids, and we stepped back a second.
        var steppedBack = false
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
            largestPage = max(largestPage, events.count)
            // After a step-back, any event is older than the second we left.
            // The known-only page before would have included it had it not
            // been capped, so that second may hold events we never saw:
            // exact, whatever the relay's page size (Audit L3, Chief P28).
            // What no time filter can detect: a capped *oldest* second on a
            // relay whose page size is 1. Nothing older follows it, so this
            // test can't fire, and a page of 1 can't show it was full
            // (NIP-01 has no offset or cursor within a second).
            if steppedBack && !events.isEmpty { saturated = true }
            steppedBack = false
            let new = events.filter { seen[$0.id] == nil }
            for e in new { seen[e.id] = e }
            if new.isEmpty {
                // An empty page: nothing older is left.
                guard !events.isEmpty, let current = until else {
                    return (url, Array(seen.values), saturated ? .unresolved("saturated second") : .answered)
                }
                // Only ids we already have, so every one is from the second
                // `until` points at (nothing older has been seen). Usually
                // that's the last second, fully read. But if this page was
                // full, or holds fewer of that second's events than we've
                // seen, the relay may have more there than it returns per
                // page, and a time filter can't reach them: the relay stays
                // unresolved (Chief P27). Either way, step past that second
                // rather than loop; older seconds are still read for the import.
                let inSecond = seen.values.filter { $0.createdAt == current }.count
                if events.count < inSecond || (largestPage > 1 && events.count >= largestPage) {
                    saturated = true
                }
                until = current - 1
                steppedBack = true
            } else {
                // `until` is inclusive (NIP-01): stay on the oldest second so
                // events cut off mid-second are fetched too (Audit L1).
                until = seen.values.map(\.createdAt).min()
            }
            if page > 200 { return (url, Array(seen.values), .failed("paging limit")) }
        }
    }

    private func fetchPage(_ filter: RelayFilter, on connection: RelayConnection,
                           subscription: String) async -> ([NostrEvent], RelayOutcome) {
        if Task.isCancelled { return ([], .failed("cancelled")) }
        let request = filter.reqMessage(subscription: subscription)
        let timeout = pageTimeout
        // Events received before a timeout or close are kept: a relay that
        // never sends EOSE is unresolved, but what it did send still counts
        // as a remote version to merge (Audit test plan B7).
        let collected = EventCollector()
        return await withTaskGroup(of: RelayOutcome?.self) { group in
            group.addTask {
                // The send is inside the page timeout. The first send on a
                // socket waits for the connection, and a relay that never
                // finishes connecting holds it for URLSession's own 60 s.
                // Every fetch waits for all its relays, so one such relay
                // among the bootstrap five kept a pass reading for minutes
                // and the spec A sheet never came up.
                do { try await connection.send(request) } catch { return .failed("send") }
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
