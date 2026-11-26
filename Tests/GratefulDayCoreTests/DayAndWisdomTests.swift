import XCTest
@testable import GratefulDayCore

final class DayAndWisdomTests: XCTestCase {
    struct Dates: Decodable {
        struct Zone: Decodable { let tz: String; let rows: [Row] }
        struct Row: Decodable { let instant: Int; let d: String; let day: Int; let published_at: Int; let alt: String }
        let zones: [Zone]
    }

    /// Same instant, six zones (UTC−10 to UTC+14): d, day, published_at and the
    /// alt text all match web's gratitudeUtils.
    func testDayMatchesWebInEveryZone() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web_dates", withExtension: "json", subdirectory: "Fixtures"))
        let dates = try JSONDecoder().decode(Dates.self, from: Data(contentsOf: url))
        XCTAssertEqual(dates.zones.count, 6)
        for zone in dates.zones {
            let tz = try XCTUnwrap(TimeZone(identifier: zone.tz))
            for r in zone.rows {
                let day = DailyEntry.Day(containing: Date(timeIntervalSince1970: TimeInterval(r.instant)), timeZone: tz)
                let label = "\(zone.tz) @ \(r.instant)"
                XCTAssertEqual(day.dateString, r.d, label)
                XCTAssertEqual(day.dayOfYear, r.day, label)
                XCTAssertEqual(day.publishedAt, r.published_at, label)
                XCTAssertEqual("Daily reflection entry for \(day.displayDate) (Day \(day.dayOfYear))", r.alt, label)
            }
        }
    }

    struct Samples: Decodable { struct Row: Decodable { let date: String; let id: String? }; let rows: [Row] }

    /// Every local date from 2026-09-01 to 2027-12-31 picks the same wisdom item as web.
    func testWisdomSelectionMatchesWebForEveryDate() throws {
        let lib = try WisdomLibrary.bundled()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "wisdom_samples", withExtension: "json", subdirectory: "Fixtures"))
        let samples = try JSONDecoder().decode(Samples.self, from: Data(contentsOf: url))
        XCTAssertEqual(samples.rows.count, 487)
        for r in samples.rows { XCTAssertEqual(lib.item(forDate: r.date)?.id, r.id, r.date) }
    }

    func testEveryScheduledWisdomItemExists() throws {
        let lib = try WisdomLibrary.bundled()
        for s in lib.schedules { for id in s.itemIds { XCTAssertNotNil(lib.items[id], id) } }
        XCTAssertFalse(lib.items.isEmpty)
    }

    /// Spec §1.8: a day rebuilt from stored identity keeps every web-computed
    /// field, in every zone, including the alt text's date.
    func testDayFromStoredIdentityMatchesWeb() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "web_dates", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Dates.self, from: Data(contentsOf: url))
        for zone in fixture.zones {
            for row in zone.rows {
                let day = try XCTUnwrap(DailyEntry.Day(dateString: row.d, dayOfYear: row.day, publishedAt: row.published_at))
                XCTAssertEqual(day.dateString, row.d)
                XCTAssertEqual(day.dayOfYear, row.day)
                XCTAssertEqual(day.publishedAt, row.published_at)
                let event = try DailyEntry.template(day: day, notes: ["x"])
                XCTAssertEqual(event.tags.first { $0.first == "alt" }?[1], row.alt, "\(zone.tz) \(row.d)")
            }
        }
        XCTAssertNil(DailyEntry.Day(dateString: "2026-02-30", dayOfYear: 61, publishedAt: 1))
        XCTAssertNil(DailyEntry.Day(dateString: "2026-02-01", dayOfYear: 0, publishedAt: 1))
    }
}
