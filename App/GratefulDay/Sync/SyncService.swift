import Foundation
import Observation
import SwiftData
import GratefulDayCore

/// Reads the connected account's journal from relays and imports it (M5b-1),
/// then publishes local changes through `PublishPass` (M5b-2). Publishing
/// happens only after spec A's disclosure was accepted, with a known,
/// non-empty write set, and after a complete import.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable { case idle, reading, done(RemoteImporter.Summary), failed }

    private(set) var status: Status = .idle
    private(set) var relays: RelaySet?
    /// The settings read for M5b-2's writer (never written here).
    private(set) var settings: RemoteSettings = .unknown
    /// Why the last pass published nothing, if it didn't.
    enum PublishDeferral: Equatable {
        /// Spec A's disclosure hasn't been accepted yet.
        case notAllowedYet
        /// The relay-list lookup didn't resolve (Audit A2): retried later.
        case relayListUnknown
        /// The user's own list names no write relay (Seth 3f1c5fd4): never
        /// publish anywhere; Prep's copy explains.
        case noWriteRelays
    }
    private(set) var publishDeferral: PublishDeferral?
    private(set) var lastPublish: PublishPass.Summary?

    private let fetcher: RelayFetcher
    private let publisher: RelayPublisher
    /// The read in progress, if any; cancelled when the app leaves the foreground.
    private var task: Task<Void, Never>?
    private var taskToken: UUID?

    init(transport: RelayTransport = WebSocketTransport()) {
        fetcher = RelayFetcher(transport: transport)
        publisher = RelayPublisher(transport: transport)
    }

    init(fetcher: RelayFetcher, publisher: RelayPublisher) {
        self.fetcher = fetcher
        self.publisher = publisher
    }

    /// Start a read pass unless one is already running. A cancelled pass is
    /// allowed to finish closing its sockets first.
    func start(owner: String, secret: Data, context: ModelContext, isCurrent: @escaping @MainActor () -> Bool) {
        if let task, !task.isCancelled { return }
        let previous = task
        let token = UUID()
        taskToken = token
        task = Task { [weak self] in
            await previous?.value
            if !Task.isCancelled { await self?.run(owner: owner, secret: secret, context: context, isCurrent: isCurrent) }
            self?.finished(token)
        }
    }

    /// The app went to the background: stop reading and close every relay
    /// connection. Nothing is imported from a stopped pass.
    func stop() { task?.cancel() }

    /// The account or the store changed (sign-out, removal, another account):
    /// stop, and forget what was read for the old account.
    func reset() {
        stop()
        relays = nil
        settings = .unknown
        publishDeferral = nil
        lastPublish = nil
    }

    private func finished(_ token: UUID) {
        guard taskToken == token else { return }
        task = nil
        taskToken = nil
    }

    /// One read pass. Unresolved relays are recorded, never read as empty.
    /// `isCurrent` is checked after the fetches, before anything is written:
    /// if the store was replaced ("Remove account and local data") or the
    /// account is no longer connected as `owner` (signed out), the pass is
    /// dropped. Writing through the old context would crash, and writing after
    /// sign-out would be a write the person didn't expect (Audit M3).
    func run(owner: String, secret: Data, context: ModelContext,
             isCurrent: @escaping @MainActor () -> Bool = { true }) async {
        guard status != .reading else { return }
        status = .reading
        let bootstrap = RelaySet.defaultRead
        let listResult = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [10002]), from: bootstrap)
        if Task.isCancelled { status = .idle; return }
        let set = RelaySet.from(RelaySet.lookup(listResult, owner: owner, bootstrap: bootstrap))
        let journal = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [DailyEntry.kind, 5]), from: set.read)
        let settingsResult = await fetcher.fetch(
            RelayFilter(authors: [owner], kinds: [AppSettings.kind], tagD: [AppSettings.dTag]), from: set.read)
        // Stopped part-way (backgrounded), or the store or account changed
        // while reading: import nothing.
        if Task.isCancelled || !isCurrent() { status = .idle; return }
        relays = set
        settings = RemoteSettings.read(settingsResult.events, owner: owner, privateKey: secret)
        let days = RemoteJournal.days(from: journal.events, owner: owner, privateKey: secret)
        let summary: RemoteImporter.Summary
        do {
            summary = try RemoteImporter(context: context, owner: owner).apply(days)
        } catch {
            StorageLog.error("Importing from relays failed", error: error)
            status = .failed
            return
        }
        await publish(owner: owner, secret: secret, context: context, set: set, isCurrent: isCurrent)
        status = .done(summary)
    }

    /// Publish after a complete import. Never runs past an unknown or empty
    /// write set, or before spec A's disclosure.
    private func publish(owner: String, secret: Data, context: ModelContext, set: RelaySet,
                         isCurrent: @escaping @MainActor () -> Bool) async {
        lastPublish = nil
        guard let write = set.write else { publishDeferral = .relayListUnknown; return }
        guard !write.isEmpty else { publishDeferral = .noWriteRelays; return }
        // Spec A: accepted for this account on this iPhone.
        let allowed = (try? PublishDisclosure(context: context, owner: owner).isAccepted()) ?? false
        guard allowed else { publishDeferral = .notAllowedYet; return }
        publishDeferral = nil
        let pass = PublishPass(context: context, owner: owner, secret: secret, set: set,
                               fetcher: fetcher, publisher: publisher, isCurrent: isCurrent)
        do {
            lastPublish = try await pass.run()
        } catch {
            StorageLog.error("Publishing failed", error: error)
        }
    }
}
