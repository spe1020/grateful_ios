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

    /// `fetched` is a query for this day's address on read ∪ write relays.
    /// `ownEventIds` are this device's outbox ids for the day.
    static func preSendCheck(day dateString: String, owner: String, baseEventId: String?,
                             ownEventIds: Set<String>, fetched: FetchResult, write: [URL]?) -> Check {
        let versions = fetched.events.filter {
            DailyEntry.isValid($0, owner: owner) && $0.tagValue("d") == dateString
        }
        // A version found anywhere, read relay or write relay, counts.
        if let unbased = versions
            .filter({ $0.id != baseEventId && !ownEventIds.contains($0.id) })
            .max(by: { ($0.createdAt, $1.id) < ($1.createdAt, $0.id) }) {
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
