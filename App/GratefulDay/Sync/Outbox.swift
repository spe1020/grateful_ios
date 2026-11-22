import Foundation
import SwiftData
import NostrCore

/// The local outbox of signed events (M5b plan r2 (b), r2.1). Rows are owned
/// like entries: only the connected account's rows are read or sent.
@MainActor
struct Outbox {
    let context: ModelContext
    let owner: String

    /// Queue a newly signed event for a day. Every older row for that day is
    /// marked superseded and never sent again, even if partly delivered.
    @discardableResult
    func enqueue(_ event: NostrEvent, dateString: String, baseEventId: String?, baseCreatedAt: Int?,
                 now: Date = .now) throws -> OutboxEvent {
        for row in try rows(dateString: dateString) where row.isLive { row.superseded = true }
        let data = try JSONEncoder().encode(event)
        let row = OutboxEvent(event: event, json: String(decoding: data, as: UTF8.self), ownerPubkey: owner,
                              dateString: dateString, baseEventId: baseEventId, baseCreatedAt: baseCreatedAt, now: now)
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
