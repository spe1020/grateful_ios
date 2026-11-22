import Foundation
import NostrCore

/// Per-relay result of sending one signed event (M5b plan r2 (b)).
enum PublishOutcome: Equatable, Sendable {
    /// `["OK", <that id>, true, …]`, including a `duplicate:` message: the
    /// relay holds that exact event.
    case accepted
    /// `["OK", <that id>, false, reason]`: not stored. Retried with backoff.
    case rejected(String)
    case failed(String)
    case timedOut
}

/// Sends a signed event to relays and reports which acknowledged it. It
/// never signs: callers pass the stored JSON, so a retry is the same event
/// byte for byte (same id, created_at and sig).
struct RelayPublisher: Sendable {
    let transport: RelayTransport
    var timeout: Duration = .seconds(8)

    func publish(json: String, eventId: String, to relays: [URL]) async -> [URL: PublishOutcome] {
        await withTaskGroup(of: (URL, PublishOutcome).self) { group in
            for url in relays {
                group.addTask { (url, await send(json: json, eventId: eventId, to: url)) }
            }
            var out: [URL: PublishOutcome] = [:]
            for await (url, outcome) in group { out[url] = outcome }
            return out
        }
    }

    private func send(json: String, eventId: String, to url: URL) async -> PublishOutcome {
        if Task.isCancelled { return .failed("cancelled") }
        let connection: RelayConnection
        do { connection = try await transport.connect(url) } catch { return .failed("connect") }
        defer { connection.close() }
        return await withTaskCancellationHandler {
            do {
                // The stored JSON goes out unchanged inside the EVENT frame.
                try await connection.send("[\"EVENT\"," + json + "]")
            } catch {
                return .failed("send")
            }
            let timeout = self.timeout
            return await withTaskGroup(of: PublishOutcome?.self) { group in
                group.addTask {
                    while true {
                        guard let text = try? await connection.receive() else { return .failed("closed") }
                        // Only an OK for this id counts. A NOTICE, an OK for
                        // another id, or the connection itself never does.
                        if case .ok(let id, let accepted, let message) = RelayMessage.parse(text), id == eventId {
                            return accepted ? .accepted : .rejected(message)
                        }
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }
                let first = await group.next() ?? nil
                group.cancelAll()
                connection.close()
                return first ?? .timedOut
            }
        } onCancel: {
            connection.close()
        }
    }
}
