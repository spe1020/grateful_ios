import Foundation
import SwiftData
import GratefulDayCore

/// Reads and writes journal entries. Every write is saved to disk before it
/// returns: there is no batching, so a completed save survives force quit.
@MainActor
struct JournalRepository {
    let context: ModelContext

    /// The entry row for a local date (including a deletion tombstone), or nil.
    func entry(for dateString: String) throws -> JournalEntry? {
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.dateString == dateString })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The day's reflection text, or "" when there is none (or it was deleted).
    func text(for day: JournalDay) throws -> String {
        guard let entry = try entry(for: day.dateString), entry.deletedAt == nil else { return "" }
        return entry.notesText
    }

    /// Save the day's text, creating the entry if needed (one per date). The
    /// text is stored in `EntryNotes` canonical form. A day's identity (date
    /// tags and time zone) is fixed when its entry is first created. Writing
    /// to a deleted day brings it back.
    @discardableResult
    func save(text: String, for day: JournalDay, now: Date = .now) throws -> JournalEntry {
        let notes = EntryNotes.normalize(text)
        let entry: JournalEntry
        if let existing = try self.entry(for: day.dateString) {
            existing.notesText = notes
            existing.updatedAt = now
            existing.deletedAt = nil
            entry = existing
        } else {
            entry = JournalEntry(
                dateString: day.day.dateString, dayOfYear: day.day.dayOfYear, publishedAt: day.day.publishedAt,
                timeZoneID: day.timeZone.identifier, notesText: notes, now: now
            )
            context.insert(entry)
        }
        try context.save()
        return entry
    }

    /// Delete the day's reflection locally. The row stays as a tombstone
    /// (`deletedAt`, keeping its `d` tag and any remote id) so M5 can apply
    /// web's NIP-09 deletion; the text itself is cleared now.
    func delete(_ day: JournalDay, now: Date = .now) throws {
        guard let entry = try entry(for: day.dateString), entry.deletedAt == nil else { return }
        entry.notesText = ""
        entry.deletedAt = now
        entry.updatedAt = now
        try context.save()
    }

    /// The most recent date before `dateString` that has a reflection.
    func latestReflectionDate(before dateString: String) throws -> String? {
        var descriptor = FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.dateString < dateString && $0.deletedAt == nil && $0.notesText != "" },
            sortBy: [SortDescriptor(\.dateString, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.dateString
    }

    /// The day an entry belongs to, rebuilt from its stored identity.
    static func day(of entry: JournalEntry) -> DailyEntry.Day {
        let zone = TimeZone(identifier: entry.timeZoneID) ?? .current
        return DailyEntry.Day(containing: Date(timeIntervalSince1970: TimeInterval(entry.publishedAt)), timeZone: zone)
    }
}
