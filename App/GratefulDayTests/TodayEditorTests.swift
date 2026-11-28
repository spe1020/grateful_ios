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

    // MARK: - D8: the save timer (Chief P208)

    private func day(_ dateString: String) -> JournalDay {
        TodayEditorModel.parse(dateString, timeZone: zone)!
    }

    /// The save timer's wait, under the test's control: a sleep ends only
    /// when `advance` passes its deadline, or when its task is cancelled.
    @MainActor
    private final class ManualSleeper {
        private(set) var now: Duration = .zero
        private var waiting: [(id: Int, deadline: Duration, resume: CheckedContinuation<Void, Error>)] = []
        private var cancelled: Set<Int> = []
        private var nextID = 0
        var waitingCount: Int { waiting.count }

        func sleep(_ duration: Duration) async throws {
            let id = nextID; nextID += 1
            let deadline = now + duration
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    if cancelled.contains(id) { c.resume(throwing: CancellationError()) } else { waiting.append((id, deadline, c)) }
                }
            } onCancel: {
                Task { @MainActor in self.cancel(id) }
            }
        }

        private func cancel(_ id: Int) {
            cancelled.insert(id)
            if let i = waiting.firstIndex(where: { $0.id == id }) { waiting.remove(at: i).resume.resume(throwing: CancellationError()) }
        }

        /// Move time on, end every sleep that is due, and let woken tasks run.
        /// Tasks armed since the last call get to start (and so call `sleep`
        /// at the current time) before time moves.
        func advance(_ duration: Duration) async {
            await settle()
            now += duration
            let due = waiting.filter { $0.deadline <= now }
            waiting.removeAll { $0.deadline <= now }
            for w in due { w.resume.resume() }
            await settle()
        }

        /// Tasks run on the main actor once this one suspends; a short real
        /// wait lets them (Task.yield alone wasn't enough).
        func settle() async {
            for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(10)) }
        }
    }

    /// D8: steady typing (an edit every 0.3 s for 2 s) is saved while it
    /// goes on, at most 0.5 s after the first unsaved edit. Before the fix
    /// every keystroke restarted the timer, so nothing was saved until
    /// typing paused, and a kill (which gives no notice) lost all of it.
    func testSteadyTypingIsSavedBeforeItPauses() async throws {
        let repo = try makeRepo()
        let sleeper = ManualSleeper()
        let today = day("2026-11-21")
        var saves: [(at: Duration, text: String)] = []
        let model = TodayEditorModel(repository: repo, day: today, save: { text, day in
            try repo.save(text: text, for: day)
            saves.append((sleeper.now, text))
        }, sleep: { try await sleeper.sleep($0) })

        var typed = ""
        for i in 0..<7 {          // edits at 0.0, 0.3, … 1.8 s
            if i > 0 { await sleeper.advance(.milliseconds(300)) }
            typed += "word\(i) "
            model.edit(typed)
        }
        // At the last edit (1.8 s), earlier typing must already be on disk.
        guard let first = saves.first else {
            return XCTFail("nothing was saved while typing went on")
        }
        XCTAssertLessThanOrEqual(first.at, .milliseconds(600), "first save at most 0.5 s after the first edit (plus one 0.3 s step)")
        XCTAssertEqual(first.text, "word0 word1 ", "the first save holds what was typed by 0.5 s")
        XCTAssertFalse(try repo.text(for: today).isEmpty)
        for pair in zip(saves, saves.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.1.at - pair.0.at, .milliseconds(600), "no gap of more than one step past 0.5 s between saves")
        }

        // After the last edit, the rest is saved within 0.5 s.
        await sleeper.advance(.milliseconds(500))
        XCTAssertEqual(try repo.text(for: today), EntryNotes.normalize(typed))
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertEqual(sleeper.waitingCount, 0, "no timer left armed once everything is saved")
    }

    /// D8 / P208 part 2: a flush whose write fails doesn't drop the save that
    /// was waiting; that save still runs and gets the text on disk.
    func testFailedFlushKeepsTheWaitingSave() async throws {
        let repo = try makeRepo()
        let sleeper = ManualSleeper()
        var locked = true
        let today = day("2026-11-21")
        let model = TodayEditorModel(repository: repo, day: today, save: { text, day in
            if locked { throw Locked() }
            try repo.save(text: text, for: day)
        }, sleep: { try await sleeper.sleep($0) })

        model.edit("kept for later")
        await sleeper.advance(.milliseconds(100))
        XCTAssertFalse(model.flush(), "the write fails (for example, the device is locking)")
        XCTAssertEqual(sleeper.waitingCount, 1, "the waiting save is still armed")

        locked = false
        await sleeper.advance(.milliseconds(400))
        XCTAssertEqual(try repo.text(for: today), "kept for later", "the waiting save ran and saved")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertNil(model.saveError)
    }

    /// Audit a290daa9: a save timer whose write fails doesn't re-arm itself,
    /// so a day that can't be written isn't retried in a loop. The text stays
    /// in the editor, and the next edit, foreground or unlock retries.
    func testFailedTimerSaveDoesNotRetryInALoop() async throws {
        let repo = try makeRepo()
        let sleeper = ManualSleeper()
        var attempts = 0
        let today = day("2026-11-21")
        let model = TodayEditorModel(repository: repo, day: today, save: { _, _ in
            attempts += 1
            throw Locked()
        }, sleep: { try await sleeper.sleep($0) })

        model.edit("can't be written yet")
        for _ in 0..<5 { await sleeper.advance(.milliseconds(500)) }
        XCTAssertEqual(attempts, 1, "one attempt, then no loop")
        XCTAssertEqual(sleeper.waitingCount, 0)
        XCTAssertEqual(model.text, "can't be written yet")
        XCTAssertTrue(model.hasUnsavedChanges)

        model.edit("can't be written yet!")
        await sleeper.advance(.milliseconds(500))
        XCTAssertEqual(attempts, 2, "the next edit arms one new save")
    }
}
