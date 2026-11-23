import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Chief P38, Prep interop §2.6 ruling 3: milestones the account passed
/// elsewhere are never shown here, and each account gets its own lines.
@MainActor
final class MilestonePerAccountTests: XCTestCase {
    private let secretA = try! NostrKeys.generatePrivateKey()
    private let secretB = try! NostrKeys.generatePrivateKey()
    private var a: String { KeyVault.pubkeyHex(for: secretA)! }
    private var b: String { KeyVault.pubkeyHex(for: secretB)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private func day(_ s: String) -> JournalDay { TodayEditorModel.parse(s, timeZone: zone)! }
    private func date(_ i: Int) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let d = cal.date(byAdding: .day, value: i, to: cal.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!)!
        return CalendarModel.dateString(d, cal)
    }

    /// `n` days on the account's relays, imported, then the post-import mark.
    private func importDays(_ n: Int, owner: String, secret: Data) throws {
        let events = try (0..<n).map { i in
            try DailyEntry.privateTemplate(day: day(date(i)).day, notes: ["day \(i)"], privateKey: secret)
                .signed(privateKey: secret, createdAt: 1_000 + i)
        }
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: events, owner: owner, privateKey: secret), zone: zone)
        try JournalRepository(context: context, activeOwner: owner).markPassedMilestonesSeen()
    }

    /// Gap 1: an import landing exactly on 30, then an edit to that last
    /// day (today), shows nothing.
    func testImportExactlyOnThirtyThenEditShowsNothing() throws {
        try importDays(30, owner: a, secret: secretA)
        let repo = JournalRepository(context: context, activeOwner: a)
        XCTAssertEqual(try repo.totalReflectionCount(), 30)
        try repo.save(text: "edited today", for: day(date(29)))
        XCTAssertNil(try repo.takeMilestone(), "30 was passed elsewhere")
    }

    /// A real crossing on this iPhone still shows the line.
    func testCrossingHereStillShows() throws {
        try importDays(29, owner: a, secret: secretA)
        let repo = JournalRepository(context: context, activeOwner: a)
        try repo.save(text: "the 30th", for: day(date(29)))
        XCTAssertEqual(try repo.takeMilestone(), 30)
        XCTAssertNil(try repo.takeMilestone(), "shown once")
    }

    /// Gap 2: account B gets its own 30 line after account A passed 30.
    func testAnotherAccountGetsItsOwnLine() throws {
        let repoA = JournalRepository(context: context, activeOwner: a)
        for i in 0..<30 {
            try repoA.save(text: "a\(i)", for: day(date(i)))
            _ = try repoA.takeMilestone()
        }
        // The guest rows above counted for A while A was active; make them A's.
        for row in try context.fetch(FetchDescriptor<JournalEntry>()) where row.ownerPubkey == nil {
            row.ownerPubkey = a
            row.entryKey = JournalEntry.key(owner: a, dateString: row.dateString)
        }
        try context.save()
        let repoB = JournalRepository(context: context, activeOwner: b)
        for i in 0..<29 {
            try repoB.save(text: "b\(i)", for: day(date(100 + i)))
            _ = try repoB.takeMilestone()
        }
        try repoB.save(text: "b's 30th", for: day(date(129)))
        XCTAssertEqual(try repoB.takeMilestone(), 30)
    }

    /// Records from before P38 count for every account.
    func testOlderRecordsHideRatherThanRepeat() throws {
        context.insert(AcknowledgedMilestone(total: 1, acknowledgedAt: .now))
        try context.save()
        let repo = JournalRepository(context: context, activeOwner: b)
        try repo.save(text: "first for b", for: day(date(0)))
        XCTAssertNil(try repo.takeMilestone())
    }
}
