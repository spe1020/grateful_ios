import XCTest
import SwiftData
import Observation
import GratefulDayCore
@testable import GratefulDay

/// M3b: calendar, counts, milestones; Chief P11; Audit M3a L2.
@MainActor
final class CalendarTests: XCTestCase {
    private var container: ModelContainer!
    private var repo: JournalRepository!
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        repo = JournalRepository(context: container.mainContext)
    }

    private func day(_ s: String) -> JournalDay { TodayEditorModel.parse(s, timeZone: zone)! }

    // Criterion 5: marks, read-only past, disabled future.
    func testGridMarksReflectionDaysTodayAndFuture() throws {
        try repo.save(text: "a", for: day("2026-11-03"))
        try repo.save(text: "b", for: day("2026-11-21"))
        try repo.save(text: "elsewhere", for: day("2026-10-31"))
        let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") })
        let days = model.grid.compactMap { $0 }
        XCTAssertEqual(days.count, 30)
        XCTAssertEqual(days.filter(\.hasReflection).map(\.dateString), ["2026-11-03", "2026-11-21"])
        XCTAssertEqual(days.first { $0.isToday }?.dateString, "2026-11-21")
        XCTAssertEqual(days.filter(\.isFuture).count, 9, "Nov 22–30")
        XCTAssertFalse(days.contains { $0.isFuture && $0.dateString <= "2026-11-21" })
    }

    /// Audit M3b M1: Buddhist and Japanese calendar users get the same
    /// Gregorian grid as everyone else (entries use Gregorian dates).
    func testNonGregorianUserCalendarsShowTheSameGrid() throws {
        try repo.save(text: "a", for: day("2026-11-03"))
        try repo.save(text: "b", for: day("2026-11-21"))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US")
        let reference = CalendarModel(repository: repo, today: { self.day("2026-11-21") }, userCalendar: gregorian)
        XCTAssertEqual(reference.monthTitle, "November 2026")
        for id in [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura, .hebrew, .persian] {
            var userCal = Calendar(identifier: id)
            userCal.locale = Locale(identifier: "en_US")
            let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") }, userCalendar: userCal)
            let days = model.grid.compactMap { $0 }
            XCTAssertEqual(days.count, 30, "\(id)")
            XCTAssertEqual(days.first?.dateString, "2026-11-01", "\(id)")
            XCTAssertEqual(days.first { $0.isToday }?.dateString, "2026-11-21", "\(id)")
            XCTAssertEqual(days.filter(\.hasReflection).map(\.dateString), ["2026-11-03", "2026-11-21"], "\(id)")
            XCTAssertEqual(days.filter(\.isFuture).count, 9, "\(id)")
            XCTAssertEqual(model.monthCount, 2, "\(id)")
            XCTAssertEqual(model.monthTitle, reference.monthTitle, "\(id): the title names the Gregorian month")
        }
    }

    func testGridAlignsTheFirstWeekday() {
        let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") })
        var cal = Calendar.current
        cal.timeZone = zone
        let firstWeekday = cal.component(.weekday, from: day("2026-11-01").start) // Sunday = 1
        let leading = model.grid.prefix { $0 == nil }.count
        XCTAssertEqual(leading, (firstWeekday - cal.firstWeekday + 7) % 7)
    }

    func testCannotGoPastTheCurrentMonth() {
        let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") })
        XCTAssertFalse(model.canShowNextMonth)
        model.showPreviousMonth()
        XCTAssertTrue(model.canShowNextMonth)
        XCTAssertEqual(model.grid.compactMap { $0 }.first?.dateString, "2026-10-01")
        model.showNextMonth()
        model.showNextMonth()
        XCTAssertEqual(model.grid.compactMap { $0 }.first?.dateString, "2026-11-01")
    }

    // Criterion 6: counts, never streaks.
    func testMonthAndTotalCountsIgnoreDeletedDays() throws {
        try repo.save(text: "a", for: day("2026-11-01"))
        try repo.save(text: "b", for: day("2026-11-02"))
        try repo.save(text: "c", for: day("2026-10-15"))
        try repo.save(text: "d", for: day("2026-11-05"))
        try repo.delete(day("2026-11-05"))
        let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") })
        XCTAssertEqual(model.monthCount, 2)
        XCTAssertEqual(model.totalCount, 3)
        XCTAssertEqual(CalendarModel.monthCountText(2), "2 reflections this month")
        XCTAssertEqual(CalendarModel.monthCountText(1), "1 reflection this month")
        XCTAssertEqual(CalendarModel.monthCountText(0), "No reflections this month")
        XCTAssertEqual(CalendarModel.totalCountText(3), "3 reflections in all")
    }

    func testNoStreakLanguageInCountCopy() {
        for n in [0, 1, 2, 7, 30, 365] {
            for text in [CalendarModel.monthCountText(n), CalendarModel.totalCountText(n), TodayEditorModel.milestoneText(n)] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains("streak"), text)
                XCTAssertFalse(text.localizedCaseInsensitiveContains("in a row"), text)
            }
        }
    }

    // Criterion 7: milestones on totals, shown once.
    func testMilestonesAreShownOnceEach() throws {
        try repo.save(text: "first", for: day("2026-11-01"))
        XCTAssertEqual(try repo.takeMilestone(), 1)
        XCTAssertNil(try repo.takeMilestone(), "shown once")
        for d in 2...7 { try repo.save(text: "x", for: day(String(format: "2026-11-%02d", d))) }
        XCTAssertEqual(try repo.takeMilestone(), 7)
        XCTAssertNil(try repo.takeMilestone())
    }

    func testReachingSeveralAtOnceShowsOnlyTheExactOne() throws {
        for d in 1...7 { try repo.save(text: "x", for: day(String(format: "2026-11-%02d", d))) }
        XCTAssertEqual(try repo.takeMilestone(), 7)
        XCTAssertNil(try repo.takeMilestone(), "1 is recorded with 7, never shown late")
    }

    /// Chief P12: a large import (M5) passes milestones without hitting one
    /// exactly: no line, and none of them is shown later with a wrong number.
    func testImportOf201EntriesShowsNoMilestoneLine() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = day("2026-01-01").start
        for i in 0..<201 {
            let d = JournalDay(containing: cal.date(byAdding: .day, value: i, to: start)!.addingTimeInterval(43_200), timeZone: zone)
            container.mainContext.insert(JournalEntry(dateString: d.day.dateString, dayOfYear: d.day.dayOfYear,
                                                      publishedAt: d.day.publishedAt, timeZoneID: zone.identifier,
                                                      notesText: "imported", now: .now))
        }
        try container.mainContext.save()
        XCTAssertNil(try repo.takeMilestone(), "201 is not a milestone")
        let shown = Set(try container.mainContext.fetch(FetchDescriptor<AcknowledgedMilestone>()).map(\.total))
        XCTAssertEqual(shown, [1, 7, 30, 100], "passed milestones are recorded silently")
        // The editor shows no line either.
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        model.edit("one more"); model.flush()
        XCTAssertNil(model.milestoneMessage, "202 is not a milestone")
    }

    func testDeletingAndRewritingDoesNotRepeatAMilestone() throws {
        try repo.save(text: "x", for: day("2026-11-01"))
        XCTAssertEqual(try repo.takeMilestone(), 1)
        try repo.delete(day("2026-11-01"))
        try repo.save(text: "again", for: day("2026-11-01"))
        XCTAssertNil(try repo.takeMilestone())
    }

    func testEditorShowsTheMilestoneAfterTheSave() throws {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        model.edit("first ever")
        model.flush()
        XCTAssertEqual(model.milestoneMessage, "Your first reflection.")
    }

    // Criterion 9: a full year opens fast.
    func testAFullYearMonthOpensQuickly() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = day("2025-11-21").start
        for i in 0..<366 {
            let d = JournalDay(containing: cal.date(byAdding: .day, value: i, to: start)!.addingTimeInterval(43_200), timeZone: zone)
            container.mainContext.insert(JournalEntry(dateString: d.day.dateString, dayOfYear: d.day.dayOfYear,
                                                      publishedAt: d.day.publishedAt, timeZoneID: zone.identifier,
                                                      notesText: String(repeating: "grateful ", count: 40), now: .now))
        }
        try container.mainContext.save()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") })
            _ = model.grid
            XCTAssertEqual(model.monthCount, 21)
            XCTAssertEqual(model.totalCount, 366)
        }
        XCTAssertLessThan(elapsed, .milliseconds(500), "\(elapsed)")
    }

    // Audit M3a L2: a refused edit makes the text field re-render with the kept text.
    func testRefusedEditAtTheCapNotifiesTheView() {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        let atCap = String(repeating: "a", count: TodayEditorModel.maxBytes)
        XCTAssertTrue(model.edit(atCap))
        final class Flag: @unchecked Sendable { var value = false }
        let notified = Flag()
        withObservationTracking { _ = model.refusedEdits } onChange: { notified.value = true }
        XCTAssertFalse(model.edit(atCap + "b"))
        XCTAssertTrue(notified.value, "the editor view is told to redraw with the kept text")
        XCTAssertEqual(model.text, atCap)
    }
}

