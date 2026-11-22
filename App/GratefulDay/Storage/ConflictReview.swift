import Foundation
import SwiftData
import GratefulDayCore

/// M6: choosing between this iPhone's text and the account's for days in
/// conflict (Prep's "M6 conflict screen"; spec B §4; Chief P31). Local
/// only: applying a choice changes the journal and the outbox, and the
/// publish pass then sends what was kept, under the usual §0.1 rules.
///
/// Rules:
/// - Every word from both sides ends up on the day or in Set aside.
/// - Keep both: the account's notes, then this iPhone's, as separate notes.
///   The day is private if either text was.
/// - Keep one: the kept text keeps its own privacy; the other goes to Set
///   aside (`.notKept`).
/// - Blocked days (the account's text can't be read) offer no choice and
///   are never changed here.
@MainActor
struct ConflictReview {
    let context: ModelContext
    let owner: String
    var now: () -> Date = { .now }

    enum Choice: Equatable, CaseIterable { case keepBoth, keepThisIPhone, keepAccount }

    /// A day with a choice to make.
    struct Item: Equatable, Identifiable {
        var id: String { dateString }
        let dateString: String
        let accountText: String
        let accountIsPrivate: Bool
        let iPhoneText: String
        let iPhoneIsPrivate: Bool
        /// The conflict was found after this day was already saved to the
        /// account (the E6 re-check), not on connecting.
        let afterSaving: Bool
        /// Keep both would make a day private that one side had public.
        var keepBothBecomesPrivate: Bool { accountIsPrivate != iPhoneIsPrivate }
    }

    /// A day whose account text can't be opened, with writing here.
    struct Blocked: Equatable, Identifiable {
        var id: String { dateString }
        let dateString: String
        let iPhoneText: String
    }

    struct Days: Equatable {
        var items: [Item] = []
        var blocked: [Blocked] = []
        /// §6: the re-check heading only when every row came from it.
        var allAfterSaving: Bool { !items.isEmpty && items.allSatisfy(\.afterSaving) }
    }

