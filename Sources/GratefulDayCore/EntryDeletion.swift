import Foundation
import NostrCore

/// NIP-09 deletion of a daily entry (spec §1.7; web `useDeleteGratitudeEntry.ts`).
public enum EntryDeletion {
    public static func address(pubkey: String, dateString: String) -> String {
        "\(DailyEntry.kind):\(pubkey):\(dateString)"
    }

    /// The identical kind 5 shape web publishes.
    public static func template(pubkey: String, dateString: String, eventId: String) -> UnsignedEvent {
        UnsignedEvent(kind: 5, tags: [
            ["a", address(pubkey: pubkey, dateString: dateString)],
            ["e", eventId],
            ["k", String(DailyEntry.kind)],
        ], content: "Deleted gratitude entry")
    }

    /// Address → latest deletion time, from the owner's own kind 5 events.
    /// Only `a` coordinates of the owner's 36669 entries count (matches web PR #40).
    public static func tombstones(from events: [NostrEvent], owner pubkey: String) -> [String: Int] {
        let prefix = "\(DailyEntry.kind):\(pubkey):"
        var out: [String: Int] = [:]
        for e in events where e.kind == 5 && e.pubkey == pubkey {
            for tag in e.tags where tag.count >= 2 && tag[0] == "a" && tag[1].hasPrefix(prefix) && tag[1].count > prefix.count {
                out[tag[1]] = max(out[tag[1]] ?? 0, e.createdAt)
            }
        }
        return out
    }

    /// A version is deleted when its `created_at` is at or before the deletion.
    public static func isDeleted(_ event: NostrEvent, tombstones: [String: Int]) -> Bool {
        guard let d = event.tagValue("d"), let at = tombstones[address(pubkey: event.pubkey, dateString: d)] else { return false }
        return event.createdAt <= at
    }
}
