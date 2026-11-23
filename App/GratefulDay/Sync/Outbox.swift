import Foundation
import SwiftData
import NostrCore
import GratefulDayCore

/// The local outbox of signed events (M5b plan r2 (b), r2.1). Rows are owned
/// like entries: only the connected account's rows are read or sent.
@MainActor
struct Outbox {
    let context: ModelContext
    let owner: String

    /// Queue a newly signed event for a day. Every older row for that day is
    /// marked superseded and never sent again, even if partly delivered.
    /// One exception (Audit M3a I4): a new 36669 for a revived day leaves a
    /// queued kind 5 live, because the deletion goes out first.
    @discardableResult
    func enqueue(_ event: NostrEvent, dateString: String, baseEventId: String?, baseCreatedAt: Int?,
                 entryUpdatedAt: Date? = nil, now: Date = .now) throws -> OutboxEvent {
        for row in try rows(dateString: dateString) where row.isLive {
            if event.kind == DailyEntry.kind && row.kind == 5 { continue }
            row.superseded = true
        }
        let data = try JSONEncoder().encode(event)
        let row = OutboxEvent(event: event, json: String(decoding: data, as: UTF8.self), ownerPubkey: owner,
                              dateString: dateString, baseEventId: baseEventId, baseCreatedAt: baseCreatedAt,
                              entryUpdatedAt: entryUpdatedAt, now: now)
        context.insert(row)
        try context.save()
        return row
    }

    /// Every row for a day, live or not, for this owner.
    func rows(dateString: String) throws -> [OutboxEvent] {
        let owner = self.owner
        return try context.fetch(FetchDescriptor<OutboxEvent>(predicate: #Predicate {
            $0.ownerPubkey == owner && $0.dateString == dateString
        }))
    }

    /// The newest live row for a day: the only one that's ever sent, and the
    /// only one whose acknowledgements give the day its state.
    func liveRow(dateString: String) throws -> OutboxEvent? {
        try rows(dateString: dateString).filter(\.isLive).max { $0.eventCreatedAt < $1.eventCreatedAt }
    }

    /// Event ids this device signed for a day (any row, superseded or not).
    func ownEventIds(dateString: String) throws -> Set<String> {
        Set(try rows(dateString: dateString).map(\.eventId))
    }

    /// Live rows for this owner that still need acknowledgements and are due.
    func due(write: [URL]?, now: Date = .now) throws -> [OutboxEvent] {
        let owner = self.owner
        let live = try context.fetch(FetchDescriptor<OutboxEvent>(predicate: #Predicate {
            $0.ownerPubkey == owner && !$0.superseded && !$0.supersededByRemote
        }, sortBy: [SortDescriptor(\.eventCreatedAt)]))
        return live.filter {
            DeliveryRules.state(acked: $0.ackedRelays, write: write) != .synced && ($0.nextAttemptAt ?? .distantPast) <= now
        }
    }

    /// The earliest time a live, unsynced row of this owner is due again
    /// after a backoff, or nil when none is waiting on one.
    func nextAttempt(write: [URL]?) throws -> Date? {
        let owner = self.owner
        let live = try context.fetch(FetchDescriptor<OutboxEvent>(predicate: #Predicate {
            $0.ownerPubkey == owner && !$0.superseded && !$0.supersededByRemote
        }))
        return live.filter { DeliveryRules.state(acked: $0.ackedRelays, write: write) != .synced }
            .compactMap(\.nextAttemptAt).min()
    }

    /// Record one attempt's outcomes. Only `OK true` adds an acknowledgement.
    func record(_ outcomes: [URL: PublishOutcome], for row: OutboxEvent, write: [URL]?, now: Date = .now) throws {
        var acked = row.ackedRelays
        for (url, outcome) in outcomes where outcome == .accepted { acked.insert(url.absoluteString) }
        row.ackedRelays = acked
        row.attempts += 1
        if DeliveryRules.state(acked: acked, write: write) == .synced {
            row.nextAttemptAt = nil
        } else {
            row.nextAttemptAt = now.addingTimeInterval(DeliveryRules.backoff(afterAttempts: row.attempts))
        }
        try context.save()
    }

    /// Live rows for this owner still waiting on a re-check of write relays
    /// that didn't answer before their send.
    func awaitingRecheck() throws -> [OutboxEvent] {
        let owner = self.owner
        return try context.fetch(FetchDescriptor<OutboxEvent>(predicate: #Predicate {
            $0.ownerPubkey == owner && !$0.superseded && !$0.supersededByRemote && $0.recheckRelaysText != ""
        }))
    }

    /// The refetch before a send didn't resolve: defer quietly, with backoff.
    func deferRow(_ row: OutboxEvent, now: Date = .now) throws {
        row.attempts += 1
        row.nextAttemptAt = now.addingTimeInterval(DeliveryRules.backoff(afterAttempts: row.attempts))
        try context.save()
    }

    /// A relay holds a version this row didn't base on: the row is never sent.
    func stopForRemote(_ row: OutboxEvent) throws {
        row.supersededByRemote = true
        try context.save()
    }

    /// The day's state, recomputed from stored rows (so it survives a relaunch).
    func state(dateString: String, write: [URL]?) throws -> DeliveryRules.State {
        guard let row = try liveRow(dateString: dateString) else { return .localOnly }
        return DeliveryRules.state(acked: row.ackedRelays, write: write)
    }
}
