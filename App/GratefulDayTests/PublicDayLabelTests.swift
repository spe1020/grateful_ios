import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Chief P42 (Prep's ruling): a day that's public on the account shows
/// "This day is public. Anyone can read it." wherever it's shown or edited.
/// Private days and days that exist only on this iPhone show nothing new.
@MainActor
final class PublicDayLabelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!
    private let owner = String(repeating: "b", count: 64)
    private let other = String(repeating: "a", count: 64)

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private func dummyEvent() -> NostrEvent { NostrEvent(id: "x", pubkey: owner, createdAt: 1, kind: 36669, tags: [], content: "", sig: "") }
    private func remote(_ text: String, isPrivate: Bool, id: String = UUID().uuidString) -> RemoteDay {
        .entry(text: text, isPrivate: isPrivate, eventId: id, createdAt: 100, event: dummyEvent())
    }
    private func day(_ s: String) -> JournalDay { TodayEditorModel.parse(s, timeZone: zone)! }
    private func importDays(_ days: [String: RemoteDay], owner o: String? = nil) throws {
        try RemoteImporter(context: context, owner: o ?? owner).apply(days, zone: zone)
    }

    func testCopy() {
        XCTAssertEqual(PrivacyCopy.publicDayLabel, "This day is public. Anyone can read it.")
    }

    func testPublicDayFromTheAccountShowsTheLine() throws {
        try importDays(["2026-11-20": remote("shared on web", isPrivate: false)])
        XCTAssertTrue(JournalRepository(context: context, activeOwner: owner).showsPublicLabel("2026-11-20"))
    }

    /// Editing on iOS republishes the day as it is, so the line stays.
    func testPublicDayKeepsTheLineWhileEdited() throws {
        try importDays(["2026-11-20": remote("shared on web", isPrivate: false)])
        let repo = JournalRepository(context: context, activeOwner: owner)
        let row = try repo.save(text: "shared on web, and more from iOS", for: day("2026-11-20"))
        XCTAssertFalse(row.isPrivate, "nothing about publishing changes (P42)")
        XCTAssertTrue(repo.showsPublicLabel("2026-11-20"))
    }

    func testPrivateDayShowsNothing() throws {
        try importDays(["2026-11-20": remote("private on web", isPrivate: true)])
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertFalse(repo.showsPublicLabel("2026-11-20"))
        try repo.save(text: "written on this iPhone", for: day("2026-11-19"))
        XCTAssertFalse(repo.showsPublicLabel("2026-11-19"), "days written on iOS are private")
    }

    func testIPhoneOnlyDaysShowNothing() throws {
        // A guest day, seen as a guest and after connecting.
        let guest = JournalRepository(context: context)
        let row = try guest.save(text: "before connecting", for: day("2026-11-18"))
        row.isPrivate = false // even if the flag were ever false, a day only here makes no claim
        try context.save()
        XCTAssertFalse(guest.showsPublicLabel("2026-11-18"))
        XCTAssertFalse(JournalRepository(context: context, activeOwner: owner).showsPublicLabel("2026-11-18"))
        // No row at all.
        XCTAssertFalse(JournalRepository(context: context, activeOwner: owner).showsPublicLabel("2026-11-17"))
    }

    func testAnotherAccountsPublicDayShowsNothingHere() throws {
        try importDays(["2026-11-20": remote("other account's public day", isPrivate: false)], owner: other)
        XCTAssertFalse(JournalRepository(context: context, activeOwner: owner).showsPublicLabel("2026-11-20"))
    }

    func testDeletedPublicDayShowsNothing() throws {
        try importDays(["2026-11-20": remote("shared on web", isPrivate: false)])
        let repo = JournalRepository(context: context, activeOwner: owner)
        try repo.delete(day("2026-11-20"))
        XCTAssertFalse(repo.showsPublicLabel("2026-11-20"))
    }
}
