import Foundation
import SwiftData
import GratefulDayCore

/// Reads and writes journal entries. Every write is saved to disk before it
/// returns: there is no batching, so a completed save survives force quit.
///
/// Ownership (design r3.1, Chief P17): `activeOwner` is the connected
/// account's pubkey, or nil when no account is connected (guest or signed
/// out). Rows the person sees and writes are guest rows plus the active
/// owner's rows. Rows owned by any other account are read-only and are never
/// edited, merged or counted here.
enum RepositoryError: Error, Equatable {
    /// The day's relay version couldn't be read; its row is read-only.
    case dayIsBlocked
}

@MainActor
struct JournalRepository {
    let context: ModelContext
    var activeOwner: String? = nil

    private func row(owner: String?, dateString: String) throws -> JournalEntry? {
        let key: String? = JournalEntry.key(owner: owner, dateString: dateString)
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    /// The row the editor reads and writes for a date: the active owner's row
    /// if there is one, otherwise the guest row (which becomes the owner's
    /// when M5b publishes it). Includes deletion tombstones.
    func entry(for dateString: String) throws -> JournalEntry? {
        if let owner = activeOwner, let owned = try row(owner: owner, dateString: dateString) {
            return owned
        }
        return try row(owner: nil, dateString: dateString)
    }

    /// The day's reflection text, or "" when there is none (or it was deleted).
    func text(for day: JournalDay) throws -> String {
        guard let entry = try entry(for: day.dateString), entry.deletedAt == nil else { return "" }
        return entry.notesText
    }

    /// Save the day's text into `entry(for:)`, or a new guest row. The text
    /// is stored in `EntryNotes` canonical form. A day's identity (date tags
    /// and time zone) is fixed when its row is first created. Writing to a
    /// deleted day brings it back. Rows of other accounts are never touched.
    @discardableResult
    func save(text: String, for day: JournalDay, now: Date = .now) throws -> JournalEntry {
        let notes = EntryNotes.normalize(text)
        let entry: JournalEntry
        if let existing = try self.entry(for: day.dateString) {
            guard existing.syncState != .blocked else { throw RepositoryError.dayIsBlocked }
            if existing.notesText != notes || existing.deletedAt != nil {
                existing.notesText = notes
                existing.updatedAt = now
                existing.deletedAt = nil
                // An edit after sync is a pending local edit (M5b plan).
                if existing.syncState == .synced { existing.syncStateRaw = SyncState.localOnly.rawValue }
            }
            entry = existing
        } else {
            entry = JournalEntry(
                dateString: day.day.dateString, dayOfYear: day.day.dayOfYear, publishedAt: day.day.publishedAt,
                timeZoneID: day.timeZone.identifier, notesText: notes, now: now, ownerPubkey: nil
            )
            context.insert(entry)
        }
        try context.save()
        return entry
    }

    /// Delete the day's reflection locally. The row stays as a tombstone
    /// (`deletedAt`, keeping its `d` tag and any remote id) so M5b can apply
    /// web's NIP-09 deletion; the text itself is cleared now.
    func delete(_ day: JournalDay, now: Date = .now) throws {
        guard let entry = try entry(for: day.dateString), entry.deletedAt == nil else { return }
        guard entry.syncState != .blocked else { throw RepositoryError.dayIsBlocked }
        entry.notesText = ""
        entry.deletedAt = now
        entry.updatedAt = now
        // A delete after sync is pending until its kind 5 is delivered (M5b-2).
        if entry.syncState == .synced { entry.syncStateRaw = SyncState.localOnly.rawValue }
        try context.save()
    }

    /// Non-empty, non-deleted rows in a date range, any owner.
    private func reflections(from start: String?, through end: String?) throws -> [JournalEntry] {
        let lo = start ?? "", hi = end ?? "9999-12-31"
        var d = FetchDescriptor<JournalEntry>(predicate: #Predicate {
            $0.dateString >= lo && $0.dateString <= hi && $0.deletedAt == nil && $0.notesText != ""
        })
        d.propertiesToFetch = [\.dateString, \.ownerPubkey]
        return try context.fetch(d)
    }

    /// Visible rows: guest plus active owner.
    private func visibleReflections(from start: String? = nil, through end: String? = nil) throws -> [JournalEntry] {
        try reflections(from: start, through: end).filter { $0.ownerPubkey == nil || $0.ownerPubkey == activeOwner }
    }

    /// The most recent date before `dateString` that has a visible reflection.
    func latestReflectionDate(before dateString: String) throws -> String? {
        try visibleReflections().map(\.dateString).filter { $0 < dateString }.max()
    }

    // MARK: - Calendar and counts

    /// Dates with a visible reflection between two `YYYY-MM-DD` dates, inclusive.
    func reflectionDates(from start: String, through end: String) throws -> Set<String> {
        Set(try visibleReflections(from: start, through: end).map(\.dateString))
            .union(try blockedDates(from: start, through: end))
    }

