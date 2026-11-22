import XCTest
import SwiftData
@testable import GratefulDay

/// Chief P10 (backup-exclusion failure) and P10.5 (protection failure):
/// the journal still opens, the failure is flagged and logged without
/// content, the app stops claiming exclusion, and a later good foreground
/// clears the flag.
@MainActor
final class StoreFailureTests: XCTestCase {
    /// Thread-safe on/off switch for an injected failure.
    final class Switch: @unchecked Sendable {
        private let lock = NSLock()
        private var _on: Bool
        init(_ on: Bool) { _on = on }
        var on: Bool {
            get { lock.withLock { _on } }
            set { lock.withLock { _on = newValue } }
        }
    }

    struct Injected: Error {}

    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        StorageLog.clearRecent()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func location(failExclusion: Switch = Switch(false), failProtection: Switch = Switch(false)) -> StoreLocation {
        var attrs = StoreLocation.Attributes.system
        let exclude = attrs.excludeFromBackup
        let protect = attrs.setCompleteProtection
        attrs.excludeFromBackup = { url in
            if failExclusion.on { throw Injected() }
            try exclude(url)
        }
        attrs.setCompleteProtection = { path in
            if failProtection.on { throw Injected() }
            try protect(path)
        }
        return StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true), attributes: attrs)
    }

    /// Let StorageLog's main-actor append run.
    private func drainLog() async { await Task.yield(); await Task.yield() }

    // P10 items 1–4.
    func testBackupExclusionFailureOpensFlagsLogsAndWithdrawsTheClaim() async throws {
        let fail = Switch(true)
        let store = JournalStore(location: location(failExclusion: fail))
        store.openIfPossible(protectedDataAvailable: true)

        XCTAssertNotNil(store.container, "the journal still opens")
        XCTAssertTrue(store.backupExclusionFailed)
        XCTAssertFalse(store.protectionFailed)

        await drainLog()
        let line = try XCTUnwrap(StorageLog.recent.first { $0.hasPrefix("Backup exclusion not applied") })
        XCTAssertEqual(line, "Backup exclusion not applied [file: Store] [GratefulDayTests.StoreFailureTests.Injected 1]")

        // The statement no longer says reflections are left out of backups.
        let shown = PrivacyCopy.statement(backupExclusionFailed: store.backupExclusionFailed)
        XCTAssertEqual(shown, PrivacyCopy.backupExclusionFailedStatement)
        XCTAssertFalse(shown.contains("aren't included in iCloud or iPhone backups"))

        // Next foreground with the call working: flag clears, claim returns.
        fail.on = false
        store.openIfPossible(protectedDataAvailable: true)
        XCTAssertFalse(store.backupExclusionFailed)
        XCTAssertEqual(PrivacyCopy.statement(backupExclusionFailed: store.backupExclusionFailed), PrivacyCopy.preAccountStatement)
        let values = try store.location.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // P10.5: a protection failure never locks the user out.
    func testProtectionFailureStillOpensFlagsLogsAndClearsOnRetry() async throws {
        let fail = Switch(true)
        let store = JournalStore(location: location(failProtection: fail))
        store.openIfPossible(protectedDataAvailable: true)

        guard case .open = store.state else { return XCTFail("locked out: \(store.state)") }
        XCTAssertTrue(store.protectionFailed)
        XCTAssertFalse(store.backupExclusionFailed)

        // The journal is usable.
        let repo = JournalRepository(context: try XCTUnwrap(store.container).mainContext)
        let day = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000))
        try repo.save(text: "still writable", for: day)

        await drainLog()
        let lines = StorageLog.recent.filter { $0.hasPrefix("Protection class not applied") }
        XCTAssertFalse(lines.isEmpty)
        for line in lines {
            XCTAssertTrue(line.contains("[file: "), line)
            XCTAssertFalse(line.contains("still writable"), "no journal content in logs")
            XCTAssertFalse(line.contains(day.dateString), "no dates in logs")
        }

        fail.on = false
        store.openIfPossible(protectedDataAvailable: true)
        XCTAssertFalse(store.protectionFailed)
    }

    func testRetryDoesNothingWhileLocked() {
        let fail = Switch(true)
        let store = JournalStore(location: location(failExclusion: fail))
        store.openIfPossible(protectedDataAvailable: true)
        fail.on = false
        store.openIfPossible(protectedDataAvailable: false)
        XCTAssertTrue(store.backupExclusionFailed, "no retry while protected data is unavailable")
        XCTAssertNotNil(store.container, "an open store stays open")
    }
}
