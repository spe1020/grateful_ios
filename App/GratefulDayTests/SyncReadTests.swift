import XCTest
import SwiftData
import Security
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// M5b-1: relay set (A2), end-to-end read, lagging relays, and the L-fixes.
@MainActor
final class SyncReadTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }

    private func fakes(_ relays: [FakeRelay]) -> FakeTransport {
        FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
    }

    // A2 / Option A

    func testUnresolvedRelayListNeverFallsBackToDefaultWriteRelays() {
        let result = FetchResult(events: [], outcomes: [RelaySet.defaultRead[0]: .answered, RelaySet.defaultRead[1]: .timedOut])
        let lookup = RelaySet.lookup(result, owner: owner, bootstrap: Array(RelaySet.defaultRead.prefix(3)))
        XCTAssertEqual(lookup, .unresolved)
        let set = RelaySet.from(lookup)
        XCTAssertNil(set.write, "write set unknown: never the defaults")
        XCTAssertEqual(set.read, RelaySet.defaultRead, "reading may use the defaults")
    }

    func testResolvedNoListUsesDefaults() {
        let boot = Array(RelaySet.defaultRead.prefix(3))
        let result = FetchResult(events: [], outcomes: [boot[0]: .answered, boot[1]: .answered, boot[2]: .timedOut])
        XCTAssertEqual(RelaySet.from(RelaySet.lookup(result, owner: owner, bootstrap: boot)).write, RelaySet.defaultWrite)
    }

    func testExplicitListNeverGetsDefaultRelaysAdded() throws {
        let list = try UnsignedEvent(kind: 10002, tags: [["r", "wss://My.Relay/"], ["r", "wss://read.only", "read"]], content: "")
            .signed(privateKey: secret, createdAt: 1)
        let set = RelaySet.from(.found(list))
        XCTAssertEqual(set.write, [URL(string: "wss://my.relay")!], "single write relay, normalized, no defaults")
        XCTAssertEqual(Set(set.read), [URL(string: "wss://my.relay")!, URL(string: "wss://read.only")!])
    }

    func testZeroWriteRelaysInExplicitListIsEmptyNotDefaults() throws {
        let list = try UnsignedEvent(kind: 10002, tags: [["r", "wss://read.only", "read"]], content: "").signed(privateKey: secret, createdAt: 1)
        XCTAssertEqual(RelaySet.from(.found(list)).write, [], "nothing to publish to; never the defaults")
    }

    // End to end (read only)

    func testSyncServiceImportsAndPublishesNothing() async throws {
        let zone = TimeZone.current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let day = DailyEntry.Day(containing: cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!, timeZone: zone)
        let event = try DailyEntry.privateTemplate(day: day, notes: ["from web"], privateKey: secret).signed(privateKey: secret, createdAt: 100)
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!, events: [event]) }
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JournalStore.schema, configurations: config)
        let sync = SyncService(transport: fakes(relays))
        await sync.run(owner: owner, secret: secret, context: container.mainContext)
        guard case .done(let summary) = sync.status else { return XCTFail("\(sync.status)") }
        XCTAssertEqual(summary.imported, 1)
        let key: String? = JournalEntry.key(owner: owner, dateString: "2026-11-20")
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first?.notesText, "from web")
        for r in relays {
            XCTAssertTrue(r.requests.allSatisfy { $0["kinds"] != nil }, "only REQs were sent")
        }
        XCTAssertEqual(sync.relays?.write, RelaySet.defaultWrite)
    }

    func testOlderCopyFromLaggingRelayIsIgnored() throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JournalStore.schema, configurations: config)
        let ctx = container.mainContext
        let r = JournalEntry(dateString: "2026-11-20", dayOfYear: 324, publishedAt: 1, timeZoneID: "UTC", notesText: "newer", now: .now, ownerPubkey: owner)
        r.syncStateRaw = SyncState.synced.rawValue; r.remoteEventID = "v2"; r.remoteCreatedAt = 200
        ctx.insert(r); try ctx.save()
        let dummy = NostrEvent(id: "v1", pubkey: owner, createdAt: 100, kind: 36669, tags: [], content: "", sig: "")
        try RemoteImporter(context: ctx, owner: owner).apply(["2026-11-20": .entry(text: "older", isPrivate: true, eventId: "v1", createdAt: 100, event: dummy)])
        XCTAssertEqual(r.notesText, "newer")
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<EarlierVersion>()).isEmpty)
    }

    // Audit M5a L3

    func testUnreadableBackupIsSkippedNotBlocking() throws {
        let keychain = FakeKeychain()
        let vault = KeyVault(keychain: keychain)
        _ = try vault.saveBackup(secret)
        _ = keychain.add(Data("garbage".utf8), service: KeyVault.backupService, account: "bk_bad", synchronizable: true,
                         accessibility: kSecAttrAccessibleWhenUnlocked)
        guard case .backups(let list) = vault.listBackups() else { return XCTFail() }
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(vault.skippedBackups, 1)
    }

    // Audit #13 L1

    func testKeyDeleteUnconfirmedIsDistinctFromFailed() throws {
        let keychain = FakeKeychain()
        let vault = KeyVault(keychain: keychain)
        _ = try vault.savePrimaryVerified(secret)
        keychain.forcedRead = .locked
        XCTAssertEqual(vault.deletePrimary(), .unconfirmed, "deleted, but the re-read couldn't confirm it")
        keychain.forcedRead = nil
        _ = try vault.savePrimaryVerified(secret)
        keychain.deleteStatus = errSecInternalError
        XCTAssertEqual(vault.deletePrimary(), .deleteFailed)
        XCTAssertFalse(AccountCopy.removeUnconfirmed.contains("Nothing has been deleted"))
        XCTAssertFalse(AccountCopy.signOutUnconfirmed.contains("Nothing has changed"))
    }
}

