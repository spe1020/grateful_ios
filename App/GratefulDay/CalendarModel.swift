import Foundation
import Observation

/// One cell of the month grid.
struct CalendarDay: Identifiable, Equatable {
    let dateString: String
    let dayNumber: Int
    let isToday: Bool
    let isFuture: Bool
    let hasReflection: Bool
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

    private let repository: JournalRepository
    private let today: () -> JournalDay
    private let calendar: Calendar

    init(repository: JournalRepository, today: @escaping () -> JournalDay = { JournalDay(containing: .now) }) {
        self.repository = repository
        self.today = today
        var cal = Calendar.current
        cal.timeZone = today().timeZone
        self.calendar = cal
        self.monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today().start))!
        load()
    }

    var monthCount: Int { reflectionDates.count }

    var monthTitle: String { monthStart.formatted(.dateTime.month(.wide).year()) }

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
            return CalendarDay(dateString: ds, dayNumber: offset + 1, isToday: ds == todayString,
                               isFuture: ds > todayString, hasReflection: reflectionDates.contains(ds))
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
