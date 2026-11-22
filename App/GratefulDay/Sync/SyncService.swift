import Foundation
import Observation
import SwiftData
import GratefulDayCore

/// M5b-1: reads the connected account's journal from relays and imports it.
/// **Read only: nothing is ever published from here.**
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable { case idle, reading, done(RemoteImporter.Summary), failed }

    private(set) var status: Status = .idle
    private(set) var relays: RelaySet?
    /// The settings read for M5b-2's writer (never written here).
    private(set) var settings: RemoteSettings = .unknown

    private let fetcher: RelayFetcher
    /// The read in progress, if any; cancelled when the app leaves the foreground.
    private var task: Task<Void, Never>?
    private var taskToken: UUID?

    init(transport: RelayTransport = WebSocketTransport()) {
        fetcher = RelayFetcher(transport: transport)
    }

    /// Start a read pass unless one is already running. A cancelled pass is
    /// allowed to finish closing its sockets first.
    func start(owner: String, secret: Data, context: ModelContext) {
        if let task, !task.isCancelled { return }
        let previous = task
        let token = UUID()
        taskToken = token
        task = Task { [weak self] in
            await previous?.value
            if !Task.isCancelled { await self?.run(owner: owner, secret: secret, context: context) }
            self?.finished(token)
        }
    }

    /// The app went to the background: stop reading and close every relay
    /// connection. Nothing is imported from a stopped pass.
    func stop() { task?.cancel() }

    private func finished(_ token: UUID) {
        guard taskToken == token else { return }
        task = nil
        taskToken = nil
    }

    /// One read pass. Unresolved relays are recorded, never read as empty.
    func run(owner: String, secret: Data, context: ModelContext) async {
        guard status != .reading else { return }
        status = .reading
        let bootstrap = RelaySet.defaultRead
        let listResult = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [10002]), from: bootstrap)
        if Task.isCancelled { status = .idle; return }
        let set = RelaySet.from(RelaySet.lookup(listResult, owner: owner, bootstrap: bootstrap))
        relays = set
        let journal = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [DailyEntry.kind, 5]), from: set.read)
        let settingsResult = await fetcher.fetch(
            RelayFilter(authors: [owner], kinds: [AppSettings.kind], tagD: [AppSettings.dTag]), from: set.read)
        // Stopped part-way (backgrounded): import nothing from a partial read.
        if Task.isCancelled { status = .idle; return }
        settings = RemoteSettings.read(settingsResult.events, owner: owner, privateKey: secret)
        let days = RemoteJournal.days(from: journal.events, owner: owner, privateKey: secret)
        do {
            let summary = try RemoteImporter(context: context, owner: owner).apply(days)
            status = .done(summary)
        } catch {
            StorageLog.error("Importing from relays failed", error: error)
            status = .failed
        }
    }
}
