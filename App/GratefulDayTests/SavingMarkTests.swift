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

    func testMarks() {
        row("2026-11-18", "saved", owner: owner, state: .synced)
        row("2026-11-19", "unsent", owner: owner)
        row("2026-11-20", "written before connecting", owner: nil)
        row("2026-11-21", "both", owner: owner, state: .conflict)
        row("2026-11-22", "", owner: owner, deleted: true)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertEqual(repo.dayMark("2026-11-18"), .none)
        XCTAssertEqual(repo.dayMark("2026-11-19"), .saving)
        XCTAssertEqual(repo.dayMark("2026-11-20"), .saving, "a guest day isn't saved yet")
        XCTAssertEqual(repo.dayMark("2026-11-21"), .saving)
        XCTAssertEqual(repo.dayMark("2026-11-22"), .none)
        XCTAssertEqual(repo.dayMark("2026-11-23"), .none, "nothing written")
        XCTAssertEqual(JournalRepository(context: context, activeOwner: nil).dayMark("2026-11-19"), .localOnly)
        XCTAssertEqual(try repo.savingDates(from: "2026-11-01", through: "2026-11-30"), ["2026-11-19", "2026-11-20", "2026-11-21"])
    }

    func testGuestDayAlreadySavedByTheAccountShowsNothing() {
        row("2026-11-20", "same", owner: owner, state: .synced)
        row("2026-11-20", "same", owner: nil)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertEqual(repo.dayMark("2026-11-20"), .none)
        XCTAssertEqual(try repo.savingDates(from: "2026-11-01", through: "2026-11-30"), [])
    }

    func testLongSavingCountsAfterSevenDays() throws {
        let now = t0.addingTimeInterval(8 * 86_400)
        row("2026-11-10", "old", owner: owner, updated: t0)
        row("2026-11-11", "old but saved", owner: owner, state: .synced, updated: t0)
        row("2026-11-17", "recent", owner: owner, updated: now.addingTimeInterval(-86_400))
        XCTAssertEqual(try JournalRepository(context: context, activeOwner: owner).longSavingCount(now: now), 1)
        XCTAssertEqual(SyncCopy.longSaving(3), "3 reflections haven't finished saving to your account yet. We'll keep trying.")
    }

    func testSavingDetailText() {
        let sync = SyncService()
        XCTAssertEqual(SyncService.savingDetail(sync),
                       "This reflection hasn't finished saving to your account. It's kept on this iPhone, and we'll keep trying.")
        let long = String(repeating: "a", count: DailyEntry.maxContentBytes + 1)
        XCTAssertEqual(SyncService.savingDetail(sync, text: long, isToday: true), ConflictCopy.dayLine(.tooLong(isToday: true)))
        XCTAssertEqual(SyncCopy.savingVoiceOver, "Not saved to your account yet")
    }
}
