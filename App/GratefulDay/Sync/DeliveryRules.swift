import Foundation
import NostrCore
import GratefulDayCore

/// The publish rules Seth approved: interop r5.1 §0.1 (events 5c471a7e,
/// 3f1c5fd4), M5b plan r2 and r2.1, Audit A2. Pure, so every rule has a
/// named test.
enum DeliveryRules {
    /// How many distinct write relays must answer (for "no copy") or
    /// acknowledge (for "synced"). Two or more write relays: 2. Fewer: all of
    /// them (Seth option A). None, or an unknown write set: never (nil).
    static func required(write: [URL]?) -> Int? {
        guard let write, !write.isEmpty else { return nil }
        return min(2, Set(write).count)
    }

    /// The day's delivery state from the live row's acknowledgements.
    enum State: Equatable {
        /// Not signed yet, or nothing acknowledged.
        case localOnly
        /// Acknowledged, but by fewer relays than required.
        case sent
        case synced
    }

    static func state(acked: Set<String>, write: [URL]?) -> State {
        guard !acked.isEmpty else { return .localOnly }
        // Count only acknowledgements from the current write set when it's
        // known; an unknown set can't confirm anything.
        guard let need = required(write: write), let write else { return .sent }
        let counted = Set(write.map(\.absoluteString)).intersection(acked).count
        return counted >= need ? .synced : .sent
    }

    /// The result of the refetch before a send (r2.1 item 2).
    enum Check: Equatable {
        /// Send it.
        case clear
        /// Not enough write relays answered to know: defer quietly.
        case unresolved
        /// A relay holds a version this row didn't base on, nor one this
        /// device published: never send; the day is an M6 conflict.
        case unbasedRemote(NostrEvent)
    }

    /// The newest change on relays that this row didn't base on, if any
    /// (r2.1 items 2 and 3, narrowed by Chief P30):
    /// - a 36669 for the day that is neither the base nor this device's
    ///   own, and is ordered after the base (`created_at`, then the lower
    ///   id wins a tie). A version at or before the base is an ancestor the
    ///   base already replaced, e.g. a copy left on a read-only relay (H1).
    ///   With no base, every version counts.
    /// - for a 36669 row only (`checkDeletions`), a kind 5 for the day's
    ///   address that isn't this device's own and is newer than the base: a
    ///   deletion the pending edit never saw (L1).
    static func unbased(day dateString: String, owner: String, baseEventId: String?, baseCreatedAt: Int?,
                        ownEventIds: Set<String>, events: [NostrEvent], checkDeletions: Bool) -> NostrEvent? {
        func afterBase(_ e: NostrEvent) -> Bool {
            guard let at = baseCreatedAt else { return true }
            if e.createdAt != at { return e.createdAt > at }
            guard let id = baseEventId else { return true }
            return e.id < id
        }
        let versions = events.filter {
            DailyEntry.isValid($0, owner: owner) && $0.tagValue("d") == dateString
                && $0.id != baseEventId && !ownEventIds.contains($0.id) && afterBase($0)
        }
        let address = EntryDeletion.address(pubkey: owner, dateString: dateString)
        let deletions = !checkDeletions ? [] : events.filter { e in
            e.kind == 5 && e.pubkey == owner && e.isValid && !ownEventIds.contains(e.id)
                && e.tags.contains { $0.count >= 2 && $0[0] == "a" && $0[1] == address }
                && (baseCreatedAt.map { e.createdAt > $0 } ?? true)
        }
        return (versions + deletions).max { ($0.createdAt, $1.id) < ($1.createdAt, $0.id) }
    }

    /// `fetched` is a query for this day's 36669s and kind 5s on read ∪
    /// write relays. `ownEventIds` are this device's outbox ids for the day.
    static func preSendCheck(day dateString: String, owner: String, baseEventId: String?, baseCreatedAt: Int? = nil,
                             ownEventIds: Set<String>, fetched: FetchResult, write: [URL]?,
                             checkDeletions: Bool = true) -> Check {
        // A change found anywhere, read relay or write relay, counts.
        if let unbased = unbased(day: dateString, owner: owner, baseEventId: baseEventId, baseCreatedAt: baseCreatedAt,
                                 ownEventIds: ownEventIds, events: fetched.events, checkDeletions: checkDeletions) {
            return .unbasedRemote(unbased)
        }
        // Only write relays that answered count toward knowing; an
        // `.unresolved` (possibly capped) relay never does.
        guard let need = required(write: write), let write else { return .unresolved }
        let answered = Set(write).filter { fetched.outcomes[$0] == .answered }.count
        return answered >= need ? .clear : .unresolved
    }

    /// Backoff after a failed attempt: 30 s, 2 min, 10 min, then hourly.
    static func backoff(afterAttempts n: Int) -> TimeInterval {
        switch n {
        case ...1: return 30
        case 2: return 120
        case 3: return 600
        default: return 3600
        }
    }
}
