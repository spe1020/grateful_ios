import Foundation
import SwiftData
import NostrCore
import GratefulDayCore

/// M5b-2: one publish pass for the connected account, run after a read pass
/// has imported (M5b plan r2, r2.1, P22; interop r5.1 §0.1; Seth 5c471a7e,
/// 3f1c5fd4; Audit A2, M3a I4; Chief P29).
///
/// The P29 safeguards all live here, in the same code that sends:
/// - **Refetch before every send** (first send and every retry). Any version
///   that's neither the row's base nor this device's own stops the row and
///   makes the day a conflict, at any timestamp.
/// - **`.unresolved` gate.** Only write relays that answered EOSE count
///   toward "no other copy"; a timeout, CLOSED, failure or capped page
///   (`.unresolved`) never does, and an unknown write set (A2) or an empty
///   one publishes nothing.
/// - **Archive before replace.** This pass never changes local text. Taking
///   a relay version happens only in `RemoteImporter`, which archives first.
///
/// Only the connected account's own rows are signed or sent. Guest rows
/// wait for the first-connect sort (spec B), which isn't in this pass.
@MainActor
struct PublishPass {
    let context: ModelContext
    let owner: String
    let secret: Data
    let set: RelaySet
    let fetcher: RelayFetcher
    let publisher: RelayPublisher
    /// Checked before every write and every send: the account or store may
    /// change while a relay answers (Audit M3).
    var isCurrent: @MainActor () -> Bool = { true }
    var now: () -> Date = { .now }

    struct Summary: Equatable {
        var signed = 0, sent = 0, synced = 0, deferred = 0, conflicts = 0, waitingOnDeletion = 0
    }

    private var outbox: Outbox { Outbox(context: context, owner: owner) }
    private var importer: RemoteImporter { RemoteImporter(context: context, owner: owner, now: now) }

    /// Sign what changed locally, re-check relays that didn't answer last
    /// time, then send every due row. Returns nil when nothing may be
    /// published (unknown or empty write set).
    func run() async throws -> Summary? {
        guard let write = set.write, DeliveryRules.required(write: write) != nil else { return nil }
        var summary = Summary()
        try signPending(&summary)
        for row in try outbox.awaitingRecheck() {
            guard isCurrent() else { return summary }
            try await recheck(row, relays: row.recheckRelays, write: write, summary: &summary)
        }
        for row in try outbox.due(write: write, now: now()) {
            guard isCurrent(), !Task.isCancelled else { return summary }
            // A row stopped earlier in this pass (same day) isn't sent.
            guard row.isLive else { continue }
            try await send(row, write: write, summary: &summary)
        }
        return summary
    }

    // MARK: - Signing

