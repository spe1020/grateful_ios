import XCTest
import CryptoKit
import SwiftUI
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
        XCTAssertEqual(TodayCardSelection.page(stored: "2026-11-23|readers", today: "2026-11-23", pageIds: ids), "wisdom",
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

    /// Every file in the built app, minus the hosted test bundle (the
    /// `.xctest` Xcode copies into PlugIns only to run these tests; it never
    /// ships, and it holds `readers_guard.json`).
    private static func appFiles() throws -> [URL] {
        let app = Bundle(for: JournalStore.self).bundleURL
        let all = try XCTUnwrap(FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        return all.filter { !$0.pathComponents.contains { $0.hasSuffix(".xctest") } }
    }

    /// Criterion 8: nothing from the web's teachings ships in the app. Walks
    /// the built app bundle, including GratefulDayCore's resource bundle.
    func testNoTeachingDataInTheAppBundle() throws {
        let urls = try Self.appFiles()
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "affirmations.json" }, "the walk reaches the core resources")
        XCTAssertFalse(urls.contains { $0.lastPathComponent.lowercased().contains("teaching") })
        for url in urls where url.pathExtension == "json" {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("scriptureQuote"), url.lastPathComponent)
        }
    }

    /// Spec 1–3 / AC 1: the page list is Wisdom then Affirmation, and no
    /// Daily Readers page exists even when the type list names it.
    func testPagesAreWisdomThenAffirmationAndNeverReaders() {
        XCTAssertEqual(TodayCardKind.allCases, [.wisdom, .affirmation, .readers])
        let both = TodayCardPage.pages(wisdom: AnyView(EmptyView()), affirmation: AnyView(EmptyView()))
        XCTAssertEqual(both.map(\.kind), [.wisdom, .affirmation])
        XCTAssertEqual(both.map(\.label), ["Daily Wisdom", "Daily Affirmation"])
        XCTAssertEqual(TodayCardPage.pages(wisdom: nil, affirmation: AnyView(EmptyView())).map(\.kind), [.affirmation],
                       "a missing page leaves no gap")
        XCTAssertTrue(TodayCardPage.pages(wisdom: nil, affirmation: nil).isEmpty)
    }

    /// AC 7: the journal's date string (and so the pick) is Gregorian in the
    /// zone, whatever calendar the device uses (Buddhist year 2569, Japanese
    /// Reiwa 8 for 2026).
    func testDateStringIgnoresTheDeviceCalendar() {
        let instant = ISO8601DateFormatter().date(from: "2026-11-23T18:00:00Z")!
        let day = JournalDay(containing: instant, timeZone: zone)
        XCTAssertEqual(day.dateString, "2026-11-23")
        for id in [Calendar.Identifier.buddhist, .japanese] {
            var cal = Calendar(identifier: id); cal.timeZone = zone
            XCTAssertNotEqual(cal.component(.year, from: instant), 2026, "the device calendar differs")
        }
        XCTAssertEqual(DailyAffirmation.text(for: day), DailyAffirmation.library?.items[192])
    }

    // MARK: - No Daily Readers text in the app (spec AC 11)

    struct Guard: Decodable { let gram: Int; let whole: [String]; let grams: [String] }

    /// gen.ts `readers-guard` normalisation: lower-case, NFKD, every run of
    /// anything but a letter or number (combining marks included, as JS
    /// `\p{L}\p{N}` excludes them) becomes one space, trimmed.
    private static let kept = CharacterSet.alphanumerics.subtracting(.nonBaseCharacters)

    private static func norm(_ t: String) -> String {
        let folded = t.lowercased().decomposedStringWithCompatibilityMapping
        var out = ""; var space = false
        for u in folded.unicodeScalars {
            if kept.contains(u) {
                if space && !out.isEmpty { out.append(" ") }
                space = false; out.unicodeScalars.append(u)
            } else { space = true }
        }
        return out
    }

    private static func h(_ t: String) -> String {
        SHA256.hash(data: Data(t.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Every string value in a JSON document.
    private static func strings(in json: Any) -> [String] {
        switch json {
        case let s as String: return [s]
        case let a as [Any]: return a.flatMap(strings(in:))
        case let d as [String: Any]: return d.flatMap { [$0.key] + strings(in: $0.value) }
        default: return []
        }
    }

    /// Strings in `text` that match a web teaching's title, body or quote
    /// (whole field, or any run of `gram` words).
    ///
    /// A whole-field match counts only from 3 words up: single words such as
    /// "patience" are Wisdom theme names and teaching titles alike.
    /// `approvedOverlaps` lists bundled strings (by hash of the normalised
    /// value) that share words with a teaching but are approved content with
    /// recorded provenance.
    static let approvedOverlaps: [String: String] = [
        // wisdom.json dhammapada-63-v2: Max Müller (1881, public domain),
        // which shares 8 words with a teaching's quote of the same verse.
        "d4e0a0910ee6c0d1": "Dhammapada 63, F. Max Müller, wisdom.json provenance",
    ]

    static func readersMatches(in text: String, guard g: Guard) -> [String] {
        let whole = Set(g.whole), grams = Set(g.grams)
        let values = (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]))
            .map(strings(in:)) ?? [text]
        return values.filter { v in
            let n = norm(v)
            guard !n.isEmpty, approvedOverlaps[h(n)] == nil else { return false }
            let w = n.split(separator: " ")
            if w.count >= 3, whole.contains(h(n)) { return true }
            guard w.count >= g.gram else { return false }
            return (0...(w.count - g.gram)).contains { grams.contains(h(w[$0..<($0 + g.gram)].joined(separator: " "))) }
        }
    }

    private func readersGuard() throws -> Guard {
        let url = try XCTUnwrap(Bundle(for: TodayCardTests.self).url(forResource: "readers_guard", withExtension: "json"))
        let g = try JSONDecoder().decode(Guard.self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(g.grams.count, 10_000, "the guard covers all 252 teachings")
        return g
    }

    /// Scans every text resource in the built app (and GratefulDayCore's
    /// bundle inside it) against hashes of the web's teachings. The test
    /// bundle holds hashes only, never the text.
    func testNoReadersTextInTheAppBundle() throws {
        let g = try readersGuard()
        let urls = try Self.appFiles()
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "affirmations.json" }, "the walk reaches the core resources")
        XCTAssertTrue(urls.contains { $0.lastPathComponent == "wisdom.json" })
        XCTAssertFalse(urls.contains { $0.lastPathComponent.lowercased().contains("teaching") })
        var scanned = 0
        for url in urls where ["json", "strings", "txt", "plist", "md"].contains(url.pathExtension) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            XCTAssertEqual(Self.readersMatches(in: text, guard: g), [], url.lastPathComponent)
        }
        XCTAssertGreaterThanOrEqual(scanned, 2)
    }

    /// The guard catches a planted line, even re-cased and re-punctuated.
    /// No teaching text may sit in the test bundle, so the planted line's hash
    /// goes into a copy of the guard. (Audit plants a real quote by hand.)
    func testGuardCatchesAPlantedLine() throws {
        let g = try readersGuard()
        let line = "a planted line of eight or more words for the guard test"
        let words = Self.norm(line).split(separator: " ")
        let planted = Guard(gram: g.gram, whole: g.whole, grams: g.grams + [Self.h(words[2..<10].joined(separator: " "))])
        let json = #"{"items": ["fine", "A  PLANTED line, of eight -- or more words; for the guard test!"]}"#
        XCTAssertEqual(Self.readersMatches(in: json, guard: planted).count, 1)
        XCTAssertEqual(Self.readersMatches(in: json, guard: g), [])
    }
}
