import XCTest
import GratefulDayCore
@testable import GratefulDay

/// Today card (Prep spec 2026-11-23): affirmation selection, page memory and
/// what ships in the bundle.
@MainActor
final class TodayCardTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Chicago")!
    private func day(_ s: String) -> JournalDay { TodayEditorModel.parse(s, timeZone: zone)! }

    /// Criteria 4–5: bundled (works offline) and the same line web shows.
    func testAffirmationUsesTheWebRotationForTheLocalDate() throws {
        let library = try XCTUnwrap(DailyAffirmation.library, "bundled, works offline")
        XCTAssertEqual(DailyAffirmation.text(for: day("2026-11-23")), library.items[192])
        XCTAssertEqual(DailyAffirmation.text(for: day("2028-02-29")), library.items[361])
        XCTAssertNotEqual(DailyAffirmation.text(for: day("2026-11-23")), DailyAffirmation.text(for: day("2026-11-24")))
    }

    /// Criterion 7: a new day opens on the first page (Wisdom); within a day
    /// the stored page is kept.
    func testEachDayOpensOnWisdomAndKeepsThePageWithinTheDay() {
        let ids = ["wisdom", "affirmation"]
        XCTAssertEqual(TodayCardSelection.page(stored: nil, today: "2026-11-23", pageIds: ids), "wisdom")
        XCTAssertEqual(TodayCardSelection.page(stored: "", today: "2026-11-23", pageIds: ids), "wisdom")
        let kept = TodayCardSelection.stored(today: "2026-11-23", pageId: "affirmation")
        XCTAssertEqual(TodayCardSelection.page(stored: kept, today: "2026-11-23", pageIds: ids), "affirmation")
        XCTAssertEqual(TodayCardSelection.page(stored: kept, today: "2026-11-24", pageIds: ids), "wisdom", "new day")
        XCTAssertEqual(TodayCardSelection.page(stored: "2026-11-23|teaching", today: "2026-11-23", pageIds: ids), "wisdom",
                       "a page that isn't offered falls back to the first")
        XCTAssertEqual(TodayCardSelection.page(stored: kept, today: "2026-11-23", pageIds: ["affirmation"]), "affirmation")
        XCTAssertNil(TodayCardSelection.page(stored: kept, today: "2026-11-23", pageIds: []))
    }

    /// VoiceOver's adjust (criterion 2) moves one page and doesn't wrap.
    func testAdjustStepsOnePageWithoutWrapping() {
        XCTAssertEqual(TodayCardSelection.step(from: 0, by: 1, count: 2), 1)
        XCTAssertEqual(TodayCardSelection.step(from: 1, by: 1, count: 2), 1)
        XCTAssertEqual(TodayCardSelection.step(from: 1, by: -1, count: 2), 0)
        XCTAssertEqual(TodayCardSelection.step(from: 0, by: -1, count: 2), 0)
        XCTAssertEqual(TodayCardSelection.step(from: 1, by: 1, count: 3), 2, "a third page is one more entry")
        XCTAssertEqual(TodayCardSelection.step(from: 0, by: 1, count: 0), 0)
    }

    /// Spec Q1: no card title until Seth picks one; pages carry their labels.
    func testNoCardTitleAndPageLabels() {
        XCTAssertNil(TodayCardCopy.title)
        XCTAssertEqual(TodayCardCopy.wisdomLabel, "Daily Wisdom")
        XCTAssertEqual(TodayCardCopy.affirmationLabel, "Daily Affirmation")
    }

    /// Criterion 8: nothing from the web's teachings ships in the app. Walks
    /// the built app bundle, including GratefulDayCore's resource bundle.
    func testNoTeachingDataInTheAppBundle() throws {
        let app = Bundle(for: JournalStore.self).bundleURL
        let urls = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "affirmations.json" }, "the walk reaches the core resources")
        XCTAssertFalse(urls.contains { $0.lastPathComponent.lowercased().contains("teaching") })
        for url in urls where url.pathExtension == "json" {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("scriptureQuote"), url.lastPathComponent)
        }
    }
}
