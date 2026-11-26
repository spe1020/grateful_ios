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

    enum Choice: Equatable, CaseIterable {
        case keepBoth, keepThisIPhone, keepAccount
        /// §7: the account deleted the day; this iPhone's text goes to Set aside.
        case letItStayDeleted
        /// §9: this iPhone deleted the day; the account's text goes to Set aside.
        case deleteEverywhere
    }

    /// What kind of disagreement a row is (Prep §2, §7, §9).
    enum Kind: Equatable {
        /// Both sides have text (§2).
        case bothChanged
        /// Deleted from the account, changed on this iPhone (§7).
        case deletedFromAccount
        /// Deleted on this iPhone, changed in the account (§9).
        case deletedHere
    }

    /// A day with a choice to make.
    struct Item: Equatable, Identifiable {
        var id: String { dateString }
        let dateString: String
        var kind: Kind = .bothChanged
        /// Empty for `.deletedFromAccount`.
        let accountText: String
        let accountIsPrivate: Bool
        /// Empty for `.deletedHere`.
        let iPhoneText: String
        let iPhoneIsPrivate: Bool
        /// The conflict was found after this day was already saved to the
        /// account (the E6 re-check), not on connecting.
        let afterSaving: Bool
        /// Keep both would make a day private that one side had public.
        var keepBothBecomesPrivate: Bool { kind == .bothChanged && accountIsPrivate != iPhoneIsPrivate }

        /// The choices this row offers, the default first.
        var choices: [Choice] {
            switch kind {
            case .bothChanged: return [.keepBoth, .keepThisIPhone, .keepAccount]
            case .deletedFromAccount: return [.keepThisIPhone, .letItStayDeleted]
            case .deletedHere: return [.keepAccount, .deleteEverywhere]
            }
        }
        var defaultChoice: Choice { choices[0] }

        /// §8: Keep both would join the texts past what one event can hold.
        var keepBothTooLong: Bool {
            kind == .bothChanged && ConflictReview.isTooLong(EntryNotes.join(EntryNotes.split(accountText) + EntryNotes.split(iPhoneText)))
        }

        /// Keep both for all applies to this row (§4, §7, §8, §9).
        var keepBothForAllApplies: Bool { kind == .bothChanged && !keepBothTooLong }
    }

    /// §8: too long to save to the account (one event's content limit).
    nonisolated static func isTooLong(_ text: String) -> Bool { text.utf8.count > DailyEntry.maxContentBytes }

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
        /// §7/§9 headings: every row is that one case.
        var allKind: Kind? {
            guard let first = items.first?.kind, items.allSatisfy({ $0.kind == first }) else { return nil }
            return first
        }
        /// §7–§9: hidden when no row is a plain Keep both case.
        var showsKeepBothForAll: Bool { items.contains(where: \.keepBothForAllApplies) }
    }

    private func conflictRows() throws -> [JournalEntry] {
        let o: String? = owner, raw = SyncState.conflict.rawValue
        return try context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.ownerPubkey == o && $0.syncStateRaw == raw },
            sortBy: [SortDescriptor(\.dateString)]))
    }

    /// The newest open conflict archive for a day: the account's text
    /// (`.remoteInConflict`), or a marker that it couldn't be read
    /// (`.localInConflict`). Archives of an earlier, resolved conflict
    /// (dismissed, or already the day's base) never stand in for a later
    /// one (Audit #16 M1).
    private func latestArchive(_ dateString: String, row: JournalEntry) throws -> EarlierVersion? {
        try allArchives(dateString).first { archive in
            guard !archive.dismissed else { return false }
            if let id = archive.eventId, id == row.remoteEventID, archive.reason == .remoteInConflict { return false }
            // Archives written before V7 have no eventCreatedAt, so only the
            // id and dismissed checks apply to them. Accepted as a narrow
            // risk (Chief P34): no user stores predate V7.
            if let at = archive.eventCreatedAt, let base = row.remoteCreatedAt,
               archive.reason == .remoteInConflict || archive.reason == .deletedInAccountInConflict,
               at <= base { return false }
            return true
        }
    }

    /// This iPhone has no text for the day: it was deleted here (§9).
    private func isGoneHere(_ row: JournalEntry) -> Bool {
        row.deletedAt != nil || EntryNotes.split(row.notesText).isEmpty
    }

    private enum Case {
        case item(Item, EarlierVersion)
        case blocked(Blocked)
    }

    /// What the screen shows for a conflict row, if anything. A row with no
    /// open archive (or a deletion against a deletion) has nothing to choose.
    private func classify(_ row: JournalEntry) throws -> Case? {
        guard let archive = try latestArchive(row.dateString, row: row) else { return nil }
        let gone = isGoneHere(row)
        switch archive.reason {
        case .localInConflict:
            return gone ? nil : .blocked(Blocked(dateString: row.dateString, iPhoneText: row.notesText))
        case .deletedInAccountInConflict:
            if gone { return nil }
            return .item(Item(dateString: row.dateString, kind: .deletedFromAccount, accountText: "",
                              accountIsPrivate: row.isPrivate, iPhoneText: row.notesText, iPhoneIsPrivate: row.isPrivate,
                              afterSaving: try wasSaved(row.dateString)), archive)
        case .remoteInConflict:
            return .item(Item(dateString: row.dateString, kind: gone ? .deletedHere : .bothChanged,
                              accountText: archive.notesText, accountIsPrivate: archive.isPrivate,
                              iPhoneText: gone ? "" : row.notesText, iPhoneIsPrivate: row.isPrivate,
                              afterSaving: try wasSaved(row.dateString)), archive)
        default:
            return nil
        }
    }

    private func allArchives(_ dateString: String) throws -> [EarlierVersion] {
        let o: String? = owner
        let remote = EarlierVersionReason.remoteInConflict.rawValue, local = EarlierVersionReason.localInConflict.rawValue
        let deleted = EarlierVersionReason.deletedInAccountInConflict.rawValue
        return try context.fetch(FetchDescriptor<EarlierVersion>(
            predicate: #Predicate {
                $0.ownerPubkey == o && $0.dateString == dateString
                    && ($0.reasonRaw == remote || $0.reasonRaw == local || $0.reasonRaw == deleted)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    private func wasSaved(_ dateString: String) throws -> Bool {
        try Outbox(context: context, owner: owner).rows(dateString: dateString)
            .contains { $0.kind == DailyEntry.kind && !$0.ackedRelays.isEmpty }
    }

    /// Days in conflict, sorted by date: rows with a choice (§2, §7, §9) and
    /// blocked days (§5).
    func load() throws -> Days {
        var days = Days()
        for row in try conflictRows() {
            switch try classify(row) {
            case .item(let item, _): days.items.append(item)
            case .blocked(let b): days.blocked.append(b)
            case nil: break
            }
        }
        return days
    }

    /// The screen would list this day with a choice to make. Blocked days
    /// aren't listed, so nothing should link to the screen for them (Prep's
    /// #16 pass, Chief P33).
    func listsDay(_ dateString: String) throws -> Bool {
        try load().items.contains { $0.dateString == dateString }
    }

    /// The line a day's own view shows about it, if any (§5, §7, §8, §9,
    /// "Coming back later"). `opensScreen` lines open the conflict screen.
    enum DayLine: Equatable {
        case alsoChangedElsewhere, deletedFromAccount, deletedHere, tooLong(isToday: Bool)
        var opensScreen: Bool { if case .tooLong = self { return false }; return true }
    }

    func dayLine(_ dateString: String, isToday: Bool) throws -> DayLine? {
        if let item = try load().items.first(where: { $0.dateString == dateString }) {
            switch item.kind {
            case .bothChanged: return .alsoChangedElsewhere
            case .deletedFromAccount: return .deletedFromAccount
            case .deletedHere: return .deletedHere
            }
        }
        // §8: a kept day too long to save stays here, unsent.
        let key: String? = JournalEntry.key(owner: owner, dateString: dateString)
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })
        d.fetchLimit = 1
        if let row = try context.fetch(d).first, row.deletedAt == nil, row.syncState == .localOnly,
           Self.isTooLong(EntryNotes.join(EntryNotes.split(row.notesText))) {
            return .tooLong(isToday: isToday)
        }
        return nil
    }

    /// Apply a choice per day. Days not in `choices`, blocked days and days
    /// no longer in conflict are left alone.
    func apply(_ choices: [String: Choice]) throws {
        for row in try conflictRows() {
            guard let choice = choices[row.dateString], case .item(let item, let archive)? = try classify(row),
                  item.choices.contains(choice) else { continue }
            let account = archive.notesText, iPhone = row.notesText
            var state = SyncState.localOnly
            switch (item.kind, choice) {
            case (.bothChanged, .keepBoth):
                row.notesText = EntryNotes.join(EntryNotes.split(account) + EntryNotes.split(iPhone))
                row.isPrivate = archive.isPrivate || row.isPrivate
            case (.bothChanged, .keepThisIPhone):
                setAside(account, of: row, reason: .notKept, isPrivate: archive.isPrivate, eventId: archive.eventId)
            case (.bothChanged, .keepAccount), (.deletedHere, .keepAccount):
                setAside(iPhone, of: row, reason: .notKept, isPrivate: row.isPrivate, eventId: nil)
                row.notesText = account
                row.isPrivate = archive.isPrivate
                row.deletedAt = nil
                // The account's text unchanged: nothing to publish.
                if archive.eventId != nil { state = .synced }
            case (.deletedHere, .deleteEverywhere):
                // The day stays deleted here; a kind 5 covering the account's
                // version is signed next.
                setAside(account, of: row, reason: .deletedHere, isPrivate: archive.isPrivate, eventId: archive.eventId)
                row.notesText = ""
                if row.deletedAt == nil { row.deletedAt = now() }
            case (.deletedFromAccount, .keepThisIPhone):
                // The day goes back to the account, signed after the deletion.
                break
            case (.deletedFromAccount, .letItStayDeleted):
                setAside(iPhone, of: row, reason: .deletedFromAccount, isPrivate: row.isPrivate, eventId: nil)
                row.notesText = ""
                row.deletedAt = Date(timeIntervalSince1970: TimeInterval(archive.eventCreatedAt ?? Int(now().timeIntervalSince1970)))
                state = .synced
            default:
                continue
            }
            // The kept day is now based on the account's version (or its
            // deletion), so the pre-send check doesn't stop it again and it's
            // signed after it. A known deletion id also tells the importer
            // this deletion has been met.
            if let id = archive.eventId { row.remoteEventID = id }
            if let at = archive.eventCreatedAt { row.remoteCreatedAt = max(row.remoteCreatedAt ?? at, at) }
            row.updatedAt = now()
            row.syncStateRaw = state.rawValue
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
        let items = try load().items.filter(\.keepBothForAllApplies)
        try apply(Dictionary(uniqueKeysWithValues: items.map { ($0.dateString, Choice.keepBoth) }))
        return KeptBoth(dates: items.map(\.dateString), madePrivate: items.contains(where: \.keepBothBecomesPrivate))
    }

    private func setAside(_ text: String, of row: JournalEntry, reason: EarlierVersionReason, isPrivate: Bool, eventId: String?) {
        guard !EntryNotes.split(text).isEmpty else { return }
        context.insert(EarlierVersion(ownerPubkey: owner, dateString: row.dateString, notesText: text,
                                      reason: reason, eventId: eventId, surfaced: true,
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