/// Chief P11, and opening an M2 store with the M3b schema.
@MainActor
final class StoreSchemaAndClaimTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    func testNoBackupClaimUntilTheFirstCheckSucceeds() {
        let store = JournalStore(location: StoreLocation(directory: root.appendingPathComponent("Store")))
        XCTAssertFalse(store.mayClaimBackupExclusion, "before any check: no claim")
        XCTAssertEqual(PrivacyCopy.statement(exclusionChecked: store.backupExclusionConfirmed, exclusionFailed: store.backupExclusionFailed),
                       PrivacyCopy.neutralStatement, "before any check: the neutral statement, no claim either way")
        store.openIfPossible(protectedDataAvailable: false)
        XCTAssertFalse(store.mayClaimBackupExclusion, "still locked: no claim")
        store.openIfPossible(protectedDataAvailable: true)
        XCTAssertTrue(store.mayClaimBackupExclusion)
        XCTAssertEqual(PrivacyCopy.statement(exclusionChecked: store.backupExclusionConfirmed, exclusionFailed: store.backupExclusionFailed),
                       PrivacyCopy.preAccountStatement)
    }

    func testExclusionIsCheckedEvenWhenTheStoreFailsToOpen() throws {
        let location = StoreLocation(directory: root.appendingPathComponent("Store"))
        _ = try location.prepare()
        FileManager.default.createFile(atPath: location.storeURL.path, contents: Data(repeating: 0x5A, count: 4096))
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        guard case .failed = store.state else { return XCTFail("\(store.state)") }
        XCTAssertTrue(store.backupExclusionConfirmed, "the check ran before the open attempt")
    }

    /// Adding `AcknowledgedMilestone` must not need a destructive migration:
    /// an M2 store (JournalEntry only) opens with the new schema, data intact.
    func testAnM2StoreOpensWithTheNewSchema() throws {
        let location = StoreLocation(directory: root.appendingPathComponent("Store"))
        _ = try location.prepare()
        let day = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000))
        do {
            // Written with the FROZEN M2 model, unversioned, as M2 shipped.
            let old = Schema([JournalSchemaV1.JournalEntry.self])
            let container = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: location.storeURL, cloudKitDatabase: .none))
            container.mainContext.insert(JournalSchemaV1.JournalEntry(
                dateString: day.day.dateString, dayOfYear: day.day.dayOfYear, publishedAt: day.day.publishedAt,
                timeZoneID: day.timeZone.identifier, notesText: "from M2", now: .now))
            try container.mainContext.save()
        }
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        let container = try XCTUnwrap(store.container)
        XCTAssertEqual(try JournalRepository(context: container.mainContext).text(for: day), "from M2")
        XCTAssertEqual(try JournalRepository(context: container.mainContext).takeMilestone(), 1)
    }
}
