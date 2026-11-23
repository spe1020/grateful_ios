import Foundation

enum AccountMarkerState: String, Codable, Sendable {
    case connected, signedOut
}

/// Where an entry stands relative to Nostr. Stored as a string, so new
/// values need no schema change.
enum SyncState: String, Codable, Sendable {
    /// Never published, or edited locally since the last synced version
    /// (a pending local edit when `remoteEventID` is set).
    case localOnly
    /// Matches the newest relay version (`remoteEventID`).
    case synced
    /// The newest relay version can't be decrypted or decoded: unknown,
    /// never shown as empty, never written over (interop §0, §4.1).
    case blocked
    /// A relay version this row didn't base on arrived while it had pending
    /// edits. Both texts are kept (the remote one in `EarlierVersion`);
    /// nothing is published until the person resolves it (M6).
    case conflict
}

/// Why an `EarlierVersion` was kept.
enum EarlierVersionReason: String, Codable, Sendable {
    /// Local text replaced by a newer relay version (archived first).
    case replacedByRemote
    /// A relay version kept aside because the local row had pending edits.
    case remoteInConflict
    /// Local text with pending edits, kept before a relay version that
    /// couldn't be read marked the day as a conflict (Chief P27). Not shown
    /// in Set aside; the row still holds the same text.
    case localInConflict
    /// M6: the text the person didn't keep when choosing between this
    /// iPhone's and the account's version. Shown in Set aside.
    case notKept
    /// Marker: the account deleted this day while this iPhone had unsent
    /// writing for it (Prep §7). `eventCreatedAt` is the deletion's time.
    /// Not shown in Set aside; the row still holds the text.
    case deletedInAccountInConflict
    /// Set aside (§7, Let it stay deleted): this iPhone's text for a day
    /// the account deleted.
    case deletedFromAccount
    /// Set aside (§9, Delete it everywhere): the account's text for a day
    /// deleted on this iPhone.
    case deletedHere

    /// Shown in Set aside (P22, M6).
    var isSetAside: Bool { [.replacedByRemote, .notKept, .deletedFromAccount, .deletedHere].contains(self) }
}
