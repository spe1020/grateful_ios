import XCTest
import SwiftData
import GratefulDayCore
@testable import GratefulDay

/// M4: Daily Wisdom on Today, the reminder, and the versioned schema.
@MainActor
final class WisdomAndReminderTests: XCTestCase {
    private var container: ModelContainer!
    private var repo: JournalRepository!
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
        repo = JournalRepository(context: container.mainContext)
    }

    private func day(_ s: String) -> JournalDay { TodayEditorModel.parse(s, timeZone: zone)! }

    // Criterion 1: the same item web shows (Phase 0 rotation, tested against
    // web fixtures across 2026-09…2027-12, including the year boundary).
    func testTodayUsesThePhase0RotationForTheLocalDate() throws {
        let library = try XCTUnwrap(DailyWisdom.library, "bundled, works offline")
        for date in ["2026-12-31", "2027-01-01", "2026-11-21"] {
            XCTAssertEqual(DailyWisdom.item(for: day(date))?.id, library.item(forDate: date)?.id, date)
            XCTAssertNotNil(DailyWisdom.item(for: day(date)), date)
        }
        XCTAssertNotEqual(DailyWisdom.item(for: day("2026-12-31"))?.id, DailyWisdom.item(for: day("2027-01-01"))?.id)
    }

    func testPresentationMatchesWebHelpers() throws {
        let item = try XCTUnwrap(DailyWisdom.item(for: day("2026-11-21")))
        XCTAssertEqual(DailyWisdom.prompt(item), item.prompt ?? "Where might this idea meet your life today?")
        XCTAssertTrue(DailyWisdom.attribution(item).hasPrefix(item.author))
        let wording = DailyWisdom.wording(item)
        XCTAssertTrue(["Original wording", "Translation", "Adapted by Grateful Day"].contains { wording.hasPrefix($0) }, wording)
    }

    // Criterion 5: permission only after a time is picked; one daily
    // notification; changes take effect immediately.
    final class FakeScheduler: NotificationScheduling, @unchecked Sendable {
        var grant = true
        var authRequests = 0
        var scheduled: [(Int, Int, String)] = []
        var cancels = 0
        func requestAuthorization() async -> Bool { authRequests += 1; return grant }
        func isAuthorized() async -> Bool { grant }
        func scheduleDaily(hour: Int, minute: Int, title: String, body: String) async throws { scheduled.append((hour, minute, body)) }
        func cancelDaily() async { cancels += 1 }
    }

    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        return d
    }

    private func time(_ h: Int, _ m: Int) -> Date { Calendar.current.date(from: DateComponents(hour: h, minute: m))! }

    func testReminderIsOffAndAsksNothingUntilATimeIsPicked() async {
        let fake = FakeScheduler()
        let model = ReminderModel(defaults: defaults(), scheduler: fake)
        XCTAssertFalse(model.isOn)
        await model.refreshAuthorization()
        XCTAssertEqual(fake.authRequests, 0)
        XCTAssertTrue(fake.scheduled.isEmpty)
    }

    func testTurningOnAsksPermissionThenSchedulesOneDailyReminder() async {
        let fake = FakeScheduler()
        let d = defaults()
        let model = ReminderModel(defaults: d, scheduler: fake)
        await model.turnOn(at: time(7, 30))
        XCTAssertEqual(fake.authRequests, 1)
        XCTAssertTrue(model.isOn)
        XCTAssertEqual(fake.scheduled.count, 1)
        XCTAssertEqual(fake.scheduled.first?.0, 7)
        XCTAssertEqual(fake.scheduled.first?.1, 30)
        XCTAssertEqual(fake.scheduled.first?.2, ReminderModel.body)
        // Survives relaunch.
        XCTAssertTrue(ReminderModel(defaults: d, scheduler: fake).isOn)
    }

    func testChangingTheTimeReschedulesImmediatelyAndOffCancels() async {
        let fake = FakeScheduler()
        let model = ReminderModel(defaults: defaults(), scheduler: fake)
        await model.turnOn(at: time(7, 30))
        await model.change(to: time(21, 0))
        XCTAssertEqual(fake.scheduled.last?.0, 21)
        await model.turnOff()
        XCTAssertFalse(model.isOn)
        XCTAssertEqual(fake.cancels, 1)
    }

    func testDeniedPermissionLeavesItOffAndExplains() async {
        let fake = FakeScheduler()
        fake.grant = false
        let model = ReminderModel(defaults: defaults(), scheduler: fake)
        await model.turnOn(at: time(8, 0))
        XCTAssertFalse(model.isOn)
        XCTAssertTrue(model.permissionDenied)
        XCTAssertTrue(fake.scheduled.isEmpty)
    }

    func testNotificationCopyHoldsNoReflectionText() {
        XCTAssertEqual(ReminderModel.title, "Grateful Day")
        XCTAssertEqual(ReminderModel.body, "A quiet minute of gratitude.")
    }

    // The offer after the 2nd saved reflection, shown once, recorded in the journal.
    func testReminderOfferAfterTheSecondReflectionOnce() throws {
        let first = TodayEditorModel(repository: repo, day: day("2026-11-20"))
        first.edit("one"); first.flush()
        XCTAssertFalse(first.showReminderOffer, "not after the first")
        let second = TodayEditorModel(repository: repo, day: day("2026-11-21"))
        second.edit("two"); second.flush()
        XCTAssertTrue(second.showReminderOffer)
        XCTAssertTrue(try repo.flag(JournalFlag.reminderOfferShown))
        second.edit("two, edited"); second.flush()
        let again = TodayEditorModel(repository: repo, day: day("2026-11-22"))
        again.edit("three"); again.flush()
        XCTAssertFalse(again.showReminderOffer, "only once")
    }

    // Versioned schema: an M3b store (unversioned V2) opens with V3, data intact.
    func testAnM3bStoreOpensWithTheVersionedSchema() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation(directory: root.appendingPathComponent("Store"))
        _ = try location.prepare()
        let d = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000))
        do {
            let old = Schema([JournalEntry.self, AcknowledgedMilestone.self])
            let c = try ModelContainer(for: old, configurations: ModelConfiguration(schema: old, url: location.storeURL, cloudKitDatabase: .none))
            let r = JournalRepository(context: c.mainContext)
            try r.save(text: "from M3b", for: d)
            _ = try r.takeMilestone()
        }
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        let c = try XCTUnwrap(store.container, "\(store.state)")
        let r = JournalRepository(context: c.mainContext)
        XCTAssertEqual(try r.text(for: d), "from M3b")
        XCTAssertNil(try r.takeMilestone(), "the acknowledged milestone survived")
        try r.setFlag(JournalFlag.reminderOfferShown)
        XCTAssertTrue(try r.flag(JournalFlag.reminderOfferShown))
    }
}
