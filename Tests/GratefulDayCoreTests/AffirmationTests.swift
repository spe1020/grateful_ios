import XCTest
@testable import GratefulDayCore

final class AffirmationTests: XCTestCase {
    struct Samples: Decodable { struct Row: Decodable { let date: String; let index: Int }; let rows: [Row] }

    /// Today card criterion 4: every local date from 2026-01-01 to 2028-12-31
    /// picks the same affirmation as web's `getAffirmationForDay`.
    func testAffirmationSelectionMatchesWebForEveryDate() throws {
        let lib = try AffirmationLibrary.bundled()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "affirmation_samples", withExtension: "json", subdirectory: "Fixtures"))
        let samples = try JSONDecoder().decode(Samples.self, from: Data(contentsOf: url))
        XCTAssertEqual(samples.rows.count, 1096)
        XCTAssertEqual(samples.rows.first?.date, "2026-01-01")
        XCTAssertEqual(samples.rows.last?.date, "2028-12-31")
        for r in samples.rows {
            XCTAssertEqual(lib.index(forDate: r.date), r.index, r.date)
            XCTAssertEqual(lib.affirmation(forDate: r.date), lib.items[r.index], r.date)
        }
    }

    /// Research §1.1 reference rows, independent of the fixture file.
    func testReferenceRows() throws {
        let lib = try AffirmationLibrary.bundled()
        let expected = ["2026-01-01": 116, "2026-11-23": 192, "2026-12-31": 10, "2028-02-29": 361, "2028-12-31": 109]
        for (date, index) in expected { XCTAssertEqual(lib.index(forDate: date), index, date) }
    }

    func testBundledLibraryHas366DistinctLines() throws {
        let lib = try AffirmationLibrary.bundled()
        XCTAssertEqual(lib.items.count, 366)
        XCTAssertEqual(Set(lib.items).count, 366)
        XCTAssertFalse(lib.items.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    func testInvalidDatesHaveNoAffirmation() throws {
        let lib = try AffirmationLibrary.bundled()
        for bad in ["", "2026-02-30", "2027-02-29", "2026-13-01", "not-a-date", "2026-11"] {
            XCTAssertNil(lib.affirmation(forDate: bad), bad)
        }
    }

    /// The day of year is Gregorian whatever the user's calendar is
    /// (Buddhist, Japanese), because it never reads `Calendar.current`.
    func testDayOfYearIsGregorian() {
        XCTAssertEqual(AffirmationLibrary.yearAndDayOfYear("2028-12-31")?.1, 366)
        XCTAssertEqual(AffirmationLibrary.yearAndDayOfYear("2026-12-31")?.1, 365)
        XCTAssertEqual(AffirmationLibrary.yearAndDayOfYear("2028-02-29")?.1, 60)
        XCTAssertEqual(AffirmationLibrary.yearAndDayOfYear("2026-11-23")?.0, 2026)
    }

    /// Acceptance criterion 8: no teaching data ships until each quote's
    /// source is recorded (Chief P48). The app-level check walks the built
    /// app (`TodayCardTests`).
    func testNoTeachingDataInTheCoreBundle() throws {
        let urls = try XCTUnwrap(FileManager.default.enumerator(at: AffirmationLibrary.resourceBundle.bundleURL,
                                                                includingPropertiesForKeys: nil)?.allObjects as? [URL])
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "affirmations.json" })
        XCTAssertFalse(urls.contains { $0.lastPathComponent.lowercased().contains("teaching") }, "\(urls)")
    }
}
