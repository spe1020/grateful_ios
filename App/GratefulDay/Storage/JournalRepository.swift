import Foundation
import SwiftData
import GratefulDayCore

/// Reads and writes journal entries. Every write is saved to disk before it
/// returns: there is no batching, so a completed save survives force quit.
@MainActor
struct JournalRepository {
    let context: ModelContext

    /// The entry for a local date, or nil.
    func entry(for dateString: String) throws -> JournalEntry? {
        var descriptor = FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.dateString == dateString })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Save the day's text, creating the entry if needed (one per date). The
    /// text is stored in `EntryNotes` canonical form. A day's identity is
    /// fixed when its entry is first created.
    @discardableResult
    func save(text: String, for day: DailyEntry.Day, timeZone: TimeZone = .current, now: Date = .now) throws -> JournalEntry {
        let notes = EntryNotes.normalize(text)
        let entry: JournalEntry
        if let existing = try self.entry(for: day.dateString) {
            existing.notesText = notes
            existing.updatedAt = now
            entry = existing
        } else {
            entry = JournalEntry(
                dateString: day.dateString, dayOfYear: day.dayOfYear, publishedAt: day.publishedAt,
                timeZoneID: timeZone.identifier, notesText: notes, now: now
            )
            context.insert(entry)
        }
        try context.save()
        return entry
    }

    /// The day an entry belongs to, rebuilt from its stored identity.
    static func day(of entry: JournalEntry) -> DailyEntry.Day {
        let zone = TimeZone(identifier: entry.timeZoneID) ?? .current
        return DailyEntry.Day(containing: Date(timeIntervalSince1970: TimeInterval(entry.publishedAt)), timeZone: zone)
    }
}
