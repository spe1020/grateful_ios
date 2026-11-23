import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Flows doc, "Incomplete sync: user experience": two user states, the
/// Saving mark and nothing, plus the 7-day Settings line.
@MainActor
final class SavingMarkTests: XCTestCase {
    private let owner = String(repeating: "a", count: 64)
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private func row(_ date: String, _ text: String, owner o: String?, state: SyncState = .localOnly,
                     updated: Date? = nil, deleted: Bool = false) {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let d = DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
        let r = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                             timeZoneID: zone.identifier, notesText: text, now: updated ?? t0, ownerPubkey: o)
        r.syncStateRaw = state.rawValue
        if deleted { r.deletedAt = t0 }
        context.insert(r)
        try? context.save()
    }

    private func accept() throws {
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
    }

    /// Prep's "Which days get the mark": only days the app is sending.
    func testMarks() throws {
        try accept()
        row("2026-11-17", "saved", owner: owner, state: .synced)
        row("2026-11-18", String(repeating: "a", count: DailyEntry.maxContentBytes + 1), owner: owner)
        row("2026-11-19", "unsent", owner: owner)
        row("2026-11-20", "written before connecting", owner: nil)
        row("2026-11-21", "both", owner: owner, state: .conflict)
        row("2026-11-22", "", owner: owner, deleted: true)
        row("2026-11-23", "can't compare", owner: owner, state: .blocked)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertEqual(repo.dayMark("2026-11-17"), .none)
        XCTAssertEqual(repo.dayMark("2026-11-18"), .none, "§8: too long shows its own line, no mark")
        XCTAssertEqual(repo.dayMark("2026-11-19"), .saving)
        XCTAssertEqual(repo.dayMark("2026-11-20"), .saving, "sorted and sent by the next pass")
        XCTAssertEqual(repo.dayMark("2026-11-21"), .none, "waiting on a choice: its own line")
        XCTAssertEqual(repo.dayMark("2026-11-22"), .none)
        XCTAssertEqual(repo.dayMark("2026-11-23"), .none, "blocked: its own line")
        XCTAssertEqual(repo.dayMark("2026-11-24"), .none, "nothing written")
        XCTAssertEqual(JournalRepository(context: context, activeOwner: nil).dayMark("2026-11-19"), .localOnly)
        XCTAssertEqual(try repo.savingDates(from: "2026-11-01", through: "2026-11-30"), ["2026-11-19", "2026-11-20"])
    }

    /// Before Continue (or after Not now) nothing is being sent: unsaved
    /// days stay "On this iPhone only" and the 7-day line counts nothing.
    func testBeforeAcceptanceUnsavedDaysAreOnThisIPhoneOnly() throws {
        row("2026-11-10", "unsent", owner: owner, updated: t0)
        row("2026-11-11", "guest", owner: nil, updated: t0)
        row("2026-11-12", "saved", owner: owner, state: .synced)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertEqual(repo.dayMark("2026-11-10"), .localOnly)
        XCTAssertEqual(repo.dayMark("2026-11-11"), .localOnly)
        XCTAssertEqual(repo.dayMark("2026-11-12"), .none)
        XCTAssertEqual(try repo.savingDates(from: "2026-11-01", through: "2026-11-30"), [])
        XCTAssertEqual(try repo.longSavingCount(now: t0.addingTimeInterval(30 * 86_400)), 0)
    }

    func testGuestDayAlreadySavedByTheAccountShowsNothing() throws {
        try accept()
        row("2026-11-20", "same", owner: owner, state: .synced)
        row("2026-11-20", "same", owner: nil)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertEqual(repo.dayMark("2026-11-20"), .none)
        XCTAssertEqual(try repo.savingDates(from: "2026-11-01", through: "2026-11-30"), [])
    }

    /// The 7-day line counts only days that get the mark.
    func testLongSavingCountsAfterSevenDays() throws {
        try accept()
        let now = t0.addingTimeInterval(8 * 86_400)
        row("2026-11-10", "old", owner: owner, updated: t0)
        row("2026-11-11", "old but saved", owner: owner, state: .synced, updated: t0)
        row("2026-11-12", "old conflict", owner: owner, state: .conflict, updated: t0)
        row("2026-11-13", String(repeating: "a", count: DailyEntry.maxContentBytes + 1), owner: owner, updated: t0)
        row("2026-11-17", "recent", owner: owner, updated: now.addingTimeInterval(-86_400))
        XCTAssertEqual(try JournalRepository(context: context, activeOwner: owner).longSavingCount(now: now), 1)
        XCTAssertEqual(SyncCopy.longSaving(3), "3 reflections haven't finished saving to your account yet. We'll keep trying.")
    }

    func testSavingDetailText() {
        let sync = SyncService()
        XCTAssertEqual(SyncService.savingDetail(sync),
                       "This reflection hasn't finished saving to your account. It's kept on this iPhone, and we'll keep trying.")
        XCTAssertEqual(SyncCopy.savingVoiceOver, "Not saved to your account yet")
    }
}
