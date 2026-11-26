import Foundation

/// One relay pass's view of the transport: a relay whose socket didn't open
/// is dialed once in the pass, not once per query.
///
/// A pass makes five queries one after the other before its first send (the
/// relay list, the journal, the settings, then the day's versions and
/// deletions). A relay that never finishes connecting held each of them for
/// the whole timeout, so one such relay among the defaults (relay.nostr.band)
/// put 40 s in front of every send, and the pass was cancelled whenever the
/// iPhone locked first. Nothing was ever sent.
///
/// A skipped relay is reported as a failed connection: unknown, never
/// "answered" and never an acknowledgement, exactly as if it had been dialed
/// and timed out again. Only a socket that never opened is skipped. A relay
/// that connected and was slow, closed, or refused is dialed again as before,
/// and every new pass starts with nothing skipped.
struct PassTransport: RelayTransport {
    /// The relays that didn't open in one pass, shared by the pass's reads
    /// and its sends.
    final class Unreachable: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: Set<URL>
        /// Starts with relays already known not to open (remembered from an
        /// earlier pass, `SyncService`): they aren't dialed at all.
        private var openedURLs: Set<URL> = []
        init(_ known: Set<URL> = []) { urls = known }
        var all: Set<URL> { lock.withLock { urls } }
        func insert(_ url: URL) { lock.withLock { _ = urls.insert(url) } }
        /// Relays whose first send got an answer from the socket in this pass:
        /// proof the phone's network worked (Audit #22 M1).
        var opened: Set<URL> { lock.withLock { openedURLs } }
        func noteOpened(_ url: URL) { lock.withLock { _ = openedURLs.insert(url) } }
    }

    let base: RelayTransport
    let unreachable: Unreachable

    func connect(_ url: URL) async throws -> RelayConnection {
        if unreachable.all.contains(url) { throw URLError(.cannotConnectToHost) }
        let unreachable = self.unreachable
        return Probe(try await base.connect(url), opened: { unreachable.noteOpened(url) }) { unreachable.insert(url) }
    }

    /// Passes everything through, and reports a connection that is closed
    /// while its first send is still waiting for the socket to open.
    final class Probe: RelayConnection, @unchecked Sendable {
        private enum FirstSend { case notStarted, waiting, finished }
        private let inner: RelayConnection
        private let neverOpened: @Sendable () -> Void
        private let opened: @Sendable () -> Void
        private let lock = NSLock()
        private var firstSend = FirstSend.notStarted

        init(_ inner: RelayConnection, opened: @escaping @Sendable () -> Void = {},
             neverOpened: @escaping @Sendable () -> Void) {
            self.inner = inner
            self.opened = opened
            self.neverOpened = neverOpened
        }

        var url: URL { inner.url }

        func send(_ text: String) async throws {
            let first = lock.withLock { () -> Bool in
                guard firstSend == .notStarted else { return false }
                firstSend = .waiting
                return true
            }
            // Whether it succeeds or throws, the socket gave an answer.
            defer { if first { lock.withLock { if firstSend == .waiting { firstSend = .finished } } } }
            try await inner.send(text)
            // The send went through: the socket opened.
            if first { opened() }
        }

        func receive() async throws -> String { try await inner.receive() }

        func close() {
            let waiting = lock.withLock { () -> Bool in
                guard firstSend == .waiting else { return false }
                firstSend = .finished
                return true
            }
            if waiting { neverOpened() }
            inner.close()
        }
    }
}
