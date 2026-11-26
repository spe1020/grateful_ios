import Foundation

/// Relays for the UI tests (Chief P48). UI tests must never reach real
/// relays: with a connected account a pass would read them from the test
/// machine, and whether the spec A sheet came up mid-test depended on their
/// latency (#20, run 45173790811).
///
/// Read only from the process's launch arguments, never from defaults or
/// any setting, and compiled only into Debug builds: a shipped (Release)
/// build always uses `WebSocketTransport`.
enum UITestRelays {
    /// Every relay refuses the connection: a pass ends unresolved, reads
    /// nothing, publishes nothing and brings up no sheet.
    static let noRelays = "-uiTestNoRelays"
    /// Every relay answers every query with nothing (EOSE) and rejects every
    /// event, without any network: a connected account with the disclosure
    /// not yet accepted reaches the spec A sheet, and nothing is ever stored.
    static let emptyRelays = "-uiTestEmptyRelays"

    static func transport(arguments: [String]) -> RelayTransport {
        #if DEBUG
        if arguments.contains(emptyRelays) { return EmptyTransport() }
        if arguments.contains(noRelays) { return RefusingTransport() }
        #endif
        return WebSocketTransport()
    }

    #if DEBUG
    struct RefusingTransport: RelayTransport {
        func connect(_ url: URL) async throws -> RelayConnection { throw URLError(.cannotConnectToHost) }
    }

    struct EmptyTransport: RelayTransport {
        func connect(_ url: URL) async throws -> RelayConnection { EmptyRelay(url: url) }
    }

    /// Answers REQ with EOSE and EVENT with `OK false`; nothing leaves the app.
    final class EmptyRelay: RelayConnection, @unchecked Sendable {
        let url: URL
        private let lock = NSLock()
        private var queue: [String] = []
        private var waiter: CheckedContinuation<String, Error>?
        private var closed = false

        init(url: URL) { self.url = url }

        func send(_ text: String) async throws {
            guard let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
                  let type = array.first as? String, array.count >= 2 else { return }
            if lock.withLock({ closed }) { throw URLError(.cancelled) }
            switch type {
            case "REQ":
                if let sub = array[1] as? String { push("[\"EOSE\",\"\(sub)\"]") }
            case "EVENT":
                let id = (array[1] as? [String: Any])?["id"] as? String ?? ""
                push("[\"OK\",\"\(id)\",false,\"blocked: ui test relay\"]")
            default:
                break
            }
        }

        private func push(_ message: String) {
            lock.lock()
            if let w = waiter { waiter = nil; lock.unlock(); w.resume(returning: message); return }
            queue.append(message)
            lock.unlock()
        }

        func receive() async throws -> String {
            try await withCheckedThrowingContinuation { c in
                lock.lock()
                if closed { lock.unlock(); c.resume(throwing: URLError(.cancelled)); return }
                if !queue.isEmpty { let m = queue.removeFirst(); lock.unlock(); c.resume(returning: m); return }
                waiter = c
                lock.unlock()
            }
        }

        func close() {
            lock.lock()
            closed = true
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume(throwing: URLError(.cancelled))
        }
    }
    #endif
}