/// Audit M5a L1/L4 and #13 L2 against a real on-disk store.
@MainActor
final class StoreLifecycleTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults = UserDefaults(suiteName: "life-\(UUID().uuidString)")!
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }

    private func location() -> StoreLocation { StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true)) }

    func testWriteAfterRemovalSurvivesReopen() throws {
        let store = JournalStore(location: location(), defaults: defaults)
        store.openIfPossible(protectedDataAvailable: true)
        let day = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000))
        try JournalRepository(context: store.container!.mainContext).save(text: "before", for: day)
        XCTAssertTrue(store.removeAllData())
        try JournalRepository(context: store.container!.mainContext).save(text: "after removal", for: day)
        let reopened = JournalStore(location: location(), defaults: defaults)
        reopened.openIfPossible(protectedDataAvailable: true)
        XCTAssertEqual(try JournalRepository(context: reopened.container!.mainContext).text(for: day), "after removal")
    }

    func testRemovalFlagClearedOnFirstGoodOpen() {
        let store = JournalStore(location: location(), defaults: defaults)
        store.removalIncomplete = true   // killed after the delete, before the reopen
        let next = JournalStore(location: location(), defaults: defaults)
        next.openIfPossible(protectedDataAvailable: true)
        XCTAssertNotNil(next.container)
        XCTAssertFalse(next.removalIncomplete)
    }

    func testReinstallMissingMarkerIsWrittenWhenSigningOut() throws {
        let store = JournalStore(location: location(), defaults: defaults)
        store.openIfPossible(protectedDataAvailable: true)
        let ctx = store.container!.mainContext
        let keychain = FakeKeychain()
        let secret = try NostrKeys.generatePrivateKey()
        _ = keychain.add(secret, service: KeyVault.primaryService, account: KeyVault.primaryAccount,
                         synchronizable: false, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        let account = AccountModel(vault: KeyVault(keychain: keychain))
        account.refresh(context: ctx)
        // Simulate the earlier marker write having failed.
        for m in try ctx.fetch(FetchDescriptor<AccountMarker>()) { ctx.delete(m) }
        try ctx.save()
        XCTAssertEqual(account.signOut(context: ctx), .signedOut, "the missing marker is written, not a block")
    }

    /// Prep F7/F8 [Try again]: an unconfirmed delete leaves the account
    /// where it was, so retrying re-runs the delete and its confirmation
    /// rather than being blocked; the journal is untouched until then.
    func testUnconfirmedKeyDeleteCanBeRetried() throws {
        let store = JournalStore(location: location(), defaults: defaults)
        store.openIfPossible(protectedDataAvailable: true)
        let ctx = store.container!.mainContext
        let keychain = FakeKeychain()
        let secret = try NostrKeys.generatePrivateKey()
        _ = keychain.add(secret, service: KeyVault.primaryService, account: KeyVault.primaryAccount,
                         synchronizable: false, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        let account = AccountModel(vault: KeyVault(keychain: keychain))
        account.refresh(context: ctx)
        let pubkey = KeyVault.pubkeyHex(for: secret)!
        let day = JournalDay(containing: Date(timeIntervalSince1970: 1_795_300_000))
        try JournalRepository(context: ctx, activeOwner: pubkey).save(text: "kept", for: day)

        keychain.forcedRead = .locked
        XCTAssertEqual(account.removeAccountAndData(context: ctx, store: store), .keyDeleteUnconfirmed)
        XCTAssertEqual(account.state, .connected(pubkey: pubkey), "not moved to a state that blocks the retry")
        XCTAssertEqual(try JournalRepository(context: store.container!.mainContext, activeOwner: pubkey).entry(for: day.dateString)?.notesText, "kept")

        keychain.forcedRead = nil
        XCTAssertEqual(account.removeAccountAndData(context: store.container!.mainContext, store: store), .removed, "the retry confirms and only then clears")
    }
}
