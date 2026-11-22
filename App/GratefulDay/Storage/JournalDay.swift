import Foundation
import GratefulDayCore

/// A local day together with the time zone it was computed in. One value, so
/// a caller can't pair a day with a different zone (Audit M2 L2).
struct JournalDay: Equatable, Sendable {
    let day: DailyEntry.Day
    let timeZone: TimeZone

    init(containing instant: Date, timeZone: TimeZone = .current) {
        self.day = DailyEntry.Day(containing: instant, timeZone: timeZone)
        self.timeZone = timeZone
    }

    var dateString: String { day.dateString }

    /// Local midnight at the start of this day.
    var start: Date { Date(timeIntervalSince1970: TimeInterval(day.publishedAt)) }

    /// Whole calendar days from `self` to `later` (0 for the same day).
    func days(until later: JournalDay) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.dateComponents([.day], from: start, to: later.start).day ?? 0
    }
}
