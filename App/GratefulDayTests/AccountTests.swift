import XCTest
import SwiftData
import Security
import UIKit
import NostrCore
@testable import GratefulDay

/// An in-memory Keychain whose every result can be forced.
final class FakeKeychain: KeychainStoring {
    struct Item { var data: Data; var accessibility: CFString }
    var items: [String: Item] = [:]
    var forcedRead: KeychainRead?
    var deleteStatus: OSStatus?
    var addStatus: OSStatus?
    var corruptReadBack = false
    var accountsFail = false

    private func k(_ s: String, _ a: String, _ sync: Bool) -> String { "\(s)|\(a)|\(sync)" }

    func read(service: String, account: String, synchronizable: Bool) -> KeychainRead {
        if let forcedRead { return forcedRead }
        guard let item = items[k(service, account, synchronizable)] else { return .notFound }
        if corruptReadBack { return .found(Data(repeating: 7, count: 32)) }
        return .found(item.data)
    }

    func add(_ data: Data, service: String, account: String, synchronizable: Bool, accessibility: CFString) -> OSStatus {
        if let addStatus { return addStatus }
        let key = k(service, account, synchronizable)
        guard items[key] == nil else { return errSecDuplicateItem }
        items[key] = Item(data: data, accessibility: accessibility)
        return errSecSuccess
    }

    func delete(service: String, account: String, synchronizable: Bool) -> OSStatus {
        if let deleteStatus { return deleteStatus }
        return items.removeValue(forKey: k(service, account, synchronizable)) == nil ? errSecItemNotFound : errSecSuccess
    }

    func accounts(service: String, synchronizable: Bool) -> Result<[String], OSStatusError> {
        if accountsFail { return .failure(OSStatusError(status: errSecInteractionNotAllowed)) }
        let prefix = "\(service)|"
        return .success(items.keys.filter { $0.hasPrefix(prefix) && $0.hasSuffix("|\(synchronizable)") }
            .map { String($0.dropFirst(prefix.count).split(separator: "|").first!) })
    }

    func item(service: String, account: String, sync: Bool) -> Item? { items[k(service, account, sync)] }
}

