import XCTest
import CryptoKit
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

    /// AC 6, text parity: the bundled lines are exactly the web's 366, in
    /// order, byte for byte, from the recorded commit. The hash is the one
    /// gen.ts printed from the web array; Audit regenerates it independently.
    func testItemsAreTheWebTextFromTheRecordedCommit() throws {
        let lib = try AffirmationLibrary.bundled()
        XCTAssertEqual(lib.sourceCommit, "2b15ce6")
        let digest = SHA256.hash(data: Data(lib.items.joined(separator: "\n").utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, lib.itemsSha256, "items edited without re-export")
        XCTAssertEqual(hex, "8272031d8a8113c4194234d878ea6c473a7d6c200e5efc2ccdd4fb8c32d21ac1")
    }

    /// AC 7: the pick depends only on the date string, never the device's
    /// calendar, zone or locale. Year ends and the 2028 leap day, against the
    /// web fixture.
    func testDateBoundariesMatchTheWeb() throws {
        let lib = try AffirmationLibrary.bundled()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "affirmation_samples", withExtension: "json", subdirectory: "Fixtures"))
        let rows = try JSONDecoder().decode(Samples.self, from: Data(contentsOf: url)).rows
        let web = Dictionary(uniqueKeysWithValues: rows.map { ($0.date, $0.index) })
        for date in ["2026-12-31", "2027-01-01", "2027-12-31", "2028-01-01", "2028-02-28", "2028-02-29", "2028-03-01", "2028-12-31",
                     "2026-03-08", "2026-11-01", "2026-03-29", "2026-10-25"] {   // US and EU DST days
            XCTAssertEqual(lib.index(forDate: date), web[date], date)
        }
        XCTAssertEqual(AffirmationLibrary.yearAndDayOfYear("2028-03-01")?.1, 61)
        XCTAssertEqual(AffirmationLibrary.yearAndDayOfYear("2027-03-01")?.1, 60)
    }
}
