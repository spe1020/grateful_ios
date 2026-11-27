import Foundation
import Observation

/// One cell of the month grid.
struct CalendarDay: Identifiable, Equatable {
    let dateString: String
    let dayNumber: Int
    let isToday: Bool
    let isFuture: Bool
    let hasReflection: Bool
    /// Not yet saved to the account (the Saving mark).
    var saving: Bool = false
    /// Only another (not connected) account wrote this day (P17).
    var otherAccountOnly: Bool = false
    var id: String { dateString }
}

/// The calendar's month: which days have a reflection, and the counts.
/// A failed read is `.readFailed`, never an empty month.
@MainActor
@Observable
final class CalendarModel {
    enum LoadState: Equatable { case loading, ready, readFailed }

    private(set) var loadState: LoadState = .loading
    /// First day of the month shown, in the user's calendar.
    private(set) var monthStart: Date
    private(set) var reflectionDates: Set<String> = []
    private(set) var totalCount = 0
    private(set) var otherAccountDates: Set<String> = []
    private(set) var savingDates: Set<String> = []
    private(set) var otherAccountReflectionCount = 0

    private let repository: JournalRepository
    private let today: () -> JournalDay
    private let calendar: Calendar

    /// `userCalendar` supplies only locale and first weekday. Dates, months
    /// and the grid are always Gregorian, because stored entries and Today
    /// use Gregorian `YYYY-MM-DD` days (`DailyEntry.Day`). Using the user's
    /// calendar here broke Buddhist and Japanese calendars (Audit M3b M1).
    init(repository: JournalRepository,
         today: @escaping () -> JournalDay = { JournalDay(containing: .now) },
         userCalendar: Calendar = .current) {
        self.repository = repository
        self.today = today
        var cal = Calendar(identifier: .gregorian)
        cal.locale = userCalendar.locale
        cal.firstWeekday = userCalendar.firstWeekday
        cal.timeZone = today().timeZone
        self.calendar = cal
        self.monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today().start))!
        load()
    }

    var monthCount: Int { reflectionDates.count }

    /// Month name and year of the Gregorian month the grid shows, in the
    /// user's language.
    var monthTitle: String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: calendar.locale ?? .current,
                                     calendar: calendar, timeZone: calendar.timeZone)
        style = style.month(.wide).year()
        return monthStart.formatted(style)
    }

    /// Weekday headings, starting at the user's first weekday.
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var canShowNextMonth: Bool {
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: today().start))!
        return monthStart < current
    }

    func showPreviousMonth() {
        monthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        load()
    }

    func showNextMonth() {
        guard canShowNextMonth else { return }
        monthStart = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        load()
    }

    func load() {
        let days = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let first = Self.dateString(monthStart, calendar)
        let last = Self.dateString(calendar.date(byAdding: .day, value: days - 1, to: monthStart)!, calendar)
        do {
            reflectionDates = try repository.reflectionDates(from: first, through: last)
            totalCount = try repository.totalReflectionCount()
            otherAccountDates = try repository.otherAccountDates(from: first, through: last)
            savingDates = try repository.savingDates(from: first, through: last)
            otherAccountReflectionCount = try repository.otherAccountReflectionCount()
            loadState = .ready
        } catch {
            loadState = .readFailed
            StorageLog.error("Reading the calendar failed", error: error)
        }
    }

    /// Leading blanks (nil) to align the first weekday, then each day.
    var grid: [CalendarDay?] {
        let todayString = today().dateString
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let days: [CalendarDay?] = (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: monthStart)!
            let ds = Self.dateString(date, calendar)
            let mine = reflectionDates.contains(ds)
            return CalendarDay(dateString: ds, dayNumber: offset + 1, isToday: ds == todayString,
                               isFuture: ds > todayString, hasReflection: mine,
                               saving: mine && savingDates.contains(ds),
                               otherAccountOnly: !mine && otherAccountDates.contains(ds))
        }
        return Array(repeating: nil, count: leading) + days
    }

    static func dateString(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    // MARK: - Copy (counts practice; never streaks)

    static func monthCountText(_ n: Int) -> String {
        switch n {
        case 0: return "No reflections this month"
        case 1: return "1 reflection this month"
        default: return "\(n) reflections this month"
        }
    }

    static func totalCountText(_ n: Int) -> String {
        n == 1 ? "1 reflection in all" : "\(n) reflections in all"
    }
}
