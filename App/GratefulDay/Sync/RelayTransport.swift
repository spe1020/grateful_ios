import Foundation
import NostrCore

/// One NIP-01 relay connection, reduced to what sync needs. Injected so tests
/// can script relays (EOSE, timeouts, malformed frames, duplicates).
protocol RelayConnection: AnyObject, Sendable {
    var url: URL { get }
    /// Send a raw client message (JSON array text).
    func send(_ text: String) async throws
    /// The next raw relay message; throws when the connection closes.
    func receive() async throws -> String
    func close()
}

protocol RelayTransport: Sendable {
    func connect(_ url: URL) async throws -> RelayConnection
}

/// The system transport: `URLSessionWebSocketTask`. No third-party code.
struct WebSocketTransport: RelayTransport {
    func connect(_ url: URL) async throws -> RelayConnection {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        return WebSocketConnection(url: url, task: task)
    }
}

final class WebSocketConnection: RelayConnection, @unchecked Sendable {
    let url: URL
    private let task: URLSessionWebSocketTask

    init(url: URL, task: URLSessionWebSocketTask) {
        self.url = url
        self.task = task
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let s): return s
        case .data(let d): return String(decoding: d, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

extension WebSocketConnection: HandshakeReporting {
    /// The HTTP status of the upgrade response, e.g. 429 when a relay
    /// refuses the handshake; nil if none arrived. A number only (I9).
    var handshakeStatus: Int? { (task.response as? HTTPURLResponse)?.statusCode }
}

/// A relay message we care about, parsed leniently: anything else is ignored.
enum RelayMessage: Equatable {
    case event(subscription: String, event: NostrEvent)
    case eose(subscription: String)
    case closed(subscription: String, reason: String)
    case notice(String)
    case ok(eventId: String, accepted: Bool, message: String)

    static func parse(_ text: String) -> RelayMessage? {
        guard let data = text.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String else { return nil }
        switch type {
        case "EVENT":
            guard array.count >= 3, let sub = array[1] as? String,
                  let obj = array[2] as? [String: Any],
                  let eventData = try? JSONSerialization.data(withJSONObject: obj),
                  let event = try? JSONDecoder().decode(NostrEvent.self, from: eventData) else { return nil }
            return .event(subscription: sub, event: event)
        case "EOSE":
            guard array.count >= 2, let sub = array[1] as? String else { return nil }
            return .eose(subscription: sub)
        case "CLOSED":
            guard array.count >= 2, let sub = array[1] as? String else { return nil }
            return .closed(subscription: sub, reason: array.count > 2 ? (array[2] as? String ?? "") : "")
        case "NOTICE":
            return .notice(array.count > 1 ? (array[1] as? String ?? "") : "")
        case "OK":
            guard array.count >= 3, let id = array[1] as? String, let ok = array[2] as? Bool else { return nil }
            return .ok(eventId: id, accepted: ok, message: array.count > 3 ? (array[3] as? String ?? "") : "")
        default:
            return nil
        }
    }
}

/// A NIP-01 filter (only the fields sync uses).
struct RelayFilter: Equatable, Sendable {
    var authors: [String]
    var kinds: [Int]
    var tagD: [String]? = nil
    var tagK: [String]? = nil
    var tagA: [String]? = nil
    var until: Int? = nil
    var limit: Int? = nil

    var json: [String: Any] {
        var f: [String: Any] = ["authors": authors, "kinds": kinds]
        if let tagD { f["#d"] = tagD }
        if let tagK { f["#k"] = tagK }
        if let tagA { f["#a"] = tagA }
        if let until { f["until"] = until }
        if let limit { f["limit"] = limit }
        return f
    }

    func reqMessage(subscription: String) -> String {
        let array: [Any] = ["REQ", subscription, json]
        let data = (try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
