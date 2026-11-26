import Foundation
import SwiftData
import NostrCore

/// M6 (live): the earlier-versions archive also keeps, for a relay version,
/// whether it was private and its created_at, so the conflict screen can
/// apply "private wins" and base the kept day on that version (Chief P31).
/// Local only. Models are the live ones behind the typealiases.
enum JournalSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        [JournalEntry.self, AcknowledgedMilestone.self, JournalFlag.self, AccountMarker.self, EarlierVersion.self, OutboxEvent.self]
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
        /// Spec A: the person saw the disclosure before the first publish.
        /// Nothing is published until this is set (the sheet lands with M6).
        static let publishDisclosureAccepted = "publishDisclosureAccepted"
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
        /// Whether this text was private. Archives written before V7 read as
        /// private, the stricter choice (Chief P31).
        var isPrivate: Bool = true
        /// The relay event's created_at, when the text came from one (V7).
        var eventCreatedAt: Int?

        init(ownerPubkey: String?, dateString: String, notesText: String, reason: EarlierVersionReason,
             eventId: String?, surfaced: Bool, isPrivate: Bool = true, eventCreatedAt: Int? = nil, now: Date) {
            self.id = UUID()
            self.ownerPubkey = ownerPubkey
            self.dateString = dateString
            self.notesText = notesText
            self.reasonRaw = reason.rawValue
            self.eventId = eventId
            self.surfaced = surfaced
            self.isPrivate = isPrivate
            self.eventCreatedAt = eventCreatedAt
            self.createdAt = now
        }

        var reason: EarlierVersionReason { EarlierVersionReason(rawValue: reasonRaw) ?? .replacedByRemote }
    }

    /// One signed event waiting to reach relays: local only, never a copy of
    /// anything on a relay, stored in the journal store (backup-excluded,
    /// file-protected) and removed with it (M5b plan r2 (b)).
    ///
    /// Retries resend `eventJSON` byte for byte: a delivery failure never
    /// re-signs. Only a new local edit signs a new event, which supersedes
    /// every older row for that day.
    @Model final class OutboxEvent {
        @Attribute(.unique) var eventId: String
        var ownerPubkey: String
        var dateString: String
        var kind: Int
        /// The event exactly as signed.
        var eventJSON: String
        var eventCreatedAt: Int
        /// The relay version this edit started from; nil = no remote copy
        /// existed, as established under interop §0.1 (r2.1 item 1).
        var baseEventId: String?
        var baseCreatedAt: Int?
        /// Relay URLs that answered `OK true` for this id, newline-separated.
        var ackedRelaysText: String = ""
        /// A newer local edit replaced this row: never sent again.
        var superseded: Bool = false
        /// A relay version this row didn't base on was found: never sent; the
        /// day is an M6 conflict (r2.1 item 2).
        var supersededByRemote: Bool = false
        var attempts: Int = 0
        var nextAttemptAt: Date?
        var queuedAt: Date
        /// The entry's `updatedAt` this event was signed from: a later local
        /// edit (a different value) needs a new event.
        var entryUpdatedAt: Date?
        /// Write relays that didn't answer the pre-send refetch: re-queried on
        /// later passes for a version this row didn't base on (§0.1 item 3),
        /// newline-separated.
        var recheckRelaysText: String = ""

        init(event: NostrEvent, json: String, ownerPubkey: String, dateString: String,
             baseEventId: String?, baseCreatedAt: Int?, entryUpdatedAt: Date? = nil, now: Date) {
            self.eventId = event.id
            self.ownerPubkey = ownerPubkey
            self.dateString = dateString
            self.kind = event.kind
            self.eventJSON = json
            self.eventCreatedAt = event.createdAt
            self.baseEventId = baseEventId
            self.baseCreatedAt = baseCreatedAt
            self.entryUpdatedAt = entryUpdatedAt
            self.queuedAt = now
        }

        var ackedRelays: Set<String> {
            get { Set(ackedRelaysText.split(separator: "\n").map(String.init)) }
            set { ackedRelaysText = newValue.sorted().joined(separator: "\n") }
        }
        var recheckRelays: [URL] {
            get { recheckRelaysText.split(separator: "\n").compactMap { URL(string: String($0)) } }
            set { recheckRelaysText = newValue.map(\.absoluteString).sorted().joined(separator: "\n") }
        }
        var isLive: Bool { !superseded && !supersededByRemote }
    }
}
