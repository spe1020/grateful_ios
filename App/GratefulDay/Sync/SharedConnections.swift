import Foundation

/// One socket per relay for a whole sync pass (Seth M, option 2; Prep's
/// acceptance criteria, PLANS/GRATEFUL_DAY_M_FIRST_SYNC_ACCEPTANCE_2026_11_27.md).
///
/// Every read and send used to dial its own socket: a 60-day first sync made
/// hundreds of WebSocket handshakes a pass, and nos.lol and nostr.wine
/// refused most of them (HTTP 429 on handshake; backlog run 2). Here
/// `connect` hands out a *lease* on the pass's socket to that relay, dialing
/// it only the first time. What each query sees is unchanged:
///
/// - A lease receives every message that arrives on the socket while it is
///   open, and nothing from before it was opened. Callers already match by
///   their own subscription id (`RelayFetcher`) or event id (`RelayPublisher`),
///   so one query's EOSE, EVENT, CLOSED or OK never counts for another.
/// - Closing a lease ends only that lease: its pending receive throws, and
///   the relay is sent CLOSE for any subscription it left open. The socket
///   stays up for the rest of the pass.
/// - If the socket drops, every lease on it fails (its queries are unknown,
///   never answered or acknowledged). The relay is dialed again at most once
///   in the pass, and only if the dropped socket had opened. A socket that
///   never opened, or a second drop, leaves the relay unreachable for the
///   rest of the pass: `connect` fails at once (a failed connection, as in
///   `PassTransport`).
/// - `closeAll` closes every socket. It runs when the pass ends, is
///   cancelled (background) or stops because the account changed, so no
///   socket outlives its pass or is shared across accounts.
final class SharedConnections: RelayTransport, @unchecked Sendable {
    /// Per relay: sockets opened in this pass and handshake statuses seen.
    struct Stats: Equatable, Sendable {
        var dials = 0
        var drops = 0
        /// HTTP status codes of failed handshakes (numbers only, I9).
        var handshakeStatuses: [Int] = []
    }

    private let base: RelayTransport
    private let lock = NSLock()
    private var sockets: [URL: Socket] = [:]
    private var stats: [URL: Stats] = [:]
    /// Relays not to dial again in this pass.
    private var dead: Set<URL> = []
    private var closed = false
    static let maxRedials = 1

    init(base: RelayTransport) { self.base = base }

    var statistics: [URL: Stats] { lock.withLock { stats } }

    func connect(_ url: URL) async throws -> RelayConnection {
        // Reserve the slot under the lock, so concurrent connects share one dial.
        let (socket, isNew) = try reserve(url)
        if isNew {
            do {
                try await socket.attach(base.connect(url))
            } catch {
                socket.fail()
                throw error
            }
        }
        return socket.lease()
    }

    /// The pass's live socket to `url`, or a new one to dial.
    private func reserve(_ url: URL) throws -> (Socket, Bool) {
        try lock.withLock {
            if closed || dead.contains(url) { throw URLError(.cannotConnectToHost) }
            if let s = sockets[url], !s.isDown { return (s, false) }
            var st = stats[url, default: Stats()]
            if let old = sockets[url], old.isDown {
                // A redial: only after a socket that had opened, and only once.
                guard old.everOpened, st.dials <= Self.maxRedials else {
                    dead.insert(url)
                    throw URLError(.cannotConnectToHost)
                }
            }
            st.dials += 1
            stats[url] = st
            let s = Socket(url: url) { [weak self] socket in self?.socketWentDown(socket) }
            sockets[url] = s
            return (s, true)
        }
    }

    private func socketWentDown(_ socket: Socket) {
        lock.withLock {
            var st = stats[socket.url, default: Stats()]
            st.drops += 1
            if let code = socket.handshakeStatus { st.handshakeStatuses.append(code) }
            stats[socket.url] = st
            // I7: a socket that never opened isn't dialed again in the pass.
            // F1/F5: after one redial, a second drop ends it too.
            if !socket.everOpened || st.dials > Self.maxRedials { dead.insert(socket.url) }
        }
    }

    /// Close every socket; later connects fail. Idempotent.
    func closeAll() {
        let all = lock.withLock { () -> [Socket] in
            closed = true
            return Array(sockets.values)
        }
        for s in all { s.close() }
    }

    // MARK: - One socket

    final class Socket: @unchecked Sendable {
        let url: URL
        private let lock = NSLock()
        private var inner: RelayConnection?
        private var leases: [ObjectIdentifier: Lease] = [:]
        private var down = false
        private var opened = false
        private var reader: Task<Void, Never>?
        /// Sends issued before the connection was attached.
        private var attachWaiters: [CheckedContinuation<RelayConnection, Error>] = []
        private let onDown: @Sendable (Socket) -> Void

        init(url: URL, onDown: @escaping @Sendable (Socket) -> Void) {
            self.url = url
            self.onDown = onDown
        }

        var isDown: Bool { lock.withLock { down } }
        var everOpened: Bool { lock.withLock { opened } }
        var handshakeStatus: Int? { lock.withLock { (inner as? HandshakeReporting)?.handshakeStatus } }

        func attach(_ connection: RelayConnection) {
            let waiters = lock.withLock { () -> [CheckedContinuation<RelayConnection, Error>]? in
                guard !down else { return nil }
                inner = connection
                let w = attachWaiters
                attachWaiters = []
                return w
            }
            guard let waiters else { connection.close(); return }
            for w in waiters { w.resume(returning: connection) }
            reader = Task { [weak self] in await self?.readLoop(connection) }
        }

        /// The dial itself failed.
        func fail() { goDown() }

