import XCTest
import SwiftData
import GratefulDayCore
import NostrCore
@testable import GratefulDay

/// M2 storage criteria. Each test uses its own temporary Store/ directory.
@MainActor
final class StorageTests: XCTestCase {
    private var root: URL!
    private var location: StoreLocation!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func openStore() throws -> JournalStore {
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        guard store.container != nil else {
            XCTFail("store did not open: \(store.state)")
            throw CancellationError()
        }
        return store
    }

    private let day = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000),
                                 timeZone: TimeZone(identifier: "America/Chicago")!)

    // MARK: - Criterion 3 / recommendation §7.1

    func testCloudKitIsOff() {
        let config = JournalStore.configuration(url: location.storeURL)
        // CloudKitDatabase isn't Equatable: compare descriptions, and check
        // that no CloudKit container is configured.
        XCTAssertEqual(String(describing: config.cloudKitDatabase),
                       String(describing: ModelConfiguration.CloudKitDatabase.none))
        XCTAssertNotEqual(String(describing: config.cloudKitDatabase),
                          String(describing: ModelConfiguration.CloudKitDatabase.automatic))
        XCTAssertNil(config.cloudKitContainerIdentifier)
    }

    func testStoreDirectoryIsExcludedFromBackup() throws {
        let store = try openStore()
        XCTAssertFalse(store.backupExclusionFailed)
        let values = try location.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testBackupExclusionIsReappliedEveryLaunch() throws {
        _ = try location.prepare()
        var url = location.directory
        var off = URLResourceValues()
        off.isExcludedFromBackup = false
        try url.setResourceValues(off)
        // The next launch puts it back.
        _ = try openStore()
        let values = try location.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testStoreLivesInApplicationSupportStore() {
        let path = StoreLocation.standard.storeURL.path
        XCTAssertTrue(path.hasSuffix("Library/Application Support/GratefulDay/Store/journal.store"), path)
        XCTAssertFalse(path.contains("/Caches/"))
        XCTAssertFalse(path.contains("/tmp/"))
        XCTAssertFalse(path.contains("/Documents/"))
    }

    func testEveryStoreFileHasCompleteProtection() throws {
        let store = try openStore()
        try JournalRepository(context: store.container!.mainContext).save(text: "a", for: day)
        try location.protectFiles()
        let names = try FileManager.default.contentsOfDirectory(atPath: location.directory.path)
        XCTAssertTrue(names.contains("journal.store"), "\(names)")
        let dirProtection = try FileManager.default.attributesOfItem(atPath: location.directory.path)[.protectionKey] as? FileProtectionType
        #if targetEnvironment(simulator)
        // The simulator doesn't implement Data Protection, so it may not report
        // a class. Real-device verification stays an open [verify] item (§7).
        if dirProtection == nil { throw XCTSkip("Simulator reports no protection class; verify on a device") }
        #endif
        XCTAssertEqual(dirProtection, .complete)
        for name in names {
            let attrs = try FileManager.default.attributesOfItem(atPath: location.directory.appendingPathComponent(name).path)
            XCTAssertEqual(attrs[.protectionKey] as? FileProtectionType, .complete, name)
        }
    }

    // MARK: - Criterion 4: never an empty journal by mistake

    func testLockedDeviceDoesNotOpenOrCreateAnything() {
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: false)
        guard case .waitingForUnlock = store.state else { return XCTFail("\(store.state)") }
        XCTAssertNil(store.container)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.directory.path), "nothing written before unlock")
    }

    func testUnreadableExistingStoreFailsInsteadOfBeingReplaced() throws {
        _ = try location.prepare()
        let original = Data("existing journal".utf8)
        FileManager.default.createFile(atPath: location.storeURL.path, contents: original,
                                       attributes: [.posixPermissions: 0o000])
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.storeURL.path) }
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        guard case .failed = store.state else { return XCTFail("\(store.state)") }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.storeURL.path)
        XCTAssertEqual(FileManager.default.contents(atPath: location.storeURL.path), original, "store file untouched")
    }

    func testCorruptStoreFailsAndIsNotReplaced() throws {
        _ = try location.prepare()
        let garbage = Data(repeating: 0x5A, count: 4096)
        FileManager.default.createFile(atPath: location.storeURL.path, contents: garbage)
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        guard case .failed = store.state else { return XCTFail("\(store.state)") }
        XCTAssertEqual(FileManager.default.contents(atPath: location.storeURL.path), garbage, "store file untouched")
    }

    // MARK: - Criteria 1 and 2

    func testSavedEntrySurvivesReopening() throws {
        do {
            let store = try openStore()
            try JournalRepository(context: store.container!.mainContext).save(text: "Morning light", for: day)
        }
        // A new container on the same file, as after a force quit and relaunch.
        let reopened = try openStore()
        let entry = try JournalRepository(context: reopened.container!.mainContext).entry(for: day.dateString)
        XCTAssertEqual(entry?.notesText, "Morning light")
    }

    func testOneEntryPerDate() throws {
        let store = try openStore()
        let repo = JournalRepository(context: store.container!.mainContext)
        try repo.save(text: "first", for: day)
        try repo.save(text: "second", for: day)
        let all = try store.container!.mainContext.fetch(FetchDescriptor<JournalEntry>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.notesText, "second")
    }

    func testNotesAreStoredInEntryNotesForm() throws {
        let store = try openStore()
        let entry = try JournalRepository(context: store.container!.mainContext)
            .save(text: "  one \r\n\r\n\n two  \n \n three", for: day)
        XCTAssertEqual(entry.notesText, "one\n\ntwo\n\nthree")
        XCTAssertEqual(EntryNotes.split(entry.notesText), ["one", "two", "three"])
    }

    func testStoredEntryEncodesAsA36669WithSameDateAndText() throws {
        let store = try openStore()
        let entry = try JournalRepository(context: store.container!.mainContext)
            .save(text: "one\n\ntwo", for: day)
        let event = try DailyEntry.template(day: JournalRepository.day(of: entry), notes: EntryNotes.split(entry.notesText))
        XCTAssertEqual(event.kind, 36669)
        XCTAssertEqual(event.content, entry.notesText)
        XCTAssertTrue(event.tags.contains(["d", day.day.dateString]))
        XCTAssertTrue(event.tags.contains(["published_at", String(day.day.publishedAt)]))
        XCTAssertTrue(event.tags.contains(["day", String(day.day.dayOfYear)]))
        XCTAssertEqual(entry.timeZoneID, "America/Chicago")
    }

    // MARK: - Criterion 6

    func testNewEntryIsPrivateAndLocalOnly() throws {
        let store = try openStore()
        let entry = try JournalRepository(context: store.container!.mainContext).save(text: "x", for: day)
        XCTAssertTrue(entry.isPrivate)
        XCTAssertEqual(entry.syncState, .localOnly)
        XCTAssertNil(entry.deletedAt)
        XCTAssertNil(entry.remoteEventID)
    }

    // MARK: - Criterion 5

    func testFailedSaveKeepsTextAndTellsTheUser() {
        struct Boom: Error {}
        var fail = true
        var saved: [String] = []
        let draft = DraftBuffer(text: "Grateful for coffee") { text in
            if fail { throw Boom() }
            saved.append(text)
        }
        XCTAssertFalse(draft.commit())
        XCTAssertEqual(draft.text, "Grateful for coffee")
        XCTAssertEqual(draft.saveError, "Couldn't save just now. Your text is still here.")
        fail = false
        XCTAssertTrue(draft.commit())
        XCTAssertNil(draft.saveError)
        XCTAssertEqual(saved, ["Grateful for coffee"])
    }

    // MARK: - Criteria 7 and 9

    func testPreAccountStatementIsTheApprovedCopy() {
        XCTAssertEqual(PrivacyCopy.preAccountStatement,
            "Until you connect an account, nothing you write is published. Your reflections are saved only on this iPhone and aren't included in iCloud or iPhone backups. If you lose or replace this iPhone, or delete the app, they can't be recovered.")
        XCTAssertEqual(PrivacyCopy.localOnlyLabel, "On this iPhone only")
    }
}