    /// The connected account's rows with a local change not yet signed.
    private func pendingRows() throws -> [JournalEntry] {
        let o: String? = owner, raw = SyncState.localOnly.rawValue
        return try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.ownerPubkey == o && $0.syncStateRaw == raw },
            sortBy: [SortDescriptor(\.dateString)]))
    }

    private func signPending(_ summary: inout Summary) throws {
        for entry in try pendingRows() {
            let rows = try outbox.rows(dateString: entry.dateString)
            // Already signed from this exact local state.
            if rows.contains(where: { $0.isLive && $0.entryUpdatedAt == entry.updatedAt }) { continue }
            // A stopped row means the day is a conflict; never sign past it.
            if rows.contains(where: { $0.supersededByRemote && $0.entryUpdatedAt == entry.updatedAt }) { continue }
            let newestOwn = rows.map(\.eventCreatedAt).max()
            let at = Int(now().timeIntervalSince1970)
            let event: NostrEvent
            if entry.deletedAt != nil {
                // Nothing of this day was ever on a relay: nothing to delete.
                let target = rows.filter { $0.kind == DailyEntry.kind }.max { $0.eventCreatedAt < $1.eventCreatedAt }
                guard let targetId = target?.eventId ?? entry.remoteEventID else { continue }
                // Covers every version up to now, including our own (§1.7: ≤).
                let createdAt = max(at, entry.remoteCreatedAt ?? 0, newestOwn ?? 0)
                event = try EntryDeletion.template(pubkey: owner, dateString: entry.dateString, eventId: targetId)
                    .signed(privateKey: secret, createdAt: createdAt)
            } else {
                guard !entry.notesText.isEmpty else { continue }
                guard let day = DailyEntry.Day(dateString: entry.dateString, dayOfYear: entry.dayOfYear,
                                               publishedAt: entry.publishedAt) else { continue }
                let notes = EntryNotes.split(entry.notesText)
                // Keep both can join two days past the size one event can
                // hold. The day stays here, unsent, rather than stopping the
                // whole pass (M6; copy for this case is open with Prep).
                guard EntryNotes.join(notes).utf8.count <= DailyEntry.maxContentBytes else { continue }
                let template = entry.isPrivate
                    ? try DailyEntry.privateTemplate(day: day, notes: notes, privateKey: secret)
                    : try DailyEntry.template(day: day, notes: notes)
                // Strictly after the base and after anything this device
                // signed for the day, including a queued kind 5 (§1.5, I4).
                let floor = [entry.remoteCreatedAt, newestOwn].compactMap { $0 }.max()
                event = try template.signed(privateKey: secret,
                                            createdAt: DailyEntry.publishCreatedAt(now: at, remoteCreatedAt: floor))
            }
            try outbox.enqueue(event, dateString: entry.dateString, baseEventId: entry.remoteEventID,
                               baseCreatedAt: entry.remoteCreatedAt, entryUpdatedAt: entry.updatedAt, now: now())
            summary.signed += 1
        }
    }

    // MARK: - Sending

    /// The day's 36669s and the kind 5s for its address (P30 L1), as one
    /// result. A relay counts as answered only if it answered both queries.
    private func fetchDay(_ dateString: String, from relays: [URL]) async -> FetchResult {
        let address = EntryDeletion.address(pubkey: owner, dateString: dateString)
        // One after the other: each relay gets one connection at a time.
        let e = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [DailyEntry.kind], tagD: [dateString]), from: relays)
        let d = await fetcher.fetch(RelayFilter(authors: [owner], kinds: [5], tagA: [address]), from: relays)
        var outcomes: [URL: RelayOutcome] = [:]
        for url in relays {
            let a = e.outcomes[url] ?? .failed("missing"), b = d.outcomes[url] ?? .failed("missing")
            outcomes[url] = a != .answered ? a : b
        }
        var byId: [String: NostrEvent] = [:]
        for ev in e.events + d.events { byId[ev.id] = ev }
        return FetchResult(events: Array(byId.values), outcomes: outcomes)
    }

    private var readAndWrite: [URL] {
        Array(NSOrderedSet(array: set.read + (set.write ?? []))) as? [URL] ?? set.read
    }

    private func send(_ row: OutboxEvent, write: [URL], summary: inout Summary) async throws {
        let day = row.dateString
        // A day the read pass found in conflict (or unreadable) is never
        // sent, even if the relay holding the other version is silent now.
        if let entry = try entry(day), entry.syncState == .conflict || entry.syncState == .blocked { return }
        // I4: a revived day's 36669 waits until its deletion is delivered.
        if row.kind == DailyEntry.kind,
           try outbox.rows(dateString: day).contains(where: {
               $0.kind == 5 && $0.isLive && DeliveryRules.state(acked: $0.ackedRelays, write: write) != .synced
           }) {
            summary.waitingOnDeletion += 1
            return
        }
        // Refetch before every send, the first one too (r2.1 item 2).
        let fetched = await fetchDay(day, from: readAndWrite)
        guard isCurrent(), !Task.isCancelled else { return }
        let own = try outbox.ownEventIds(dateString: day)
        switch DeliveryRules.preSendCheck(day: day, owner: owner, baseEventId: row.baseEventId,
                                          baseCreatedAt: row.baseCreatedAt, ownEventIds: own, fetched: fetched,
                                          write: write, checkDeletions: row.kind == DailyEntry.kind) {
        case .unresolved:
            try outbox.deferRow(row, now: now())
            summary.deferred += 1
            return
        case .unbasedRemote(let event):
            try stop(row, remote: event, fetched: fetched)
            summary.conflicts += 1
            return
        case .clear:
            break
        }
        let outcomes = await publisher.publish(json: row.eventJSON, eventId: row.eventId, to: write)
        guard isCurrent() else { return }
        try outbox.record(outcomes, for: row, write: write, now: now())
        summary.sent += 1
        // Write relays that didn't answer the refetch are asked again later.
        row.recheckRelays = write.filter { fetched.outcomes[$0] != .answered }
        try context.save()
        // Re-check after publishing: same test, any timestamp (r2.1 item 3).
        try await recheck(row, relays: readAndWrite, write: write, summary: &summary)
        if row.isLive, DeliveryRules.state(acked: row.ackedRelays, write: write) == .synced {
            try markSynced(row)
            summary.synced += 1
        }
    }

    /// Look on `relays` for a version this row didn't base on. Relays that
    /// answer are crossed off the row's re-check list; any unbased version
    /// stops the row and makes the day a conflict.
    private func recheck(_ row: OutboxEvent, relays: [URL], write: [URL], summary: inout Summary) async throws {
        guard !relays.isEmpty else { return }
        let fetched = await fetchDay(row.dateString, from: relays)
        guard isCurrent(), !Task.isCancelled else { return }
        let own = try outbox.ownEventIds(dateString: row.dateString)
        if let unbased = DeliveryRules.unbased(day: row.dateString, owner: owner, baseEventId: row.baseEventId,
                                               baseCreatedAt: row.baseCreatedAt, ownEventIds: own,
                                               events: fetched.events, checkDeletions: row.kind == DailyEntry.kind) {
            try stop(row, remote: unbased, fetched: fetched)
            summary.conflicts += 1
            return
        }
        row.recheckRelays = row.recheckRelays.filter { fetched.outcomes[$0] != .answered }
        try context.save()
    }

    /// Never send this row again; the day is a conflict with both texts kept.
    private func stop(_ row: OutboxEvent, remote event: NostrEvent, fetched: FetchResult) throws {
        try outbox.stopForRemote(row)
        row.recheckRelays = []
        // A lone kind 5 has no 36669 beside it to cover, so RemoteJournal
        // would return nothing for it. It is the account deleting the day
        // (Audit #16 L1): the importer must see `.deleted`.
        let remote: RemoteDay? = event.kind == 5
            ? .deleted(at: event.createdAt, by: [event.id])
            : RemoteJournal.days(from: [event], owner: owner, privateKey: secret)[row.dateString]
        try importer.conflict(dateString: row.dateString, remote: remote)
    }

    /// The row reached its acknowledgement threshold: if the entry hasn't
    /// changed since it was signed, the entry is now based on this event.
    private func entry(_ dateString: String) throws -> JournalEntry? {
        let key: String? = JournalEntry.key(owner: owner, dateString: dateString)
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    private func markSynced(_ row: OutboxEvent) throws {
        guard let entry = try entry(row.dateString), entry.syncState == .localOnly,
              entry.updatedAt == row.entryUpdatedAt else { return }
        // A revived day's kind 5 is synced, but its entry waits on the 36669.
        if row.kind == 5, entry.deletedAt == nil { return }
        entry.syncStateRaw = SyncState.synced.rawValue
        if row.kind == DailyEntry.kind {
            entry.remoteEventID = row.eventId
            entry.remoteCreatedAt = row.eventCreatedAt
        }
        try context.save()
    }
}
