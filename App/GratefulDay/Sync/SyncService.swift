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

    /// The Saving mark's tap text: different while the account lists
    /// nowhere to save, since "we'll keep trying" would be false (§1).
    static func savingDetail(_ sync: SyncService, text: String = "", isToday: Bool = false) -> String {
        if sync.relays?.write?.isEmpty == true { return SyncCopy.savingDetailNoWriteRelays }
        return SyncCopy.savingDetail
    }

    /// Runs a read-then-publish pass for the connected account (set by the
    /// app). Used by Try now and after conflict choices.
    var runner: (() -> Void)?
    /// Try now dials every relay again (Audit #22 M1): the person asked.
    func tryNow() {
        unreachableSince = [:]
        runner?()
    }

    /// The last read didn't complete (spec B): nothing was published.
    var couldNotReach: Bool { status == .failed || publishDeferral == .relayListUnknown }
    private(set) var lastPublish: PublishPass.Summary?

    /// The configured clients. Each pass uses copies of them over its own
    /// `PassTransport`, so a relay that never connects is dialed once a pass.
    private let baseFetcher: RelayFetcher
    private let basePublisher: RelayPublisher
    /// The read in progress, if any; cancelled when the app leaves the foreground.
    private var task: Task<Void, Never>?
    private var taskToken: UUID?

    // MARK: Passes after a local save, and retries, in the foreground only

    /// Set by the app: false once the scene is in the background. Nothing
    /// below starts a pass, or keeps one waiting, outside the foreground.
    var isForeground = false {
        didSet { if !isForeground { cancelScheduled() } }
    }
    /// Set by the app: true only while the scene is active. A save that
    /// lands while it isn't (the editor flushing as the app goes inactive)
    /// starts its pass now, rather than after the quiet time (R2).
    var isActive = false
    /// Set by the app: whether spec A's disclosure was accepted for the
    /// connected account. A save starts no pass before it, so saving never
    /// leads to a relay read the person hasn't agreed to publish after.
    var publishAllowed: (@MainActor () -> Bool)?
    /// Quiet time after the last save before a pass starts, so one sitting
    /// makes one publish, not one per local save (Prep §2.2 R2: about 30 s,
    /// never under 15 s). Each publish is a public edit time and an earlier
    /// version the key can read forever.
    static let saveQuietTime: Duration = .seconds(30)
    var saveDebounce: Duration = SyncService.saveQuietTime
    /// The shortest wait before a foreground retry, whatever a row's backoff says.
    var minimumRetryDelay: TimeInterval = 30
    /// Clock for passes and retry scheduling, and the wait before a retry
    /// (tests replace both).
    var now: () -> Date = { .now }
    var retrySleep: @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    private var debounce: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    var retryPending: Bool { retry != nil }
    /// A save landed while a pass was running: run one more pass after it,
    /// since the running pass may already have chosen what to publish.
    private(set) var followUpRequested = false
    /// Relays whose socket didn't open in a finished pass, and when. For
    /// `unreachableMemory` after that, later passes don't dial them: they are
    /// reported at once as a failed connection (unknown, never "answered",
    /// never an acknowledgement), exactly as within one pass (#20). In memory
    /// only; `reset()` (an account or store change) forgets them. A pass that
    /// was cancelled adds nothing, since its sockets were closed while still
    /// opening. Relay reliability, Priority B (Chief 2dfa43a6).
    private(set) var unreachableSince: [URL: Date] = [:]
    var unreachableMemory: TimeInterval = 600
    /// Whether, with `remembered` not dialed, at least 2 bootstrap relays and
    /// at least 2 write relays (all of them when there are fewer than 2) are
    /// still dialed (Chief P47).
    static func keepsEnoughDialable(remembered: Set<URL>, bootstrap: [URL], write: [URL]?) -> Bool {
        func enough(_ relays: [URL]) -> Bool {
            let unique = Set(relays)
            return unique.subtracting(remembered).count >= min(2, unique.count)
        }
        return enough(bootstrap) && enough(write ?? [])
    }

    /// Remembered relays still inside `unreachableMemory`.
    func rememberedUnreachable() -> Set<URL> {
        let now = now()
        return Set(unreachableSince.filter { now.timeIntervalSince($0.value) < unreachableMemory }.keys)
    }

    /// The owner's days and the relay event each local copy is based on
    /// (D7 rule 3). Only the connected account's own rows.
    static func localBases(owner: String, context: ModelContext) throws -> [String: String] {
        let o: String? = owner
        let rows = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate {
            $0.ownerPubkey == o && $0.remoteEventID != nil
        }))
        var out: [String: String] = [:]
        for row in rows { if let id = row.remoteEventID { out[row.dateString] = id } }
        return out
    }

    /// When the last finished pass's earliest waiting row is due again.
    private(set) var nextRetryAt: Date?

    init(transport: RelayTransport = WebSocketTransport()) {
        baseFetcher = RelayFetcher(transport: transport)
        basePublisher = RelayPublisher(transport: transport)
    }

    init(fetcher: RelayFetcher, publisher: RelayPublisher) {
        baseFetcher = fetcher
        basePublisher = publisher
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

    /// A reflection was saved or deleted on this iPhone. In the foreground,
    /// with the disclosure accepted, a pass starts once saves have been quiet
    /// for `saveDebounce`. If a pass is running then, another runs after it;
    /// passes never overlap. The pass itself keeps every publishing rule.
    func localChangeSaved() {
        guard isForeground else { return }
        debounce?.cancel()
        debounce = nil
        guard isActive else { requestPass(reason: "after a save, leaving the app"); return }
        let delay = saveDebounce
        debounce = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.debounce = nil
            self.requestPass(reason: "after a save")
        }
    }

    /// The person left Today, or the app is becoming inactive: start the
    /// pass a pending save is waiting for now, rather than after the quiet
    /// time (R2). Does nothing when no save is waiting.
    func flushPendingSave() {
        guard let pending = debounce else { return }
        pending.cancel()
        debounce = nil
        requestPass(reason: "after a save, leaving the editor")
    }

    /// Start a pass now, or right after the one running.
    private func requestPass(reason: String) {
        guard isForeground, publishAllowed?() == true else { return }
        if let task, !task.isCancelled {
            followUpRequested = true
            SyncLog.note("pass queued", reason)
            return
        }
        SyncLog.note("pass requested", reason)
        runner?()
    }

    /// Cancel any pass that's waiting to start (not the running one).
    private func cancelScheduled() {
        debounce?.cancel()
        debounce = nil
        retry?.cancel()
        retry = nil
        followUpRequested = false
    }

    /// After a pass: run the queued one, or wait for the earliest row that's
    /// due again (its backoff, at least `minimumRetryDelay`).
    private func scheduleAfterPass() {
        guard isForeground else { return }
        if followUpRequested {
            followUpRequested = false
            requestPass(reason: "saved during the last pass")
            return
        }
        retry?.cancel()
        retry = nil
        guard let due = nextRetryAt else { return }
        let wait = max(due.timeIntervalSince(now()), minimumRetryDelay)
        let sleep = retrySleep
        SyncLog.note("retry scheduled", "in \(Int(wait)) s")
        retry = Task { [weak self] in
            await sleep(wait)
            guard !Task.isCancelled, let self else { return }
            self.retry = nil
            self.requestPass(reason: "retry")
        }
    }

    /// The app went to the background: stop reading and close every relay
    /// connection. Nothing is imported from a stopped pass, and no pass is
    /// left waiting to start.
    func stop() {
        cancelScheduled()
        task?.cancel()
    }

    /// The account or the store changed (sign-out, removal, another account):
    /// stop, and forget what was read for the old account.
    func reset() {
        stop()
        relays = nil
        settings = .unknown
        publishDeferral = nil
        lastPublish = nil
        nextRetryAt = nil
        unreachableSince = [:]
    }

    private func finished(_ token: UUID) {
        guard taskToken == token else { return }
        let cancelled = task?.isCancelled ?? true
        task = nil
        taskToken = nil
        if !cancelled { scheduleAfterPass() }
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
        // Seth M (option 2): one socket per relay for the whole pass, shared
        // by its reads and sends. They are all closed when the pass ends, and
        // at once when it's cancelled (background, sign-out, another
        // account), so no socket is reused by a later pass or account.
        let shared = SharedConnections(base: baseFetcher.transport)
        await withTaskCancellationHandler {
            await pass(owner: owner, secret: secret, context: context, isCurrent: isCurrent, shared: shared)
        } onCancel: {
            shared.closeAll()
        }
        shared.closeAll()
        let stats = shared.statistics
        if !stats.isEmpty { SyncLog.note("sockets this pass", SyncLog.describe(stats)) }
    }

    private func pass(owner: String, secret: Data, context: ModelContext,
                      isCurrent: @escaping @MainActor () -> Bool, shared: SharedConnections) async {
        status = .reading
        // A pass that stops before publishing schedules no retry.
        nextRetryAt = nil
        SyncLog.note("pass started")
        var fetcher = baseFetcher, publisher = basePublisher
        // One list for the pass: a relay that didn't open for a read isn't
        // waited on again for a later read or for the send.
        let remembered = rememberedUnreachable()
        if !remembered.isEmpty { SyncLog.note("not dialed, remembered as not opening", SyncLog.hosts(remembered.sorted { $0.absoluteString < $1.absoluteString })) }
        let unreachable = PassTransport.Unreachable(remembered)
        fetcher.transport = PassTransport(base: shared, unreachable: unreachable)
        publisher.transport = PassTransport(base: shared, unreachable: unreachable)
        let bootstrap = RelaySet.defaultRead
        let listResult = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [10002]), from: bootstrap)
        SyncLog.note("relay list read", SyncLog.describe(listResult.outcomes))
        if Task.isCancelled { SyncLog.note("pass stopped", "cancelled after the relay list"); status = .idle; return }
        let set = RelaySet.from(RelaySet.lookup(listResult, owner: owner, bootstrap: bootstrap))
        SyncLog.note("relay set", "read: \(SyncLog.hosts(set.read)); write: \(SyncLog.hosts(set.write))")
        // The journal and the settings are read at the same time, each on its
        // own connections; each keeps its own outcomes (and `.unresolved`).
        let reader = fetcher
        async let journalRead = reader.fetch(RelayFilter(authors: [owner], kinds: [DailyEntry.kind, 5]), from: set.read)
        async let settingsRead = reader.fetch(
            RelayFilter(authors: [owner], kinds: [AppSettings.kind], tagD: [AppSettings.dTag]), from: set.read)
        let (journal, settingsResult) = await (journalRead, settingsRead)
        // Stopped part-way (backgrounded), or the store or account changed
        // while reading: import nothing.
        SyncLog.note("journal read", "\(journal.events.count) events; \(SyncLog.describe(journal.outcomes))")
        SyncLog.note("settings read", SyncLog.describe(settingsResult.outcomes))
        if Task.isCancelled || !isCurrent() {
            SyncLog.note("pass stopped", Task.isCancelled ? "cancelled after reading" : "account or store changed")
            status = .idle
            return
        }
        relays = set
        settings = RemoteSettings.read(settingsResult.events, owner: owner, privateKey: secret)
        // D7 rule 3: an `e`-only kind 5 acts only on the day whose copy is
        // based on exactly the event it names.
        let localBases: [String: String]
        do { localBases = try Self.localBases(owner: owner, context: context) } catch {
            StorageLog.error("Reading local bases failed", error: error)
            status = .failed
            return
        }
        let days = RemoteJournal.days(from: journal.events, owner: owner, privateKey: secret, localBases: localBases)
        let summary: RemoteImporter.Summary
        do {
            summary = try RemoteImporter(context: context, owner: owner).apply(days)
            // Milestones this account passed elsewhere are never shown here.
            try JournalRepository(context: context, activeOwner: owner).markPassedMilestonesSeen()
        } catch {
            StorageLog.error("Importing from relays failed", error: error)
            status = .failed
            return
        }
        await publish(owner: owner, secret: secret, context: context, set: set,
                      fetcher: fetcher, publisher: publisher, isCurrent: isCurrent)
        let skipped = unreachable.all.subtracting(remembered).sorted { $0.absoluteString < $1.absoluteString }
        if !skipped.isEmpty { SyncLog.note("never connected, dialed once", SyncLog.hosts(skipped)) }
        // Remember them for later passes, unless this pass was stopped or the
        // account changed (then nothing it learned is kept), or no relay at
        // all opened: then it's the phone's network that stalled, not those
        // relays, and remembering them would shut out every relay after the
        // network is back (Audit #22 M1).
        let networkWorked = !unreachable.opened.isEmpty
        if !skipped.isEmpty, !networkWorked { SyncLog.note("not remembered", "no relay opened in this pass") }
        if !Task.isCancelled, isCurrent(), networkWorked {
            let at = now()
            unreachableSince = unreachableSince.filter { at.timeIntervalSince($0.value) < unreachableMemory }
            // Chief P47 (Audit #22 L1): never remember so many that fewer
            // than 2 bootstrap relays, or fewer than 2 of the account's write
            // relays (all of them when it has fewer than 2), stay dialable.
            // Otherwise a partial stall would block every automatic pass's
            // two-answer rule until the memory expires.
            var held: [URL] = []
            for url in skipped {
                var next = Set(unreachableSince.keys)
                next.insert(url)
                if Self.keepsEnoughDialable(remembered: next, bootstrap: bootstrap, write: set.write) {
                    unreachableSince[url] = at
                } else {
                    held.append(url)
                }
            }
            if !held.isEmpty { SyncLog.note("not remembered", "too few would be left to dial: \(SyncLog.hosts(held))") }
        }
        if let deferral = publishDeferral { SyncLog.note("publishing deferred", "\(deferral)") }
        if let p = lastPublish {
            SyncLog.note("pass finished", "signed \(p.signed), sent \(p.sent), synced \(p.synced), deferred \(p.deferred), conflicts \(p.conflicts), waiting on deletion \(p.waitingOnDeletion)")
        } else {
            SyncLog.note("pass finished", "nothing published")
        }
        status = .done(summary)
    }

    /// Publish after a complete import. Never runs past an unknown or empty
    /// write set, or before spec A's disclosure.
    private func publish(owner: String, secret: Data, context: ModelContext, set: RelaySet,
                         fetcher: RelayFetcher, publisher: RelayPublisher,
                         isCurrent: @escaping @MainActor () -> Bool) async {
        lastPublish = nil
        nextRetryAt = nil
        guard let write = set.write else { publishDeferral = .relayListUnknown; return }
        guard !write.isEmpty else { publishDeferral = .noWriteRelays; return }
        // Spec A: accepted for this account on this iPhone.
        let allowed = (try? PublishDisclosure(context: context, owner: owner).isAccepted()) ?? false
        guard allowed else { publishDeferral = .notAllowedYet; return }
        publishDeferral = nil
        // Spec B step 3: days written here without an account are sorted
        // against what was just read, before anything is published.
        do {
            try FirstConnectSort(context: context, owner: owner).run()
        } catch {
            StorageLog.error("Sorting this iPhone's days failed", error: error)
            return
        }
        var pass = PublishPass(context: context, owner: owner, secret: secret, set: set,
                               fetcher: fetcher, publisher: publisher, isCurrent: isCurrent)
        pass.now = now
        let passStarted = now()
        do {
            lastPublish = try await pass.run()
            nextRetryAt = try Outbox(context: context, owner: owner).nextAttempt(write: write, after: passStarted)
        } catch {
            StorageLog.error("Publishing failed", error: error)
        }
    }
}
