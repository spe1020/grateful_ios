import Foundation
import SwiftData

/// M5b-1 (FROZEN, as shipped in #14 at 53b51e0): adds the local "earlier
/// versions" archive (interop §0.1 5a, §4.4; Chief P22). Never edit; add a
/// new version instead.
enum JournalSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, AcknowledgedMilestone.self, JournalFlag.self, AccountMarker.self, EarlierVersion.self]
    }

    /// One reflection day for one owner. `ownerPubkey == nil` is a guest
    /// entry. `entryKey` ("<owner or guest>|<date>") is the unique key;
    /// `#Unique` needs iOS 18 and the app targets 17.
    ///
    /// The day's identity (`dateString`, `dayOfYear`, `publishedAt`,
    /// `timeZoneID`) is stored as first computed, so the entry becomes a
    /// kind 36669 event with the same date tags even after a time-zone change.
    @Model final class JournalEntry {
        var dateString: String
        var dayOfYear: Int
        var publishedAt: Int
        var timeZoneID: String
        /// Canonical notes text (`EntryNotes`).
        var notesText: String
        var isPrivate: Bool = true
        var createdAt: Date
        var updatedAt: Date
        var syncStateRaw: String = SyncState.localOnly.rawValue
        /// Deletion tombstone. Nil while the entry exists.
        var deletedAt: Date?
        var remoteEventID: String?
        var remoteCreatedAt: Int?
        /// The account this entry belongs to; nil for a guest entry.
        var ownerPubkey: String?
        /// Unique: `key(owner:dateString:)`. Optional only so the V3→V4
        /// stage can add it; always set for rows written by M5a or later.
        @Attribute(.unique) var entryKey: String?

        init(dateString: String, dayOfYear: Int, publishedAt: Int, timeZoneID: String,
             notesText: String, now: Date, ownerPubkey: String? = nil) {
            self.dateString = dateString
            self.dayOfYear = dayOfYear
            self.publishedAt = publishedAt
            self.timeZoneID = timeZoneID
            self.notesText = notesText
            self.createdAt = now
            self.updatedAt = now
            self.ownerPubkey = ownerPubkey
            self.entryKey = Self.key(owner: ownerPubkey, dateString: dateString)
        }

        static func key(owner: String?, dateString: String) -> String {
            "\(owner ?? "guest")|\(dateString)"
        }

        var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
    }

    @Model final class AcknowledgedMilestone {
        @Attribute(.unique) var total: Int
        var acknowledgedAt: Date
        init(total: Int, acknowledgedAt: Date) { self.total = total; self.acknowledgedAt = acknowledgedAt }
    }

    /// A one-time personal app fact (it implies journal activity), kept in
    /// the journal store rather than UserDefaults, which is backed up.
    @Model final class JournalFlag {
        @Attribute(.unique) var name: String
        var setAt: Date
        init(name: String, setAt: Date) { self.name = name; self.setAt = setAt }
        static let reminderOfferShown = "reminderOfferShown"
        /// Prep F3: a restore found no backup yet; Today shows a quiet line.
        static let restorePending = "restorePending"
    }

    /// Which account this install is connected to (non-secret; design §3).
    /// At most one row. Absent = never connected.
    @Model final class AccountMarker {
        @Attribute(.unique) var slot: Int = 0
        var pubkey: String
        var stateRaw: String
        var updatedAt: Date
        init(pubkey: String, state: AccountMarkerState, now: Date) {
            self.pubkey = pubkey; self.stateRaw = state.rawValue; self.updatedAt = now
        }
        var state: AccountMarkerState { AccountMarkerState(rawValue: stateRaw) ?? .connected }
    }

    /// A version of a day's text kept aside on this iPhone: never sent to a
    /// relay, stored in the journal store (backup-excluded, file-protected),
    /// owned like entries, removed by "Remove account and local data"
    /// (Audit's rules for M5b-1).
    @Model final class EarlierVersion {
        @Attribute(.unique) var id: UUID
        var ownerPubkey: String?
        var dateString: String
        var notesText: String
        var reasonRaw: String
        /// The relay event this text came from, if any.
        var eventId: String?
        /// Shown to the person (a quiet line plus the Set aside list), because
        /// some of their notes would otherwise be lost (P22).
        var surfaced: Bool
        var dismissed: Bool = false
        var createdAt: Date

        init(ownerPubkey: String?, dateString: String, notesText: String, reason: EarlierVersionReason,
             eventId: String?, surfaced: Bool, now: Date) {
            self.id = UUID()
            self.ownerPubkey = ownerPubkey
            self.dateString = dateString
            self.notesText = notesText
            self.reasonRaw = reason.rawValue
            self.eventId = eventId
            self.surfaced = surfaced
            self.createdAt = now
        }

        var reason: EarlierVersionReason { EarlierVersionReason(rawValue: reasonRaw) ?? .replacedByRemote }
    }
}
