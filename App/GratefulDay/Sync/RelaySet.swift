import Foundation
import NostrCore

/// Which relays to read from and write to (interop §5, r5.1 §0.1; Seth
/// 3f1c5fd4; Audit A2).
struct RelaySet: Equatable, Sendable {
    var read: [URL]
    /// nil = unknown (the relay-list lookup didn't resolve): never publish.
    var write: [URL]?

    /// Web's five defaults (gratefulday `src/App.tsx:40-44`).
    static let defaultRead: [URL] = [
        "wss://relay.damus.io", "wss://relay.nostr.band", "wss://nos.lol", "wss://relay.primal.net", "wss://nostr.wine",
    ].map { URL(string: $0)! }
    /// Provisional until damus is re-measured (Seth).
    static let defaultWrite: [URL] = ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net"].map { URL(string: $0)! }

    enum ListLookup: Equatable {
        /// The user's kind 10002 was found.
        case found(NostrEvent)
        /// At least 2 relays answered EOSE with nothing: there is no list.
        case none
        /// Not enough answers to know either way.
        case unresolved
    }

    /// Interpret a kind 10002 lookup across the bootstrap relays.
    static func lookup(_ result: FetchResult, owner: String, bootstrap: [URL]) -> ListLookup {
        let lists = result.events.filter { $0.kind == 10002 && $0.pubkey == owner }
        if let newest = lists.max(by: { ($0.createdAt, $1.id) < ($1.createdAt, $0.id) }) { return .found(newest) }
        let answered = bootstrap.filter { result.outcomes[$0] == .answered }.count
        return answered >= min(2, bootstrap.count) ? .none : .unresolved
    }

    static func from(_ lookup: ListLookup) -> RelaySet {
        switch lookup {
        case .found(let event):
            var read: [URL] = [], write: [URL] = []
            for tag in event.tags where tag.count >= 2 && tag[0] == "r" {
                guard let url = normalize(tag[1]) else { continue }
                let marker = tag.count > 2 ? tag[2] : ""
                if marker.isEmpty || marker == "read" { read.append(url) }
                if marker.isEmpty || marker == "write" { write.append(url) }
            }
            // Own events live on write relays (interop §1.5): read both.
            let reads = Array(NSOrderedSet(array: read + write)) as? [URL] ?? read + write
            // The user's explicit list is used as is: defaults are never added.
            return RelaySet(read: reads, write: Array(NSOrderedSet(array: write)) as? [URL] ?? write)
        case .none:
            return RelaySet(read: defaultRead, write: defaultWrite)
        case .unresolved:
            // Reading publishes nothing, so defaults are fine for reads; the
            // write set stays unknown (Audit A2).
            return RelaySet(read: defaultRead, write: nil)
        }
    }

    /// Lowercased scheme and host, no trailing slash; only ws/wss.
    static func normalize(_ raw: String) -> URL? {
        guard var c = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
              let scheme = c.scheme?.lowercased(), scheme == "wss" || scheme == "ws", let host = c.host, !host.isEmpty
        else { return nil }
        c.scheme = scheme
        c.host = host.lowercased()
        if c.path == "/" { c.path = "" }
        return c.url
    }
}