@MainActor
final class AccountTests: XCTestCase {
    private var root: URL!
    private var store: JournalStore!
    private var keychain: FakeKeychain!
    private var account: AccountModel!
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = JournalStore(location: StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true)))
        store.openIfPossible(protectedDataAvailable: true)
        keychain = FakeKeychain()
        account = AccountModel(vault: KeyVault(keychain: keychain))
        account.refresh(context: context)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private var context: ModelContext { store.container!.mainContext }
    private func day(_ s: String) -> JournalDay { TodayEditorModel.parse(s, timeZone: zone)! }
    private var primary: FakeKeychain.Item? {
        keychain.item(service: KeyVault.primaryService, account: KeyVault.primaryAccount, sync: false)
    }
    private func newSecret() throws -> Data { try NostrKeys.generatePrivateKey() }
    private func pubkey(_ secret: Data) -> String { KeyVault.pubkeyHex(for: secret)! }

    private func insert(_ text: String, on date: String, owner: String?) throws {
        let d = day(date)
        context.insert(JournalEntry(dateString: d.day.dateString, dayOfYear: d.day.dayOfYear, publishedAt: d.day.publishedAt,
                                    timeZoneID: zone.identifier, notesText: text, now: .now, ownerPubkey: owner))
        try context.save()
    }

    // MARK: Storage (design §3)

    func testCreateKeyStoresDeviceOnlyAndConnects() throws {
        XCTAssertEqual(account.state, .guest)
        let pub = try account.createKey(context: context)
        XCTAssertEqual(account.state, .connected(pubkey: pub))
        let item = try XCTUnwrap(primary)
        XCTAssertEqual(item.accessibility as String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertNil(keychain.item(service: KeyVault.primaryService, account: KeyVault.primaryAccount, sync: true), "never synchronized")
        XCTAssertEqual(account.backups, .backups([]), "no backup without an affirmative choice")
    }

    func testBackupIsSyncedWhenUnlockedOnlyOnRequest() throws {
        let pub = try account.createKey(context: context)
        try account.backUpKey()
        guard case .backups(let list) = account.backups else { return XCTFail() }
        XCTAssertEqual(list.map(\.pubkey), [pub])
        let item = try XCTUnwrap(keychain.item(service: KeyVault.backupService, account: list[0].account, sync: true))
        XCTAssertEqual(item.accessibility as String, kSecAttrAccessibleWhenUnlocked as String)
        XCTAssertTrue(list[0].account.hasPrefix("bk_"), "opaque name, no npub")
        XCTAssertFalse(list[0].account.contains(pub))
    }

    // MARK: §7 states — a failed read is never "no key"

    func testMarkerUnreadableIsUnknown() {
        account.refresh(context: nil)
        XCTAssertEqual(account.state, .unknown)
        XCTAssertThrowsError(try account.createKey(context: context))
    }

    func testKeychainFailureIsKeyUnavailableNeverGuest() {
        keychain.forcedRead = .failed(errSecInternalError)
        account.refresh(context: context)
        XCTAssertEqual(account.state, .keyUnavailable(errSecInternalError))
        XCTAssertThrowsError(try account.createKey(context: context))
    }

    func testLockedIsLocked() {
        keychain.forcedRead = .locked
        account.refresh(context: context)
        XCTAssertEqual(account.state, .locked)
    }

    func testKeyMissingNeverCreatesAKey() throws {
        let pub = try account.createKey(context: context)
        keychain.items.removeAll()
        account.refresh(context: context)
        XCTAssertEqual(account.state, .keyMissing(pubkey: pub))
        XCTAssertThrowsError(try account.createKey(context: context))
        XCTAssertNil(primary)
    }

    func testMismatchWhenKeyAndMarkerDiffer() throws {
        let pub = try account.createKey(context: context)
        keychain.items.removeAll()
        let other = try newSecret()
        _ = keychain.add(other, service: KeyVault.primaryService, account: KeyVault.primaryAccount,
                         synchronizable: false, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        account.refresh(context: context)
        XCTAssertEqual(account.state, .mismatch(keyPubkey: pubkey(other), markerPubkey: pub))
    }

    func testReinstallKeyWithoutMarkerConnects() throws {
        let secret = try newSecret()
        _ = keychain.add(secret, service: KeyVault.primaryService, account: KeyVault.primaryAccount,
                         synchronizable: false, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        account.refresh(context: context)
        XCTAssertEqual(account.state, .connected(pubkey: pubkey(secret)))
    }

    // MARK: Import (design §6a)

    func testImportAcceptsNsecAndHex() throws {
        let secret = try newSecret()
        XCTAssertEqual(KeyInput.parse(try NostrKeys.nsec(secret)), secret)
        XCTAssertEqual(KeyInput.parse("  " + NostrKeys.hex(secret).uppercased() + "\n"), secret)
        let pub = try account.importKey(try NostrKeys.nsec(secret), context: context)
        XCTAssertEqual(pub, pubkey(secret))
    }

    func testImportRejectsBadChecksum() throws {
        var nsec = try NostrKeys.nsec(try newSecret())
        nsec.removeLast(); nsec.append(nsec.last == "q" ? "p" : "q")
        XCTAssertNil(KeyInput.parse(nsec))
        XCTAssertNil(KeyInput.parse("npub1notakey"))
        XCTAssertThrowsError(try account.importKey(nsec, context: context)) { XCTAssertEqual($0 as? AccountModel.ActionError, .invalidKey) }
        XCTAssertNil(primary, "nothing stored")
    }

    func testImportVerifiesKeychainWriteAndRollsBack() throws {
        keychain.corruptReadBack = true
        XCTAssertThrowsError(try account.importKey(try NostrKeys.nsec(try newSecret()), context: context))
        XCTAssertNil(primary, "what was written was removed")
        XCTAssertEqual(account.state, .guest)
    }

    func testImportRefusedWhileConnected() throws {
        _ = try account.createKey(context: context)
        XCTAssertThrowsError(try account.importKey(try NostrKeys.nsec(try newSecret()), context: context)) {
            XCTAssertEqual($0 as? AccountModel.ActionError, .notAllowedNow)
        }
    }

    func testPasteReadsOnceAndClearsPasteboard() {
        let board = UIPasteboard(name: UIPasteboard.Name("gd-test-\(UUID().uuidString)"), create: true)!
        board.string = "nsec1example"
        XCTAssertEqual(PasteboardReader.readOnceAndClear(board), "nsec1example")
        XCTAssertNil(board.string, "cleared after reading")
        UIPasteboard.remove(withName: board.name)
    }

    // MARK: Restore (F3)

    func testRestoreFromBackupOnANewPhone() throws {
        let secret = try newSecret()
        _ = try KeyVault(keychain: keychain).saveBackup(secret)
        guard case .backups(let list) = account.backups, let backup = list.first else { return XCTFail() }
        let pub = try account.restore(backup, context: context)
        XCTAssertEqual(pub, pubkey(secret))
        XCTAssertEqual(account.state, .connected(pubkey: pub))
    }

    func testUnreadableBackupListIsUnavailableNotNone() {
        keychain.accountsFail = true
        XCTAssertEqual(account.backups, .unavailable)
    }

    // MARK: Sign out (F7, P16)

    func testSignOutKeepsJournalAndOwners() throws {
        let pub = try account.createKey(context: context)
        try insert("A's day", on: "2026-11-20", owner: pub)
        try insert("guest day", on: "2026-11-19", owner: nil)
        XCTAssertEqual(account.signOut(context: context), .signedOut)
        XCTAssertNil(primary, "key removed from this iPhone")
        XCTAssertEqual(account.state, .signedOut(pubkey: pub))
        let rows = try context.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
        XCTAssertEqual(rows.map(\.ownerPubkey), [nil, pub], "journal kept, owners kept")
    }

    func testSignOutStaysSignedInWhenKeychainDeleteFails() throws {
        let pub = try account.createKey(context: context)
        keychain.deleteStatus = errSecInternalError
        XCTAssertEqual(account.signOut(context: context), .stayedSignedIn)
        XCTAssertEqual(account.state, .connected(pubkey: pub))
        XCTAssertNotNil(primary)
    }

    func testSignOutNeverTouchesTheBackup() throws {
        _ = try account.createKey(context: context)
        try account.backUpKey()
        XCTAssertEqual(account.signOut(context: context), .signedOut)
        guard case .backups(let list) = account.backups else { return XCTFail() }
        XCTAssertEqual(list.count, 1)
    }

    func testNoBackupIsDetectedForTheSignOutWarning() throws {
        let pub = try account.createKey(context: context)
        XCTAssertEqual(account.hasBackup(for: pub), false)
        try account.backUpKey()
        XCTAssertEqual(account.hasBackup(for: pub), true)
    }

    func testReconnectingAResumesItsEntries() throws {
        let secret = try newSecret()
        let pub = try account.importKey(try NostrKeys.nsec(secret), context: context)
        try insert("A's day", on: "2026-11-20", owner: pub)
        _ = account.signOut(context: context)
        XCTAssertEqual(try JournalRepository(context: context, activeOwner: account.activeOwner).text(for: day("2026-11-20")), "",
                       "signed out: A's row isn't the editor's")
        _ = try account.importKey(try NostrKeys.nsec(secret), context: context)
        XCTAssertEqual(try JournalRepository(context: context, activeOwner: account.activeOwner).text(for: day("2026-11-20")), "A's day")
    }

    // MARK: P17 owner rules

    func testSignedOutEditOfAOwnedDayCreatesAGuestRowAndLeavesAUntouched() throws {
        let pub = try account.createKey(context: context)
        try insert("A wrote this", on: "2026-11-21", owner: pub)
        _ = account.signOut(context: context)
        let repo = JournalRepository(context: context, activeOwner: account.activeOwner)
        XCTAssertNil(account.activeOwner)
        try repo.save(text: "guest today", for: day("2026-11-21"))
        let rows = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.dateString == "2026-11-21" }))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first { $0.ownerPubkey == pub }?.notesText, "A wrote this", "A's row untouched")
        XCTAssertEqual(rows.first { $0.ownerPubkey == nil }?.notesText, "guest today")
    }

    func testConnectedEditorWritesOwnersRowOtherwiseGuest() throws {
        let pub = try account.createKey(context: context)
        try insert("owned", on: "2026-11-20", owner: pub)
        let repo = JournalRepository(context: context, activeOwner: pub)
        try repo.save(text: "owned, edited", for: day("2026-11-20"))
        try repo.save(text: "new day", for: day("2026-11-21"))
        let byDate = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<JournalEntry>()).map { ($0.dateString, $0) })
        XCTAssertEqual(byDate["2026-11-20"]?.ownerPubkey, pub)
        XCTAssertEqual(byDate["2026-11-20"]?.notesText, "owned, edited")
        XCTAssertNil(byDate["2026-11-21"]?.ownerPubkey, "a new row is a guest row until M5b publishes it")
    }

    func testCalendarShowsSignedOutAccountDaysReadOnly() throws {
        try insert("A's day", on: "2026-11-10", owner: "aa")
        try insert("mine", on: "2026-11-12", owner: nil)
        let repo = JournalRepository(context: context, activeOwner: nil)
        let model = CalendarModel(repository: repo, today: { self.day("2026-11-21") })
        let days = Dictionary(uniqueKeysWithValues: model.grid.compactMap { $0 }.map { ($0.dateString, $0) })
        XCTAssertEqual(days["2026-11-10"]?.otherAccountOnly, true)
        XCTAssertEqual(days["2026-11-10"]?.hasReflection, false)
        XCTAssertEqual(days["2026-11-12"]?.hasReflection, true)
        XCTAssertEqual(model.monthCount, 1, "another account's day never counts")
        XCTAssertEqual(model.otherAccountDayCount, 1)
        XCTAssertEqual(try repo.otherAccountText(for: "2026-11-10"), "A's day")
        XCTAssertEqual(try repo.text(for: day("2026-11-10")), "", "not the editor's row")
    }

    func testOtherAccountDaysNeverCountTowardMilestones() throws {
        for d in 1...6 { try insert("A", on: String(format: "2026-11-%02d", d), owner: "aa") }
        let repo = JournalRepository(context: context, activeOwner: nil)
        try repo.save(text: "first of mine", for: day("2026-11-21"))
        XCTAssertEqual(try repo.totalReflectionCount(), 1)
        XCTAssertEqual(try repo.takeMilestone(), 1, "the 1st, not the 7th")
    }

    // MARK: Remove account and local data (F8)

    func testRemoveDeletesKeyThenJournalAndKeepsBackupUnlessAsked() throws {
        let pub = try account.createKey(context: context)
        try account.backUpKey()
        try insert("mine", on: "2026-11-20", owner: pub)
        XCTAssertEqual(account.removeAccountAndData(context: context, store: store), .removed)
        XCTAssertNil(primary)
        XCTAssertEqual(account.state, .guest)
        XCTAssertEqual(try store.container!.mainContext.fetchCount(FetchDescriptor<JournalEntry>()), 0, "every reflection removed")
        guard case .backups(let list) = account.backups else { return XCTFail() }
        XCTAssertEqual(list.count, 1, "the backup is a separate question, default keep")
        XCTAssertTrue(account.deleteBackups(for: pub))
        XCTAssertEqual(account.backups, .backups([]))
    }

    func testRemoveAbortsBeforeTheJournalWhenKeyDeleteFails() throws {
        let pub = try account.createKey(context: context)
        try insert("mine", on: "2026-11-20", owner: pub)
        keychain.deleteStatus = errSecInternalError
        XCTAssertEqual(account.removeAccountAndData(context: context, store: store), .keyDeleteFailed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<JournalEntry>()), 1, "nothing deleted")
        XCTAssertEqual(account.state, .connected(pubkey: pub))
    }
}

