import Foundation
import SwiftData

/// Where an entry stands relative to Nostr. Only `localOnly` exists until M5.
enum SyncState: String, Codable, Sendable {
    case localOnly
}

/// One reflection day. One row per local date (Phase 0 day key, `d` tag).
///
/// The day's identity (`dateString`, `dayOfYear`, `publishedAt`, `timeZoneID`)
/// is stored as computed when the entry was first written, so the entry can
/// later become a kind 36669 event with exactly the same date tags even if
/// the device's time zone has changed since.
///
/// The fields M5/M6 need (`syncStateRaw`, `deletedAt`, `remote*`) exist now,
/// all optional or defaulted, so adding sync needs no destructive migration.
@Model
final class JournalEntry {
    /// `YYYY-MM-DD` local date: the 36669 `d` tag.
    @Attribute(.unique) var dateString: String
    /// The 36669 `day` tag (1–366).
    var dayOfYear: Int
    /// The 36669 `published_at` tag: Unix seconds of local midnight.
    var publishedAt: Int
    /// Time zone the day was computed in.
    var timeZoneID: String
    /// Canonical notes text: notes separated by a blank line (`EntryNotes`).
    var notesText: String
    /// Private by default. No toggle in guest mode: nothing is published.
    var isPrivate: Bool = true
    var createdAt: Date
    var updatedAt: Date
    var syncStateRaw: String = SyncState.localOnly.rawValue
    /// Deletion tombstone (M3/M5). Nil while the entry exists.
    var deletedAt: Date?
    /// The 36669 event this entry last matched on relays (M5).
    var remoteEventID: String?
    var remoteCreatedAt: Int?

    init(dateString: String, dayOfYear: Int, publishedAt: Int, timeZoneID: String,
         notesText: String, now: Date) {
        self.dateString = dateString
        self.dayOfYear = dayOfYear
        self.publishedAt = publishedAt
        self.timeZoneID = timeZoneID
        self.notesText = notesText
        self.createdAt = now
        self.updatedAt = now
    }

    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}
