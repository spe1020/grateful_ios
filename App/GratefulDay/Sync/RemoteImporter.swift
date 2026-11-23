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
        let outbox = Outbox(context: context, owner: owner)
        for (dateString, remote) in days.sorted(by: { $0.key < $1.key }) {
            let row = try ownerRow(dateString)
            // A version this device signed (M5b-2): its state comes from the
            // outbox's acknowledgements, never from seeing it on one relay.
            if case .entry(_, _, let eventId, _, _) = remote,
               try outbox.ownEventIds(dateString: dateString).contains(eventId) { continue }
            // A copy older than the version this row already has (a lagging
            // relay answered a partial read) is never taken or archived.
            if let row, let base = row.remoteCreatedAt, let at = remote.createdAt, at < base { continue }
            switch remote {
            case .blocked(let eventId, let createdAt):
                if let row, hasPendingEdits(row) {
                    // Audit L2 / Chief P27: unsent local edits meeting a version
                    // we can't read never look clean. The day becomes a conflict,
                    // keeps its pending state and its base, and the local text is
                    // archived first (once per remote version, Audit M1).
                    if !hasArchive(dateString, eventId: eventId, reason: .localInConflict) {
                        archive(row.notesText, dateString: dateString, reason: .localInConflict,
                                eventId: eventId, surfaced: false, isPrivate: row.isPrivate)
                        summary.conflicts += 1
                    }
                    row.syncStateRaw = SyncState.conflict.rawValue
                } else if let row {
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

            case .deleted(let at, let by):
                // This device's own delivered deletion (its id is in our
                // outbox) is nothing new: a revive of that day is pending, not
                // a conflict. Another device's deletion, even signed with the
                // same key, still applies (P30 M1).
                if !by.isEmpty, !by.isDisjoint(with: try outbox.ownEventIds(dateString: dateString)) { continue }
                guard let row, row.deletedAt == nil else { continue }
                // §7 Keep this iPhone's: the row is based on this deletion
                // already, so meeting it again is nothing new.
                if let base = row.remoteEventID, by.contains(base) { continue }
                retireBlockedMarkers(dateString)
                if hasPendingEdits(row) {
                    // A remote delete against unsent local edits is a conflict (§4.2).
                    row.syncStateRaw = SyncState.conflict.rawValue
                    retireOpenConflictCopies(dateString)
                    markDeletedInAccount(dateString, at: at, by: by, row: row)
                    summary.conflicts += 1
                    continue
                }
                if !row.notesText.isEmpty {
                    archive(row.notesText, dateString: dateString, reason: .replacedByRemote,
                            eventId: row.remoteEventID, surfaced: false, isPrivate: row.isPrivate)
                }
                row.notesText = ""
                row.deletedAt = Date(timeIntervalSince1970: TimeInterval(at))
                // The row is now based on the deletion: a revive is signed
                // after it, and the pre-send check doesn't count it (P30 L1).
                row.remoteCreatedAt = at
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
                retireBlockedMarkers(dateString)
                // A readable version is newer than any deletion already met.
                retire(dateString, .deletedInAccountInConflict)
                if hasPendingEdits(row) {
                    if row.notesText == text {
                        row.remoteEventID = eventId
                        row.remoteCreatedAt = createdAt
                        row.syncStateRaw = SyncState.synced.rawValue
                        continue
                    }
                    // Audit M1: the row keeps its base (M5b-2's 5a check needs
                    // it), so the same relay version is met again on every
                    // pass. Archive it only once.
                    row.syncStateRaw = SyncState.conflict.rawValue
                    if hasArchive(dateString, eventId: eventId, reason: .remoteInConflict) { continue }
                    archive(text, dateString: dateString, reason: .remoteInConflict, eventId: eventId, surfaced: true,
                            isPrivate: isPrivate, eventCreatedAt: createdAt)
                    summary.conflicts += 1
                    summary.surfaced += 1
                    continue
                }
                // No pending edits: take the relay version, archiving first.
                if !row.notesText.isEmpty, row.notesText != text {
                    let lost = Self.losesNotes(old: row.notesText, new: text)
                    archive(row.notesText, dateString: dateString, reason: .replacedByRemote,
                            eventId: row.remoteEventID, surfaced: lost, isPrivate: row.isPrivate)
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

    /// A relay holds a version a queued event of this device didn't base on
    /// (r2.1 items 2 and 3): the day becomes a conflict. The local text
    /// stays; a readable relay text is archived (once) and surfaced, so both
    /// are kept for M6.
    func conflict(dateString: String, remote: RemoteDay?) throws {
        guard let row = try ownerRow(dateString) else { return }
        row.syncStateRaw = SyncState.conflict.rawValue
        if case .entry(let text, let isPrivate, let eventId, let createdAt, _) = remote,
           !hasArchive(dateString, eventId: eventId, reason: .remoteInConflict) {
            archive(text, dateString: dateString, reason: .remoteInConflict, eventId: eventId, surfaced: true,
                    isPrivate: isPrivate, eventCreatedAt: createdAt)
        }
        switch remote {
        case .entry:
            retireBlockedMarkers(dateString)
            retire(dateString, .deletedInAccountInConflict)
        case .deleted(let at, let by):
            retireOpenConflictCopies(dateString)
            retireBlockedMarkers(dateString)
            markDeletedInAccount(dateString, at: at, by: by, row: row)
        case .blocked(let eventId, _):
            // The account's newest version can't be read: the day is listed
            // under "Can't compare these yet", never hidden (acceptance 6).
            if !hasArchive(dateString, eventId: eventId, reason: .localInConflict) {
                archive(row.notesText, dateString: dateString, reason: .localInConflict,
                        eventId: eventId, surfaced: false, isPrivate: row.isPrivate)
            }
        case nil:
            break
        }
        try context.save()
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

    /// This account already archived this relay version for this day.
    private func hasArchive(_ dateString: String, eventId: String, reason: EarlierVersionReason) -> Bool {
        let o: String? = owner, raw = reason.rawValue, id: String? = eventId
        let d = FetchDescriptor<EarlierVersion>(predicate: #Predicate {
            $0.ownerPubkey == o && $0.dateString == dateString && $0.eventId == id && $0.reasonRaw == raw
        })
        return ((try? context.fetchCount(d)) ?? 0) > 0
    }

    /// The account now holds a deletion for this day, so any open copy of
    /// its earlier text is no longer the account's version. It stays in the
    /// store, hidden, and is never offered on the conflict screen (P34 M1).
    private func retireOpenConflictCopies(_ dateString: String) {
        retire(dateString, .remoteInConflict)
    }

    private func retire(_ dateString: String, _ reason: EarlierVersionReason) {
        let o: String? = owner, raw = reason.rawValue
        let d = FetchDescriptor<EarlierVersion>(predicate: #Predicate {
            $0.ownerPubkey == o && $0.dateString == dateString && $0.reasonRaw == raw && !$0.dismissed
        })
        for copy in (try? context.fetch(d)) ?? [] { copy.dismissed = true }
    }

    /// §7: the account deleted a day this iPhone has unsent writing for.
    /// A marker (once per deletion time) lets the conflict screen list it;
    /// the row keeps its text and its base.
    private func markDeletedInAccount(_ dateString: String, at: Int, by: Set<String>, row: JournalEntry) {
        let o: String? = owner, raw = EarlierVersionReason.deletedInAccountInConflict.rawValue, when: Int? = at
        let d = FetchDescriptor<EarlierVersion>(predicate: #Predicate {
            $0.ownerPubkey == o && $0.dateString == dateString && $0.reasonRaw == raw && $0.eventCreatedAt == when
        })
        if ((try? context.fetchCount(d)) ?? 0) > 0 { return }
        archive("", dateString: dateString, reason: .deletedInAccountInConflict, eventId: by.sorted().first,
                surfaced: false, isPrivate: row.isPrivate, eventCreatedAt: at)
    }

    /// The account's version can be read now, or the account deleted the
    /// day: a marker saying its text couldn't be read no longer describes
    /// it. It stays in the store, hidden, so the day leaves "Can't compare
    /// these yet" (Audit #16 L2; Prep §10).
    private func retireBlockedMarkers(_ dateString: String) {
        let o: String? = owner, raw = EarlierVersionReason.localInConflict.rawValue
        let d = FetchDescriptor<EarlierVersion>(predicate: #Predicate {
            $0.ownerPubkey == o && $0.dateString == dateString && $0.reasonRaw == raw && !$0.dismissed
        })
        for marker in (try? context.fetch(d)) ?? [] { marker.dismissed = true }
    }

    private func archive(_ text: String, dateString: String, reason: EarlierVersionReason, eventId: String?, surfaced: Bool,
                         isPrivate: Bool = true, eventCreatedAt: Int? = nil) {
        context.insert(EarlierVersion(ownerPubkey: owner, dateString: dateString, notesText: text,
                                      reason: reason, eventId: eventId, surfaced: surfaced,
                                      isPrivate: isPrivate, eventCreatedAt: eventCreatedAt, now: now()))
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

extension RemoteDay {
    var createdAt: Int? {
        switch self {
        case .entry(_, _, _, let at, _), .blocked(_, let at): return at
        case .deleted(let at, _): return at
        }
    }
}
