import XCTest
import SwiftData
@testable import GratefulDay

/// Opening stores written by earlier builds (Audit PR #11, design r3.1).
@MainActor
final class MigrationTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    /// The fixture was written by the M4 build itself (Fixtures/M4Store/README.md),
    /// so this catches a checksum change in the frozen older schemas.
    func testV3StoreMigratesToOwnerKeyedEntries() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "m4-journal", withExtension: "store"),
                                    "fixture is bundled")
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: location.storeURL)

        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        let container = try XCTUnwrap(store.container, "an M4 store opens with V4: \(store.state)")
        let context = container.mainContext

        let rows = try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
        XCTAssertEqual(rows.map(\.dateString), ["2026-11-19", "2026-11-20", "2026-11-21"])
        XCTAssertEqual(rows.map(\.notesText), ["First note\n\nSecond note", "Morning light", ""])
        XCTAssertNotNil(rows[2].deletedAt, "the tombstone survives")
        XCTAssertTrue(rows.allSatisfy { $0.ownerPubkey == nil }, "every pre-account row is a guest row")
        XCTAssertEqual(rows.map(\.entryKey), ["guest|2026-11-19", "guest|2026-11-20", "guest|2026-11-21"])

        let repo = JournalRepository(context: context)
        XCTAssertTrue(try repo.flag(JournalFlag.reminderOfferShown))
        XCTAssertNil(try repo.takeMilestone(), "milestone 1 was already acknowledged")
        XCTAssertTrue(try context.fetch(FetchDescriptor<AccountMarker>()).isEmpty, "no account yet")

        // Writing after migration uses the new key without clashing.
        let zone = TimeZone(identifier: "America/Chicago")!
        try repo.save(text: "after migration", for: TodayEditorModel.parse("2026-11-20", timeZone: zone)!)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 3, "edited in place, no duplicate")
    }
}