    private func conflictRows() throws -> [JournalEntry] {
        let o: String? = owner, raw = SyncState.conflict.rawValue
        return try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.ownerPubkey == o && $0.syncStateRaw == raw },
            sortBy: [SortDescriptor(\.dateString)]))
    }

    /// The newest conflict archive for a day: the account's text
    /// (`.remoteInConflict`), or a marker that it couldn't be read
    /// (`.localInConflict`).
    private func latestArchive(_ dateString: String) throws -> EarlierVersion? {
        let o: String? = owner
        let remote = EarlierVersionReason.remoteInConflict.rawValue, local = EarlierVersionReason.localInConflict.rawValue
        return try context.fetch(FetchDescriptor<EarlierVersion>(
            predicate: #Predicate {
                $0.ownerPubkey == o && $0.dateString == dateString && ($0.reasonRaw == remote || $0.reasonRaw == local)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).first
    }

    private func wasSaved(_ dateString: String) throws -> Bool {
        try Outbox(context: context, owner: owner).rows(dateString: dateString)
            .contains { $0.kind == DailyEntry.kind && !$0.ackedRelays.isEmpty }
    }

    /// Days in conflict, sorted by date. A conflict with no account text on
    /// this iPhone (a deletion elsewhere) isn't listed: it has no copy yet,
    /// and it stays a conflict, so nothing is published for it.
    func load() throws -> Days {
        var days = Days()
        for row in try conflictRows() {
            guard let archive = try latestArchive(row.dateString) else { continue }
            if archive.reason == .localInConflict {
                days.blocked.append(Blocked(dateString: row.dateString, iPhoneText: row.notesText))
            } else {
                days.items.append(Item(dateString: row.dateString, accountText: archive.notesText,
                                       accountIsPrivate: archive.isPrivate, iPhoneText: row.notesText,
                                       iPhoneIsPrivate: row.isPrivate, afterSaving: try wasSaved(row.dateString)))
            }
        }
        return days
    }

    /// Apply a choice per day. Days not in `choices`, blocked days and days
    /// no longer in conflict are left alone.
    func apply(_ choices: [String: Choice]) throws {
        for row in try conflictRows() {
            guard let choice = choices[row.dateString], let archive = try latestArchive(row.dateString),
                  archive.reason == .remoteInConflict else { continue }
            let account = archive.notesText, iPhone = row.notesText
            switch choice {
            case .keepBoth:
                row.notesText = EntryNotes.join(EntryNotes.split(account) + EntryNotes.split(iPhone))
                row.isPrivate = archive.isPrivate || row.isPrivate
            case .keepThisIPhone:
                setAside(account, of: row, isPrivate: archive.isPrivate, eventId: archive.eventId)
            case .keepAccount:
                setAside(iPhone, of: row, isPrivate: row.isPrivate, eventId: nil)
                row.notesText = account
                row.isPrivate = archive.isPrivate
            }
            // The kept day is now based on the account's version, so the
            // pre-send check doesn't stop it again and it's signed after it.
            row.remoteEventID = archive.eventId
            if let at = archive.eventCreatedAt { row.remoteCreatedAt = max(row.remoteCreatedAt ?? at, at) }
            row.deletedAt = nil
            row.updatedAt = now()
            // Keep the account's text unchanged: nothing to publish.
            let unchanged = choice == .keepAccount && archive.eventId != nil
            row.syncStateRaw = (unchanged ? SyncState.synced : SyncState.localOnly).rawValue
            // Queued events from before the choice are never sent.
            for queued in try Outbox(context: context, owner: owner).rows(dateString: row.dateString) where queued.isLive {
                queued.superseded = true
            }
            // The conflict archive is resolved; it stays, hidden, as history.
            archive.dismissed = true
        }
        try context.save()
    }

    struct KeptBoth: Equatable {
        let dates: [String]
        let madePrivate: Bool
    }

    /// §4: Keep both for every day with a choice. Blocked days are untouched.
    func keepBothForAll() throws -> KeptBoth {
        let items = try load().items
        try apply(Dictionary(uniqueKeysWithValues: items.map { ($0.dateString, Choice.keepBoth) }))
        return KeptBoth(dates: items.map(\.dateString), madePrivate: items.contains(where: \.keepBothBecomesPrivate))
    }

    private func setAside(_ text: String, of row: JournalEntry, isPrivate: Bool, eventId: String?) {
        guard !EntryNotes.split(text).isEmpty else { return }
        context.insert(EarlierVersion(ownerPubkey: owner, dateString: row.dateString, notesText: text,
                                      reason: .notKept, eventId: eventId, surfaced: true,
                                      isPrivate: isPrivate, now: now()))
    }
}

extension ConflictReview {
    private static let noticePrefix = "keptBothNotice|"

    /// The Today line after Keep both for all, kept in the journal store
    /// (backup-excluded, like other journal facts) until dismissed.
    func saveKeptBothNotice(_ kept: KeptBoth) throws {
        try clearKeptBothNotice()
        guard !kept.dates.isEmpty else { return }
        let name = Self.noticePrefix + (kept.madePrivate ? "1" : "0") + "|" + kept.dates.joined(separator: ",")
        context.insert(JournalFlag(name: name, setAt: now()))
        try context.save()
    }

    func keptBothNotice() throws -> KeptBoth? {
        let prefix = Self.noticePrefix
        guard let flag = try context.fetch(FetchDescriptor<JournalFlag>(predicate: #Predicate { $0.name.starts(with: prefix) })).first
        else { return nil }
        let parts = flag.name.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return KeptBoth(dates: parts[2].split(separator: ",").map(String.init), madePrivate: parts[1] == "1")
    }

    func clearKeptBothNotice() throws {
        let prefix = Self.noticePrefix
        for f in try context.fetch(FetchDescriptor<JournalFlag>(predicate: #Predicate { $0.name.starts(with: prefix) })) {
            context.delete(f)
        }
        try context.save()
    }
}