/// Seth's M5a requirement 3: a failed migration never replaces the journal.
@MainActor
final class MigrationFailureTests: XCTestCase {
    @Model final class Unknown { var x: Int = 0; init() {} }

    func testFailedMigrationLeavesTheStoreUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        _ = try location.prepare()
        do {
            // A store whose model matches no version in the migration plan.
            let s = Schema([Unknown.self])
            let c = try ModelContainer(for: s, configurations: ModelConfiguration(schema: s, url: location.storeURL, cloudKitDatabase: .none))
            c.mainContext.insert(Unknown())
            try c.mainContext.save()
        }
        let before = try Data(contentsOf: location.storeURL)
        let store = JournalStore(location: location)
        store.openIfPossible(protectedDataAvailable: true)
        guard case .failed = store.state else { return XCTFail("expected the failed state, got \(store.state)") }
        XCTAssertNil(store.container, "never an empty journal")
        XCTAssertEqual(try Data(contentsOf: location.storeURL), before, "store file byte-for-byte unchanged")
    }
}

/// Audit M4 L1: rapid time changes end with the last pick scheduled.
@MainActor
final class ReminderSerializationTests: XCTestCase {
    final class SlowScheduler: NotificationScheduling, @unchecked Sendable {
        var scheduled: [Int] = []
        func requestAuthorization() async -> Bool { true }
        func isAuthorized() async -> Bool { true }
        func scheduleDaily(hour: Int, minute: Int, title: String, body: String) async throws {
            try? await Task.sleep(for: .milliseconds(30))
            scheduled.append(hour)
        }
        func cancelDaily() async {}
    }

    func testRapidTimeChangesScheduleTheLastPick() async {
        let scheduler = SlowScheduler()
        let model = ReminderModel(defaults: UserDefaults(suiteName: "t-\(UUID().uuidString)")!, scheduler: scheduler)
        func time(_ h: Int) -> Date { Calendar.current.date(from: DateComponents(hour: h, minute: 0))! }
        await model.turnOn(at: time(7))
        model.requestChange(to: time(8))
        model.requestChange(to: time(9))
        let last = model.requestChange(to: time(10))
        await last.value
        XCTAssertEqual(scheduler.scheduled.last, 10)
        XCTAssertEqual(model.hour, 10)
    }
}
