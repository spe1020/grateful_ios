import XCTest
import SwiftUI
import GratefulDayCore
@testable import GratefulDay

/// D9: "Carry it with you" must never be squeezed, whatever the day's
/// passage. CI's text-clipped audit caught it only on dates whose card laid
/// out tight (11-28, not 11-27), so this lays out the real Today card for
/// every scheduled passage instead of today's alone.
@MainActor
final class WisdomCardLayoutTests: XCTestCase {
    /// Collects what the label reports while one card is laid out.
    private final class Box: @unchecked Sendable { var size: CGSize? }

    func testCarryItWithYouGetsItsFullHeightForEveryPassage() throws {
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

        // Narrow, common and wide iPhones, at the sizes where the label wraps.
        let cases: [(DynamicTypeSize, CGFloat)] = [(.accessibility5, 375), (.accessibility5, 402), (.accessibility5, 440), (.accessibility3, 375)]
        for (size, width) in cases {
            var squeezed: [String] = []
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
                .environment(\.wisdomLabelLayout) { box.size = $0 }
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 874))
                window.rootViewController = UIHostingController(rootView: root)
                window.makeKeyAndVisible()
                window.layoutIfNeeded()
                if box.size == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
                window.isHidden = true

                // Fails closed: a label that never reported counts as squeezed.
                guard let laidOut = box.size else { squeezed.append("\(day.dateString) \(item.id) (no layout)"); continue }
                let full = UIHostingController(rootView: Text("Carry it with you").font(GDFont.sectionLabel).dynamicTypeSize(size))
                    .sizeThatFits(in: CGSize(width: laidOut.width, height: .greatestFiniteMagnitude)).height
                if laidOut.height < full - 0.5 {
                    squeezed.append("\(day.dateString) \(item.id) (\(laidOut.height) of \(full) pt)")
                }
            }
            XCTAssertTrue(squeezed.isEmpty, "\(size) at \(Int(width)) pt: \"Carry it with you\" squeezed on \(squeezed.count) of \(days.count) days, first: \(squeezed.prefix(5).joined(separator: "; "))")
        }
    }
}
