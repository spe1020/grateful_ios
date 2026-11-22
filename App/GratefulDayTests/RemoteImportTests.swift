import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// M5b-1 importer: owner rows only, archive before take-remote, conflicts,
/// blocked days, deletions (interop r5.1 §0.1 5a, §4; P17; P22).
@MainActor
final class RemoteImportTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let zone = TimeZone(identifier: "America/Chicago")!
    private let owner = String(repeating: "b", count: 64)
    private let other = String(repeating: "a", count: 64)

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private func importer() -> RemoteImporter { RemoteImporter(context: context, owner: owner) }
    private func dummyEvent() -> NostrEvent { NostrEvent(id: "x", pubkey: owner, createdAt: 1, kind: 36669, tags: [], content: "", sig: "") }
    private func entry(_ text: String, id: String = UUID().uuidString, at: Int = 100) -> RemoteDay {
        .entry(text: text, isPrivate: true, eventId: id, createdAt: at, event: dummyEvent())
    }
    private func row(owner o: String?, _ date: String) throws -> JournalEntry? {
        let key: String? = JournalEntry.key(owner: o, dateString: date)
        return try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first
    }
    private func insert(_ text: String, on date: String, owner o: String?, state: SyncState = .localOnly, remoteId: String? = nil) throws {
        let d = TodayEditorModel.parse(date, timeZone: zone)!
        let r = JournalEntry(dateString: date, dayOfYear: d.day.dayOfYear, publishedAt: d.day.publishedAt,
                             timeZoneID: zone.identifier, notesText: text, now: .now, ownerPubkey: o)
        r.syncStateRaw = state.rawValue
        r.remoteEventID = remoteId
        context.insert(r)
        try context.save()
    }
    private func archive() throws -> [EarlierVersion] { try context.fetch(FetchDescriptor<EarlierVersion>()) }

    func testImportsNewRemoteDayAsOwnerRow() throws {
        try importer().apply(["2026-11-20": entry("from web")], zone: zone)
        let r = try XCTUnwrap(row(owner: owner, "2026-11-20"))
        XCTAssertEqual(r.notesText, "from web")
        XCTAssertEqual(r.syncState, .synced)
    }

    func testBFetchForDateOwnedByANeverOverwrites() throws {
        try insert("A's reflection", on: "2026-11-20", owner: other, state: .synced, remoteId: "a1")
        try importer().apply(["2026-11-20": entry("B's reflection")], zone: zone)
        XCTAssertEqual(try row(owner: other, "2026-11-20")?.notesText, "A's reflection", "A's row untouched")
        XCTAssertEqual(try row(owner: owner, "2026-11-20")?.notesText, "B's reflection", "B gets its own row")
        XCTAssertTrue(try archive().isEmpty, "nothing of A's was replaced or archived")
    }

    func testGuestRowSameDateUntouchedByImport() throws {
        try insert("written as guest", on: "2026-11-21", owner: nil)
        try importer().apply(["2026-11-21": entry("remote")], zone: zone)
        XCTAssertEqual(try row(owner: nil, "2026-11-21")?.notesText, "written as guest")
        XCTAssertEqual(try row(owner: owner, "2026-11-21")?.notesText, "remote")
    }

    func testTakeRemoteArchivesReplacedLocalText() throws {
        try insert("old synced", on: "2026-11-20", owner: owner, state: .synced, remoteId: "v1")
        try importer().apply(["2026-11-20": entry("newer from web", id: "v2", at: 200)], zone: zone)
        XCTAssertEqual(try row(owner: owner, "2026-11-20")?.notesText, "newer from web")
        let kept = try archive()
        XCTAssertEqual(kept.map(\.notesText), ["old synced"], "archived before replacing")
        XCTAssertEqual(kept.first?.ownerPubkey, owner)
    }

    func testTakeRemoteSurfacesSelfPublishedVersionWhenNotesWereLost() throws {
        try insert("my note\n\nsecond", on: "2026-11-20", owner: owner, state: .synced, remoteId: "v1")
        try importer().apply(["2026-11-20": entry("someone else's text", id: "v2")], zone: zone)
        XCTAssertEqual(try archive().first?.surfaced, true)
        XCTAssertEqual(try JournalRepository(context: context, activeOwner: owner).surfacedEarlierVersions().count, 1)
    }

    func testTakeRemoteArchivesSilentlyWhenEveryNoteSurvives() throws {
        try insert("my note", on: "2026-11-20", owner: owner, state: .synced, remoteId: "v1")
        try importer().apply(["2026-11-20": entry("my note\n\nadded on web", id: "v2")], zone: zone)
        XCTAssertEqual(try archive().first?.surfaced, false)
    }

    func testUnbasedRemoteVersionWithPendingEditsIsConflict() throws {
        try insert("edited here", on: "2026-11-20", owner: owner, state: .localOnly, remoteId: "v1")
        try importer().apply(["2026-11-20": entry("edited on web", id: "v2")], zone: zone)
        let r = try XCTUnwrap(row(owner: owner, "2026-11-20"))
        XCTAssertEqual(r.notesText, "edited here", "local text kept")
        XCTAssertEqual(r.syncState, .conflict)
        XCTAssertEqual(try archive().map(\.notesText), ["edited on web"], "remote text kept aside")
    }

    func testUndecryptableDayIsBlockedAndReadOnly() throws {
        try insert("local copy", on: "2026-11-20", owner: owner, state: .synced, remoteId: "v1")
        try importer().apply(["2026-11-20": .blocked(eventId: "v2", createdAt: 300)], zone: zone)
        let r = try XCTUnwrap(row(owner: owner, "2026-11-20"))
        XCTAssertEqual(r.notesText, "local copy", "never emptied")
        XCTAssertEqual(r.syncState, .blocked)
        let repo = JournalRepository(context: context, activeOwner: owner)
        XCTAssertThrowsError(try repo.save(text: "overwrite", for: TodayEditorModel.parse("2026-11-20", timeZone: zone)!))
        XCTAssertTrue(try repo.isBlocked("2026-11-20"))
    }

    func testRemoteDeleteTombstonesAndArchives() throws {
        try insert("to go", on: "2026-11-20", owner: owner, state: .synced, remoteId: "v1")
        try importer().apply(["2026-11-20": .deleted(at: 500)], zone: zone)
        let r = try XCTUnwrap(row(owner: owner, "2026-11-20"))
        XCTAssertNotNil(r.deletedAt)
        XCTAssertEqual(try archive().map(\.notesText), ["to go"])
    }

    func testRemoteDeleteAgainstPendingEditIsConflict() throws {
        try insert("unsent edit", on: "2026-11-20", owner: owner, state: .localOnly, remoteId: "v1")
        try importer().apply(["2026-11-20": .deleted(at: 500)], zone: zone)
        let r = try XCTUnwrap(row(owner: owner, "2026-11-20"))
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "unsent edit")
        XCTAssertEqual(r.syncState, .conflict)
    }

    func testEditAfterSyncBecomesPendingEdit() throws {
        try insert("synced", on: "2026-11-20", owner: owner, state: .synced, remoteId: "v1")
        try JournalRepository(context: context, activeOwner: owner).save(text: "edited", for: TodayEditorModel.parse("2026-11-20", timeZone: zone)!)
        XCTAssertEqual(try row(owner: owner, "2026-11-20")?.syncState, .localOnly)
    }

    func testEarlierVersionsOfOtherAccountsAreNotShown() throws {
        context.insert(EarlierVersion(ownerPubkey: other, dateString: "2026-11-20", notesText: "A's", reason: .replacedByRemote,
                                      eventId: nil, surfaced: true, now: .now))
        try context.save()
        XCTAssertTrue(try JournalRepository(context: context, activeOwner: owner).surfacedEarlierVersions().isEmpty)
    }
}

/// V4 (M5a-built fixture) -> V5.
@MainActor
final class V5MigrationTests: XCTestCase {
    func testV4StoreMigratesToV5() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "v4-journal", withExtension: "store"))
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: location.storeURL)
        let store = JournalStore(location: location, defaults: UserDefaults(suiteName: "v5-\(UUID().uuidString)")!)
        store.openIfPossible(protectedDataAvailable: true)
        let ctx = try XCTUnwrap(store.container, "\(store.state)").mainContext
        let rows = try ctx.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
        XCTAssertEqual(rows.map(\.notesText), ["Guest note", "Owned note"])
        XCTAssertEqual(rows.map(\.ownerPubkey), [nil, String(repeating: "a", count: 64)])
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AccountMarker>()).first?.state, .signedOut)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<EarlierVersion>()).isEmpty)
        XCTAssertTrue(try JournalRepository(context: ctx).flag(JournalFlag.reminderOfferShown))
    }
}