        func lease() -> Lease {
            let lease = Lease(socket: self)
            let ok = lock.withLock { () -> Bool in
                guard !down else { return false }
                leases[ObjectIdentifier(lease)] = lease
                return true
            }
            if !ok { lease.end() }
            return lease
        }

        fileprivate func remove(_ lease: Lease) {
            lock.withLock { _ = leases.removeValue(forKey: ObjectIdentifier(lease)) }
        }

        fileprivate func connection() async throws -> RelayConnection {
            try await withCheckedThrowingContinuation { c in
                lock.lock()
                if down { lock.unlock(); c.resume(throwing: URLError(.networkConnectionLost)); return }
                if let inner { lock.unlock(); c.resume(returning: inner); return }
                attachWaiters.append(c)
                lock.unlock()
            }
        }

        fileprivate func send(_ text: String) async throws {
            let connection = try await connection()
            do {
                try await connection.send(text)
                lock.withLock { opened = true }
            } catch {
                // A failed send means the socket is gone (or never opened).
                goDown()
                throw error
            }
        }

        /// A lease gave up while its send was still waiting for the socket
        /// to open: the socket never opened in time (`PassTransport.Probe`
        /// reports it). Close it so every other waiting send ends too.
        fileprivate func abandonedWhileOpening() {
            if !everOpened { goDown() }
        }

        private func readLoop(_ connection: RelayConnection) async {
            while true {
                let text: String
                do { text = try await connection.receive() } catch { goDown(); return }
                lock.withLock { opened = true }
                let current = lock.withLock { Array(leases.values) }
                for l in current { l.deliver(text) }
            }
        }

        private func goDown() {
            let (current, inner, waiters, first) = lock.withLock { () -> ([Lease], RelayConnection?, [CheckedContinuation<RelayConnection, Error>], Bool) in
                let first = !down
                down = true
                let current = Array(leases.values)
                leases = [:]
                let w = attachWaiters
                attachWaiters = []
                return (current, self.inner, w, first)
            }
            for w in waiters { w.resume(throwing: URLError(.networkConnectionLost)) }
            for l in current { l.end() }
            inner?.close()
            if first { onDown(self) }
        }

        func close() {
            goDown()
            reader?.cancel()
        }
    }

    // MARK: - One caller's view

    final class Lease: RelayConnection, @unchecked Sendable {
        private let socket: Socket
        private let lock = NSLock()
        private var queue: [String] = []
        private var waiter: CheckedContinuation<String, Error>?
        private var ended = false
        /// Subscriptions this lease opened and the relay hasn't ended.
        private var openSubscriptions: Set<String> = []
        private var sending = 0

        init(socket: Socket) { self.socket = socket }

        var url: URL { socket.url }

        func send(_ text: String) async throws {
            if lock.withLock({ ended }) { throw URLError(.cancelled) }
            let req = Self.subscription(in: text, command: "REQ")
            let close = Self.subscription(in: text, command: "CLOSE")
            lock.withLock {
                sending += 1
                if let req { openSubscriptions.insert(req) }
                if let close { openSubscriptions.remove(close) }
            }
            defer { lock.withLock { sending -= 1 } }
            try await socket.send(text)
        }

        func receive() async throws -> String {
            let text = try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
                lock.lock()
                if !queue.isEmpty { let s = queue.removeFirst(); lock.unlock(); c.resume(returning: s); return }
                if ended { lock.unlock(); c.resume(throwing: URLError(.cancelled)); return }
                waiter = c
                lock.unlock()
            }
            // The relay ended a subscription of ours: nothing to CLOSE later.
            if let sub = Self.endedSubscription(text) { lock.withLock { _ = openSubscriptions.remove(sub) } }
            return text
        }

        fileprivate func deliver(_ text: String) {
            lock.lock()
            if ended { lock.unlock(); return }
            if let w = waiter { waiter = nil; lock.unlock(); w.resume(returning: text); return }
            queue.append(text)
            lock.unlock()
        }

        /// Ends this lease only (the socket went down, or the caller closed).
        fileprivate func end() {
            lock.lock()
            ended = true
            queue = []
            let w = waiter
            waiter = nil
            lock.unlock()
            w?.resume(throwing: URLError(.cancelled))
        }

        func close() {
            let (first, subs, wasSending) = lock.withLock { () -> (Bool, Set<String>, Bool) in
                let first = !ended
                let subs = openSubscriptions
                openSubscriptions = []
                return (first, subs, sending > 0)
            }
            guard first else { return }
            end()
            socket.remove(self)
            if wasSending { socket.abandonedWhileOpening() }
            // Leave nothing running on the relay for a query that gave up.
            if !subs.isEmpty, !socket.isDown {
                let socket = self.socket
                Task { for sub in subs { try? await socket.send(Self.closeFrame(sub)) } }
            }
        }

        static func closeFrame(_ sub: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: ["CLOSE", sub])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }

        /// The subscription id of a client `REQ` or `CLOSE` frame.
        static func subscription(in text: String, command: String) -> String? {
            guard text.hasPrefix("[\"\(command)\""),
                  let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
                  array.count >= 2, array[0] as? String == command else { return nil }
            return array[1] as? String
        }

        /// The subscription a relay EOSE or CLOSED ends.
        static func endedSubscription(_ text: String) -> String? {
            switch RelayMessage.parse(text) {
            case .eose(let sub), .closed(let sub, _): return sub
            default: return nil
            }
        }
    }
}

/// A connection that can say what HTTP status its WebSocket handshake got.
protocol HandshakeReporting {
    var handshakeStatus: Int? { get }
}
