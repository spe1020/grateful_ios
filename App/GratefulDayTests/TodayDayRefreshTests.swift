import XCTest
import SwiftData
import UIKit
import GratefulDayCore
@testable import GratefulDay

/// Spec 10a / AC 7a (Seth's decision 3, 58d27316): the card and the editor
/// share one local day. Midnight, a time-zone change and a clock change all
/// run the existing day-change refresh; a failed save keeps the editor (and
/// so the card) on the unsaved entry.
@MainActor
final class TodayDayRefreshTests: XCTestCase {
    private var container: ModelContainer!
    private var repo: JournalRepository!
    private let chicago = TimeZone(identifier: "America/Chicago")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    struct Locked: Error {}

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        repo = JournalRepository(context: container.mainContext)
    }

    /// 2026-11-21 23:30 in Chicago = 2026-11-22 14:30 in Tokyo.
    private let lateEvening = ISO8601DateFormatter().date(from: "2026-11-22T05:30:00Z")!
    private let afterMidnight = ISO8601DateFormatter().date(from: "2026-11-22T06:05:00Z")!

    func testAllThreeTriggersRunTheRefresh() {
        XCTAssertEqual(Set(TodayDayRefresh.notifications), [
            .NSCalendarDayChanged, .NSSystemTimeZoneDidChange, UIApplication.significantTimeChangeNotification,
        ])
    }

    /// The view's publisher fires for each trigger (so removing one from the
    /// merge fails here, not only in the list above).
    func testPublisherFiresForEachTrigger() {
        let center = NotificationCenter()
        var seen: [Notification.Name] = []
        let sub = TodayDayRefresh.publisher(center: center).sink { seen.append($0.name) }
        for name in TodayDayRefresh.notifications { center.post(name: name, object: nil) }
        sub.cancel()
        XCTAssertEqual(seen, TodayDayRefresh.notifications)
    }

    func testMidnightMovesEditorAndCardTogether() throws {
        let started = JournalDay(containing: lateEvening, timeZone: chicago)
        let editor = TodayEditorModel(repository: repo, day: started)
        editor.edit("before midnight")
        let shown = TodayDayRefresh.refresh(current: started, editor: editor, now: afterMidnight, timeZone: chicago)
        XCTAssertEqual(shown.dateString, "2026-11-22")
        XCTAssertEqual(shown, editor.day, "card and editor on the same day")
        XCTAssertEqual(try repo.text(for: started), "before midnight")
        XCTAssertEqual(editor.text, "")
    }

    func testTimeZoneChangeThatMovesTheDateMovesBoth() throws {
        let started = JournalDay(containing: lateEvening, timeZone: chicago)
        XCTAssertEqual(started.dateString, "2026-11-21")
        let editor = TodayEditorModel(repository: repo, day: started)
        editor.edit("written in Chicago")
        let shown = TodayDayRefresh.refresh(current: started, editor: editor, now: lateEvening, timeZone: tokyo)
        XCTAssertEqual(shown.dateString, "2026-11-22")
        XCTAssertEqual(shown, editor.day)
        XCTAssertEqual(try repo.text(for: started), "written in Chicago", "saved to the day it was written on")
        XCTAssertEqual(DailyAffirmation.text(for: shown), DailyAffirmation.library?.affirmation(forDate: "2026-11-22"))
    }

    func testNoChangeKeepsTheSameDayAndText() {
        let started = JournalDay(containing: lateEvening, timeZone: chicago)
        let editor = TodayEditorModel(repository: repo, day: started)
        editor.edit("still typing")
        let shown = TodayDayRefresh.refresh(current: started, editor: editor, now: lateEvening, timeZone: chicago)
        XCTAssertEqual(shown, started)
        XCTAssertEqual(editor.text, "still typing")
    }

    /// AC 7a: a forced save failure keeps the unsaved entry, and the card
    /// stays on the editor's day. The next refresh after the store recovers moves on.
    func testFailedSaveKeepsTheUnsavedEntryAndTheCardOnItsDay() throws {
        var locked = true
        let started = JournalDay(containing: lateEvening, timeZone: chicago)
        let editor = TodayEditorModel(repository: repo, day: started, save: { [repo] text, day in
            if locked { throw Locked() }
            try repo!.save(text: text, for: day)
        })
        editor.edit("must not be lost")
        for (now, zone) in [(afterMidnight, chicago), (lateEvening, tokyo)] {
            let shown = TodayDayRefresh.refresh(current: started, editor: editor, now: now, timeZone: zone)
            XCTAssertEqual(shown, started, "stays on the unsaved entry")
            XCTAssertEqual(editor.day, started)
            XCTAssertEqual(editor.text, "must not be lost")
            XCTAssertTrue(editor.hasUnsavedChanges)
        }
        locked = false
        let shown = TodayDayRefresh.refresh(current: started, editor: editor, now: afterMidnight, timeZone: chicago)
        XCTAssertEqual(shown.dateString, "2026-11-22")
        XCTAssertEqual(try repo.text(for: started), "must not be lost")
    }

    /// AC 7a: rapid edits right up to the change lose nothing, and the
    /// still-pending debounced save never writes the old text into the new day.
    func testRapidEditsAcrossTheChangeLoseNothing() async throws {
        let started = JournalDay(containing: lateEvening, timeZone: chicago)
        let editor = TodayEditorModel(repository: repo, day: started)
        for n in 1...20 { editor.edit(String(repeating: "x", count: n)) }
        let shown = TodayDayRefresh.refresh(current: started, editor: editor, now: lateEvening, timeZone: tokyo)
        editor.edit("new day")
        try await Task.sleep(for: TodayEditorModel.saveDelay * 2)
        XCTAssertEqual(try repo.text(for: started), String(repeating: "x", count: 20))
        XCTAssertEqual(try repo.text(for: shown), "new day")
    }

    /// B8 (Audit f91cb48e): the real notification → `TodayDayRefresh` →
    /// `TodayEditorModel` path, with only the save stubbed. Each posted
    /// notification (time zone, clock, midnight) drives the refresh the way
    /// `TodayView` wires it; while saving fails nothing moves.
    func testPostedNotificationsDriveTheRefreshAndAFailedSaveHolds() throws {
        let center = NotificationCenter()
        var locked = true
        var zone = chicago
        let started = JournalDay(containing: lateEvening, timeZone: chicago)
        var shown = started
        let editor = TodayEditorModel(repository: repo, day: started, save: { [repo] text, day in
            if locked { throw Locked() }
            try repo!.save(text: text, for: day)
        })
        let sub = TodayDayRefresh.publisher(center: center).sink { _ in
            shown = TodayDayRefresh.refresh(current: shown, editor: editor, now: self.lateEvening, timeZone: zone)
        }
        defer { sub.cancel() }
        editor.edit("typed before the flight landed")
        zone = tokyo
        for name in TodayDayRefresh.notifications {
            center.post(name: name, object: nil)
            XCTAssertEqual(shown, started, "\(name.rawValue): stays on the unsaved entry")
            XCTAssertEqual(editor.day, started)
            XCTAssertEqual(editor.text, "typed before the flight landed")
        }
        locked = false
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(shown.dateString, "2026-11-22")
        XCTAssertEqual(shown, editor.day, "card and editor on the same day")
        XCTAssertEqual(try repo.text(for: started), "typed before the flight landed")
    }
}
