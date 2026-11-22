import XCTest
import SwiftData
import GratefulDayCore
@testable import GratefulDay

/// M3a: Today's editor.
@MainActor
final class TodayEditorTests: XCTestCase {
    private var container: ModelContainer!
    private var repo: JournalRepository!
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        repo = JournalRepository(context: container.mainContext)
    }

    private func day(_ dateString: String) -> JournalDay {
        TodayEditorModel.parse(dateString, timeZone: zone)!
    }

    // Criterion 1: saves as you type, no save button.
    func testTypingSavesAfterTheDelay() async throws {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        XCTAssertTrue(model.edit("Morning coffee"))
        XCTAssertEqual(try repo.text(for: day("2026-11-21")), "", "not yet: waits for a pause")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(try repo.text(for: day("2026-11-21")), "Morning coffee")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testFlushSavesImmediately() throws {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        model.edit("one\n\ntwo")
        XCTAssertTrue(model.flush())
        XCTAssertEqual(try repo.text(for: day("2026-11-21")), "one\n\ntwo")
    }

    func testLoadsExistingText() throws {
        try repo.save(text: "kept", for: day("2026-11-21"))
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        XCTAssertEqual(model.text, "kept")
        XCTAssertTrue(model.isEditable)
    }

    // Criterion 2: midnight keeps text with the day it was started on.
    func testMidnightSavesToTheStartedDayThenMovesOn() throws {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        model.edit("written just before midnight")
        model.dayChanged(to: day("2026-11-22"))
        XCTAssertEqual(try repo.text(for: day("2026-11-21")), "written just before midnight")
        XCTAssertEqual(model.day, day("2026-11-22"))
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(try repo.text(for: day("2026-11-22")), "")
    }

    // Criterion 3: length cap.
    func testNearlyFullAndHardCap() {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        let nearly = String(repeating: "a", count: TodayEditorModel.nearlyFullBytes)
        XCTAssertTrue(model.edit(nearly))
        XCTAssertTrue(model.isNearlyFull)
        let atCap = String(repeating: "a", count: TodayEditorModel.maxBytes)
        XCTAssertTrue(model.edit(atCap))
        XCTAssertFalse(model.edit(atCap + "b"), "input stops at the limit")
        XCTAssertEqual(model.text.utf8.count, TodayEditorModel.maxBytes, "nothing typed is cut")
        XCTAssertTrue(model.flush())
    }

    func testCapCountsBytesNotCharacters() {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        // "é" is 2 bytes in UTF-8.
        let half = String(repeating: "é", count: TodayEditorModel.maxBytes / 2)
        XCTAssertTrue(model.edit(half))
        XCTAssertFalse(model.edit(half + "éé"))
    }

    // Criterion 4: delete, recorded as a tombstone.
    func testDeleteLeavesATombstoneWithoutText() throws {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        model.edit("to delete")
        model.flush()
        try model.deleteReflection()
        XCTAssertEqual(model.text, "")
        let row = try XCTUnwrap(repo.entry(for: "2026-11-21"))
        XCTAssertNotNil(row.deletedAt)
        XCTAssertEqual(row.notesText, "")
        XCTAssertEqual(row.dateString, "2026-11-21", "d tag kept for NIP-09 in M5")
        XCTAssertEqual(try repo.text(for: day("2026-11-21")), "")
    }

    func testWritingAfterDeleteRestoresTheDay() throws {
        let model = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        model.edit("first"); model.flush()
        try model.deleteReflection()
        model.edit("again"); model.flush()
        let row = try XCTUnwrap(repo.entry(for: "2026-11-21"))
        XCTAssertNil(row.deletedAt)
        XCTAssertEqual(row.notesText, "again")
    }

    // Criterion 8: "Welcome back." after 2+ days without a reflection.
    func testWelcomeBackAfterAGapOfTwoDays() throws {
        try repo.save(text: "x", for: day("2026-11-18"))
        XCTAssertTrue(TodayEditorModel(repository: repo, day: day("2026-11-21")).showWelcomeBack)
    }

    func testNoWelcomeBackAfterOneMissedDayOrForNewUsers() throws {
        XCTAssertFalse(TodayEditorModel(repository: repo, day: day("2026-11-21")).showWelcomeBack, "no history")
        try repo.save(text: "x", for: day("2026-11-19"))
        XCTAssertFalse(TodayEditorModel(repository: repo, day: day("2026-11-21")).showWelcomeBack)
    }

    func testDeletedDaysDoNotCountForWelcomeBack() throws {
        try repo.save(text: "x", for: day("2026-11-15"))
        try repo.save(text: "y", for: day("2026-11-20"))
        try repo.delete(day("2026-11-20"))
        XCTAssertTrue(TodayEditorModel(repository: repo, day: day("2026-11-21")).showWelcomeBack)
    }

    // Audit M2 L2: one value carries the day and its zone.
    func testStoredTimeZoneIsTheOneTheDayWasComputedIn() throws {
        let tokyo = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        let entry = try repo.save(text: "x", for: tokyo)
        XCTAssertEqual(entry.timeZoneID, "Asia/Tokyo")
        XCTAssertEqual(JournalRepository.day(of: entry), tokyo.day)
    }
}

/// Audit M2 I1: a failed save (for example, the device locked) never loses
/// text and never moves it to the wrong day.
@MainActor
final class TodayEditorFailureTests: XCTestCase {
    struct Locked: Error {}
    private let zone = TimeZone(identifier: "America/Chicago")!

    /// Held for the test's lifetime: a context outlived by its container crashes.
    private var container: ModelContainer!

    private func makeRepo() throws -> JournalRepository {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        return JournalRepository(context: container.mainContext)
    }

    func testFailedSaveKeepsTextAndTheNextFlushRetries() throws {
        let repo = try makeRepo()
        var locked = true
        let today = TodayEditorModel.parse("2026-11-21", timeZone: zone)!
        let model = TodayEditorModel(repository: repo, day: today, save: { text, day in
            if locked { throw Locked() }
            try repo.save(text: text, for: day)
        })
        model.edit("grateful for this")
        XCTAssertFalse(model.flush())
        XCTAssertEqual(model.text, "grateful for this")
        XCTAssertEqual(model.saveError, DraftBuffer.saveFailedMessage)
        XCTAssertTrue(model.hasUnsavedChanges)

        locked = false  // unlocked: the foreground flush succeeds
        XCTAssertTrue(model.flush())
        XCTAssertNil(model.saveError)
        XCTAssertEqual(try repo.text(for: today), "grateful for this")
    }

    func testMidnightWithAFailedSaveStaysOnTheStartedDay() throws {
        let repo = try makeRepo()
        var locked = true
        let started = TodayEditorModel.parse("2026-11-21", timeZone: zone)!
        let next = TodayEditorModel.parse("2026-11-22", timeZone: zone)!
        let model = TodayEditorModel(repository: repo, day: started, save: { text, day in
            if locked { throw Locked() }
            try repo.save(text: text, for: day)
        })
        model.edit("late-night thought")
        model.dayChanged(to: next)
        XCTAssertEqual(model.day, started, "text is never attached to the new day")
        XCTAssertEqual(model.text, "late-night thought")

        locked = false
        model.dayChanged(to: next)
        XCTAssertEqual(try repo.text(for: started), "late-night thought")
        XCTAssertEqual(model.day, next)
        XCTAssertEqual(model.text, "")
    }
}
