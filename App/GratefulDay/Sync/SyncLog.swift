import Foundation
import os

/// Sync diagnostics: where a relay pass is and how each relay answered.
///
/// Never logs keys, reflection text, event content, dates or the account's
/// public key. A line holds only a fixed stage name, relay hosts, outcome
/// names, counts and the first 8 characters of an event id (ids are public
/// on relays once sent).
enum SyncLog {
    static let logger = Logger(subsystem: "app.gratefulday.ios", category: "sync")

    /// The most recent lines, kept in memory so tests can check what was
    /// logged (and that it holds no content).
    @MainActor private(set) static var recent: [String] = []

    static func note(_ stage: StaticString, _ detail: String = "") {
        let line = detail.isEmpty ? "\(stage)" : "\(stage): \(detail)"
        logger.notice("\(line, privacy: .public)")
        Task { @MainActor in
            recent.append(line)
            if recent.count > 200 { recent.removeFirst(recent.count - 200) }
        }
    }

    @MainActor static func clearRecent() { recent.removeAll() }

    static func hosts(_ urls: [URL]?) -> String {
        guard let urls else { return "unknown" }
        return urls.isEmpty ? "none" : urls.map { $0.host ?? "?" }.joined(separator: " ")
    }

    static func id(_ eventId: String) -> String { String(eventId.prefix(8)) }

    /// Relay-supplied text (a CLOSED or OK reason), cut short.
    private static func reason(_ s: String) -> String { String(s.prefix(48)) }

    static func describe(_ outcomes: [URL: RelayOutcome]) -> String {
        outcomes.sorted { $0.key.absoluteString < $1.key.absoluteString }.map { url, outcome in
            let name: String
            switch outcome {
            case .answered: name = "answered"
            case .timedOut: name = "timedOut"
            case .failed(let why): name = "failed(\(reason(why)))"
            case .closed(let why): name = "closed(\(reason(why)))"
            case .unresolved(let why): name = "unresolved(\(reason(why)))"
            }
            return "\(url.host ?? "?")=\(name)"
        }.joined(separator: " ")
    }

    static func describe(_ outcomes: [URL: PublishOutcome]) -> String {
        outcomes.sorted { $0.key.absoluteString < $1.key.absoluteString }.map { url, outcome in
            let name: String
            switch outcome {
            case .accepted: name = "OK"
            case .rejected(let why): name = "rejected(\(reason(why)))"
            case .failed(let why): name = "failed(\(reason(why)))"
            case .timedOut: name = "timedOut"
            }
            return "\(url.host ?? "?")=\(name)"
        }.joined(separator: " ")
    }
}
