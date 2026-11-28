import XCTest
import SwiftUI
import GratefulDayCore
@testable import GratefulDay

/// D9 and D11: no text on the Wisdom card may be squeezed below its full
/// height, whatever the day's passage. CI's text-clipped audit caught D9 only
/// on dates whose card laid out tight (11-28, not 11-27), so this lays out the
/// real Today card for every scheduled passage instead of today's alone.
///
/// Sizes are read from the settled layout (Prep, P221): after the first pass
/// the card resizes to its tallest page, and that later pass is where a text
/// gets squeezed.
@MainActor
final class WisdomCardLayoutTests: XCTestCase {
    /// The last size each measured text reported while one card was laid out.
    private final class Box: @unchecked Sendable { var sizes: [WisdomCardLayoutPart: CGSize] = [:] }

    func testCardTextsGetTheirFullHeightForEveryPassage() throws {
        XCTAssertNotNil(DailyWisdom.library, "bundled")
        let zone = TimeZone(identifier: "UTC")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        // The current schedule (from 2026-09-22) holds every passage once.
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22)))
        var days: [JournalDay] = []
        var ids = Set<String>()
        for offset in 0..<1000 {
            let day = JournalDay(containing: calendar.date(byAdding: .day, value: offset, to: start)!, timeZone: zone)
            guard let item = DailyWisdom.item(for: day) else { continue }
            if !ids.insert(item.id).inserted { break }
            days.append(day)
        }
        XCTAssertEqual(days.count, 465, "one full cycle of the schedule")

        // Narrow, common and wide iPhones, at the sizes where these texts wrap.
        let cases: [(DynamicTypeSize, CGFloat)] = [(.accessibility5, 375), (.accessibility5, 402), (.accessibility5, 440), (.accessibility3, 375)]
        for (size, width) in cases {
            var squeezed: [WisdomCardLayoutPart: [String]] = [.carryLabel: [], .sourceLink: []]
            for day in days {
                let item = try XCTUnwrap(DailyWisdom.item(for: day))
                let box = Box()
                let pages = TodayCardPage.pages(
                    wisdom: AnyView(WisdomCard(item: item, isPinned: false) {}),
                    affirmation: DailyAffirmation.text(for: day).map { AnyView(AffirmationPage(text: $0)) })
                // As Today shows it: a vertical scroll view, the card inset by
                // the screen margin.
                let root = ScrollView {
                    TodayCard(pages: pages, selection: .constant(nil))
                        .padding(.horizontal, GDSpacing.medium)
                }
                .dynamicTypeSize(size)
                .environment(\.wisdomCardLayout) { part, laidOut in box.sizes[part] = laidOut }
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 874))
                window.rootViewController = UIHostingController(rootView: root)
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                // Let the card settle at its tallest page, then lay out again.
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                window.layoutIfNeeded()
                window.isHidden = true

                var expected: [(WisdomCardLayoutPart, Text)] = [
                    (.carryLabel, Text("Carry it with you").font(GDFont.sectionLabel)),
                ]
                if let p = item.provenance, URL(string: p.url) != nil {
                    expected.append((.sourceLink, Text(p.location).font(.caption).underline()))
                }
                for (part, text) in expected {
                    // Fails closed: a text that never reported counts as squeezed.
                    guard let laidOut = box.sizes[part] else {
                        squeezed[part, default: []].append("\(day.dateString) \(item.id) (no layout)")
                        continue
                    }
                    let full = UIHostingController(rootView: text.dynamicTypeSize(size))
                        .sizeThatFits(in: CGSize(width: laidOut.width, height: .greatestFiniteMagnitude)).height
                    if laidOut.height < full - 0.5 {
                        squeezed[part, default: []].append("\(day.dateString) \(item.id) (\(laidOut.height) of \(full) pt)")
                    }
                }
            }
            for (part, name) in [(WisdomCardLayoutPart.carryLabel, "\"Carry it with you\""), (.sourceLink, "the source link")] {
                let hits = squeezed[part] ?? []
                // Names every day that failed, so a run shows which passages hit.
                for hit in hits { print("WISDOM-LAYOUT-SQUEEZED \(part) \(size) w=\(Int(width)) \(hit)") }
                XCTAssertTrue(hits.isEmpty, "\(size) at \(Int(width)) pt: \(name) squeezed on \(hits.count) of \(days.count) days, first: \(hits.prefix(5).joined(separator: "; "))")
            }
        }
    }
}
