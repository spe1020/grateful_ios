import Foundation
import SwiftData
import GratefulDayCore
import NostrCore

/// Applies fetched relay days to the journal (M5b-1: read only, nothing is
/// published). Rules (interop r5.1 §0.1 5a, §4; plan r2.1; Chief P17, P22):
///
/// - Writes only the connected account's own rows (`ownerPubkey == owner`).
///   Guest rows and other accounts' rows are never touched.
/// - Takes a relay version only when the row has **no pending local edits**,
///   and archives the replaced local text first. The archive is surfaced when
///   any note of the replaced text is missing from the incoming version.
/// - A row with pending edits that meets a relay version it didn't base on
///   becomes a conflict: local text stays, the relay text is archived.
/// - An unreadable relay version blocks the day; never empty, never written over.
/// - A covering kind 5 tombstones the row (local text archived first).
@MainActor
struct RemoteImporter {
    let context: ModelContext
    let owner: String
    var now: () -> Date = { .now }

    struct Summary: Equatable {
        var imported = 0, replaced = 0, conflicts = 0, blocked = 0, deleted = 0, surfaced = 0
    }

    private func ownerRow(_ dateString: String) throws -> JournalEntry? {
        let key: String? = JournalEntry.key(owner: owner, dateString: dateString)
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    @discardableResult
    func apply(_ days: [String: RemoteDay], zone: TimeZone = .current) throws -> Summary {
        var summary = Summary()
        for (dateString, remote) in days.sorted(by: { $0.key < $1.key }) {
            let row = try ownerRow(dateString)
            switch remote {
            case .blocked(let eventId, let createdAt):
                if let row {
                    // Keep the local text; just mark the day unreadable remotely.
                    row.syncStateRaw = SyncState.blocked.rawValue
                    row.remoteEventID = eventId
                    row.remoteCreatedAt = createdAt
                } else {
                    let r = try newRow(dateString, text: "", zone: zone)
                    r.syncStateRaw = SyncState.blocked.rawValue
                    r.remoteEventID = eventId
                    r.remoteCreatedAt = createdAt
                }
                summary.blocked += 1

            case .deleted(let at):
                guard let row, row.deletedAt == nil else { continue }
                if hasPendingEdits(row) {
                    // A remote delete against unsent local edits is a conflict (§4.2).
                    row.syncStateRaw = SyncState.conflict.rawValue
                    summary.conflicts += 1
                    continue
                }
                if !row.notesText.isEmpty {
                    archive(row.notesText, dateString: dateString, reason: .replacedByRemote,
                            eventId: row.remoteEventID, surfaced: false)
                }
                row.notesText = ""
                row.deletedAt = Date(timeIntervalSince1970: TimeInterval(at))
                row.syncStateRaw = SyncState.synced.rawValue
                summary.deleted += 1

            case .entry(let text, let isPrivate, let eventId, let createdAt, let event):
                guard let row else {
                    // Day identity comes from the event's own tags (interop §1.8:
                    // never recompute d or published_at).
                    let r = try newRow(dateString, text: text, zone: zone, event: event)
                    r.isPrivate = isPrivate
                    r.remoteEventID = eventId
                    r.remoteCreatedAt = createdAt
                    r.syncStateRaw = SyncState.synced.rawValue
                    summary.imported += 1
                    continue
                }
                if row.remoteEventID == eventId, row.syncState != .blocked { continue }   // already based on it
                if hasPendingEdits(row) {
                    if row.notesText == text {
                        row.remoteEventID = eventId
                        row.remoteCreatedAt = createdAt
                        row.syncStateRaw = SyncState.synced.rawValue
                        continue
                    }
                    archive(text, dateString: dateString, reason: .remoteInConflict, eventId: eventId, surfaced: true)
                    row.syncStateRaw = SyncState.conflict.rawValue
                    summary.conflicts += 1
                    summary.surfaced += 1
                    continue
                }
                // No pending edits: take the relay version, archiving first.
                if !row.notesText.isEmpty, row.notesText != text {
                    let lost = Self.losesNotes(old: row.notesText, new: text)
                    archive(row.notesText, dateString: dateString, reason: .replacedByRemote,
                            eventId: row.remoteEventID, surfaced: lost)
                    if lost { summary.surfaced += 1 }
                }
                row.notesText = text
                row.isPrivate = isPrivate
                row.deletedAt = nil
                row.remoteEventID = eventId
                row.remoteCreatedAt = createdAt
                row.syncStateRaw = SyncState.synced.rawValue
                row.updatedAt = now()
                summary.replaced += 1
            }
        }
        try context.save()
        return summary
    }

    /// A row has pending local edits when it isn't in step with a relay
    /// version: never published with text, or edited since its last sync.
    private func hasPendingEdits(_ row: JournalEntry) -> Bool {
        switch row.syncState {
        case .synced: return false
        case .blocked: return false
        case .conflict: return true
        case .localOnly: return !row.notesText.isEmpty || row.remoteEventID != nil
        }
    }

    /// P22: some note of the old text is missing from the new one (exact match).
    static func losesNotes(old: String, new: String) -> Bool {
        let incoming = Set(EntryNotes.split(new))
        return EntryNotes.split(old).contains { !incoming.contains($0) }
    }

    private func archive(_ text: String, dateString: String, reason: EarlierVersionReason, eventId: String?, surfaced: Bool) {
        context.insert(EarlierVersion(ownerPubkey: owner, dateString: dateString, notesText: text,
                                      reason: reason, eventId: eventId, surfaced: surfaced, now: now()))
    }

    private func newRow(_ dateString: String, text: String, zone: TimeZone, event: NostrEvent? = nil) throws -> JournalEntry {
        guard let day = TodayEditorModel.parse(dateString, timeZone: zone) else { throw RepositoryError.dayIsBlocked }
        let dayOfYear = event?.tagValue("day").flatMap(Int.init) ?? day.day.dayOfYear
        let publishedAt = event?.tagValue("published_at").flatMap(Int.init) ?? day.day.publishedAt
        let row = JournalEntry(dateString: dateString, dayOfYear: dayOfYear, publishedAt: publishedAt,
                               timeZoneID: zone.identifier, notesText: text, now: now(), ownerPubkey: owner)
        context.insert(row)
        return row
    }
}
