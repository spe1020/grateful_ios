import Foundation
import SwiftData
import GratefulDayCore

/// Spec B step 3 (M5b plan §4.1): days written here without an account
/// (guest rows) are sorted against the account's days after a complete read
/// and after spec A was accepted, before anything is published.
///
/// - Only here: the guest row becomes the account's, to be published.
/// - Both, same text: nothing to do (the guest copy is dropped).
/// - Both, different text: a conflict for the M6 screen, both texts kept.
/// - The account deleted the day: a §7 conflict.
/// - The account's text can't be read: blocked, listed apart (§5).
///
/// Every word stays on a row or in an archive copy. Guest tombstones (days
/// deleted here before connecting) were never published and are left alone.
@MainActor
struct FirstConnectSort {
    let context: ModelContext
    let owner: String
    var now: () -> Date = { .now }

    struct Summary: Equatable { var adopted = 0, same = 0, conflicts = 0 }

    private func ownerRow(_ dateString: String) throws -> JournalEntry? {
        let key: String? = JournalEntry.key(owner: owner, dateString: dateString)
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    private func guestRows() throws -> [JournalEntry] {
        try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.ownerPubkey == nil && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.dateString)]))
            .filter { !EntryNotes.split($0.notesText).isEmpty }
    }

    @discardableResult
    func run() throws -> Summary {
        var summary = Summary()
        for guest in try guestRows() {
            let text = guest.notesText
            guard let mine = try ownerRow(guest.dateString) else {
                // Only here: it becomes this account's and is published next.
                guest.ownerPubkey = owner
                guest.entryKey = JournalEntry.key(owner: owner, dateString: guest.dateString)
                guest.syncStateRaw = SyncState.localOnly.rawValue
                guest.remoteEventID = nil
                guest.remoteCreatedAt = nil
                summary.adopted += 1
                continue
            }
            switch mine.syncState {
            case .synced where mine.deletedAt == nil:
                if EntryNotes.split(mine.notesText) == EntryNotes.split(text) {
                    summary.same += 1
                } else {
                    // The account's version goes aside as the conflict copy;
                    // the row holds this iPhone's text. The row's base is
                    // cleared so the copy isn't taken for a resolved one.
                    archive(mine.notesText, mine, reason: .remoteInConflict, isPrivate: mine.isPrivate)
                    mine.notesText = text
                    mine.isPrivate = guest.isPrivate
                    mine.remoteEventID = nil
                    mine.remoteCreatedAt = nil
                    mine.syncStateRaw = SyncState.conflict.rawValue
                    mine.updatedAt = now()
                    summary.conflicts += 1
                }
            case .synced:
                // §7: the account deleted this day; this iPhone has writing.
                archive("", mine, reason: .deletedInAccountInConflict, isPrivate: guest.isPrivate)
                mine.notesText = text
                mine.isPrivate = guest.isPrivate
                mine.deletedAt = nil
                mine.remoteCreatedAt = nil
                mine.syncStateRaw = SyncState.conflict.rawValue
                mine.updatedAt = now()
                summary.conflicts += 1
            case .blocked:
                // §5: the account's text can't be read. Nothing is published.
                let joined = EntryNotes.join(EntryNotes.split(mine.notesText) + EntryNotes.split(text))
                context.insert(EarlierVersion(ownerPubkey: owner, dateString: mine.dateString, notesText: joined,
                                              reason: .localInConflict, eventId: mine.remoteEventID, surfaced: false,
                                              isPrivate: guest.isPrivate, now: now()))
                mine.notesText = joined
                mine.syncStateRaw = SyncState.conflict.rawValue
                mine.updatedAt = now()
                summary.conflicts += 1
            case .localOnly, .conflict:
                // Already this account's, with writing of its own: keep both.
                if EntryNotes.split(mine.notesText) != EntryNotes.split(text) {
                    let notes = EntryNotes.split(mine.notesText)
                    mine.notesText = EntryNotes.join(notes + EntryNotes.split(text).filter { !notes.contains($0) })
                    mine.deletedAt = nil
                    mine.updatedAt = now()
                }
                summary.same += 1
            }
            context.delete(guest)
        }
        try context.save()
        return summary
    }

    private func archive(_ text: String, _ row: JournalEntry, reason: EarlierVersionReason, isPrivate: Bool) {
        context.insert(EarlierVersion(ownerPubkey: owner, dateString: row.dateString, notesText: text,
                                      reason: reason, eventId: row.remoteEventID, surfaced: reason == .remoteInConflict,
                                      isPrivate: isPrivate, eventCreatedAt: row.remoteCreatedAt, now: now()))
    }
}
