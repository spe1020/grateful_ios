import XCTest
import SwiftData
@testable import GratefulDay

/// Seth / Audit (#13): "Nothing has been deleted." must never appear after a
/// "Remove account and local data" that didn't finish, because the folder
/// delete can remove some files before it fails.
@MainActor
final class RemovalMessageTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults = UserDefaults(suiteName: "removal-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func testFailedOpenTextNeverClaimsNothingDeletedAfterIncompleteRemoval() {
        XCTAssertEqual(JournalUnavailableView.failedText(removalIncomplete: false), JournalUnavailableView.failedMessage)
        let after = JournalUnavailableView.failedText(removalIncomplete: true)
        XCTAssertEqual(after, AccountCopy.removeKeyOnly)
        XCTAssertFalse(after.contains("Nothing has been deleted"))
    }

    func testRemovalThatCannotDeleteStaysIncompleteAcrossRelaunch() throws {
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        let store = JournalStore(location: location, defaults: defaults)
        store.openIfPossible(protectedDataAvailable: true)
        XCTAssertNotNil(store.container)
        // Make the parent read-only so the folder can't be removed.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        let removed = store.removeAllData()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        if removed { throw XCTSkip("The simulator allowed the delete despite permissions") }
        XCTAssertTrue(store.removalIncomplete)
        // A relaunch still knows the removal didn't finish.
        XCTAssertTrue(JournalStore(location: location, defaults: defaults).removalIncomplete)
    }

    func testCompletedRemovalClearsTheFlag() {
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        let store = JournalStore(location: location, defaults: defaults)
        store.openIfPossible(protectedDataAvailable: true)
        XCTAssertTrue(store.removeAllData())
        XCTAssertFalse(store.removalIncomplete)
        XCTAssertNotNil(store.container, "a fresh, empty journal after a confirmed removal")
    }

    func testFlagSetBeforeDeletingSoAFailedReopenNeverClaimsNothingDeleted() {
        // Simulates a removal interrupted after it started (e.g. the app was
        // killed mid-delete): the flag is already set, so a later failed open
        // shows F8's message.
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        let store = JournalStore(location: location, defaults: defaults)
        store.removalIncomplete = true
        XCTAssertEqual(JournalUnavailableView.failedText(removalIncomplete: store.removalIncomplete), AccountCopy.removeKeyOnly)
    }
}