    /// The active account's days whose relay version can't be read. Marked in
    /// the calendar even with no local text: never shown as empty (Audit M2,
    /// spec §1.3, test plan B9).
    func blockedDates(from start: String, through end: String) throws -> Set<String> {
        guard let owner = activeOwner else { return [] }
        let o: String? = owner, raw = SyncState.blocked.rawValue
        let d = FetchDescriptor<JournalEntry>(predicate: #Predicate {
            $0.dateString >= start && $0.dateString <= end && $0.deletedAt == nil
                && $0.ownerPubkey == o && $0.syncStateRaw == raw
        })
        return Set(try context.fetch(d).map(\.dateString))
    }

    /// Days with a visible reflection, in total (a guest row and the owner's
    /// row on the same date count once).
    func totalReflectionCount() throws -> Int {
        Set(try visibleReflections().map(\.dateString)).count
    }

    // MARK: - Other accounts' rows (read-only, P17)

    private func otherAccountReflections(from start: String? = nil, through end: String? = nil) throws -> [JournalEntry] {
        try reflections(from: start, through: end).filter { $0.ownerPubkey != nil && $0.ownerPubkey != activeOwner }
    }

    /// Dates where only another (signed-out) account has a reflection.
    func otherAccountDates(from start: String, through end: String) throws -> Set<String> {
        Set(try otherAccountReflections(from: start, through: end).map(\.dateString))
    }

    /// Days with another account's reflection (Prep: "N earlier reflections
    /// from another account are kept on this iPhone").
    func otherAccountDayCount() throws -> Int {
        Set(try otherAccountReflections().map(\.dateString)).count
    }

    /// Every reflection on this iPhone, any owner (for "Remove account and
    /// local data", which removes them all).
    func allReflectionCount() throws -> Int {
        try reflections(from: nil, through: nil).count
    }

    /// Read-only text another account wrote on a date, or nil.
    func otherAccountText(for dateString: String) throws -> String? {
        try otherAccountReflections(from: dateString, through: dateString).first?.notesText
    }

    // MARK: - Milestones (totals only, shown once)

    static let milestones = [1, 7, 30, 100, 365]

    /// The milestone to show after a save: only when the total is exactly a
    /// milestone that hasn't been shown. Every milestone the total has
    /// passed is recorded as shown, silently when it wasn't hit exactly
    /// (for example after a large import), so none is ever shown late or
    /// with the wrong number (Chief P12).
    func takeMilestone(now: Date = .now) throws -> Int? {
        let total = try totalReflectionCount()
        let shown = Set(try context.fetch(FetchDescriptor<AcknowledgedMilestone>()).map(\.total))
        let passed = Self.milestones.filter { $0 <= total && !shown.contains($0) }
        guard !passed.isEmpty else { return nil }
        for m in passed {
            context.insert(AcknowledgedMilestone(total: m, acknowledgedAt: now))
        }
        try context.save()
        return passed.contains(total) ? total : nil
    }

    // MARK: - One-time flags

    func flag(_ name: String) throws -> Bool {
        var d = FetchDescriptor<JournalFlag>(predicate: #Predicate { $0.name == name })
        d.fetchLimit = 1
        return try !context.fetch(d).isEmpty
    }

    func clearFlag(_ name: String) throws {
        for f in try context.fetch(FetchDescriptor<JournalFlag>(predicate: #Predicate { $0.name == name })) {
            context.delete(f)
        }
        try context.save()
    }

    func setFlag(_ name: String, now: Date = .now) throws {
        guard try !flag(name) else { return }
        context.insert(JournalFlag(name: name, setAt: now))
        try context.save()
    }

    // MARK: - Earlier versions (local archive)

    /// Kept-aside versions the person should see (P22), for the active owner
    /// (or guest) only.
    func surfacedEarlierVersions() throws -> [EarlierVersion] {
        try setAsideVersions().filter { !$0.dismissed }
    }

    /// Set aside (P22): this account's surfaced versions that a relay version
    /// replaced, newest first. Dismissing the Today line never removes one,
    /// and nothing here is ever purged. Conflict copies are excluded; they
    /// belong to the conflict case, not a replacement.
    func setAsideVersions() throws -> [EarlierVersion] {
        let all = try context.fetch(FetchDescriptor<EarlierVersion>(
            predicate: #Predicate { $0.surfaced },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
        return all.filter { $0.ownerPubkey == activeOwner && $0.reason == .replacedByRemote }
    }

    /// Hide the Today line for these versions. Nothing is deleted.
    func dismissEarlierVersions(_ ids: [UUID]) throws {
        for v in try setAsideVersions() where ids.contains(v.id) { v.dismissed = true }
        try context.save()
    }

    /// Chief P25: whether a day shows "On this iPhone only". Guests always
    /// do. On an account, only a day imported from relays whose text still
    /// matches that version (`.synced`; any local edit makes it `.localOnly`)
    /// drops the label. Days written or edited here, and days whose state
    /// can't be read, keep it (they become M5b-2's Saving mark).
    func showsLocalOnlyLabel(_ dateString: String) -> Bool {
        guard activeOwner != nil else { return true }
        // No row yet, or unreadable: only here.
        guard let row = try? entry(for: dateString) else { return true }
        return row.syncState != .synced
    }

    /// The editor's row for a date is read-only while its relay version is unreadable.
    func isBlocked(_ dateString: String) throws -> Bool {
        try entry(for: dateString)?.syncState == .blocked
    }

    /// The day an entry belongs to, rebuilt from its stored identity.
    static func day(of entry: JournalEntry) -> DailyEntry.Day {
        let zone = TimeZone(identifier: entry.timeZoneID) ?? .current
        return DailyEntry.Day(containing: Date(timeIntervalSince1970: TimeInterval(entry.publishedAt)), timeZone: zone)
    }
}
