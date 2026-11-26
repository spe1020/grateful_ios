import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// M6: the conflict screen's model, copy and the V7 archive fields (Prep's
/// "M6 conflict screen"; Chief P31).
@MainActor
final class ConflictReviewTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    private var review: ConflictReview { ConflictReview(context: context, owner: owner, now: { self.t0 }) }

    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func remote(_ date: String, _ text: String, at: Int, private isPrivate: Bool = true) throws -> NostrEvent {
        let d = day(date)
        let template = isPrivate
            ? try DailyEntry.privateTemplate(day: d, notes: [text], privateKey: secret)
            : try DailyEntry.template(day: d, notes: [text])
        return try template.signed(privateKey: secret, createdAt: at)
    }

    /// A row with a pending local edit, then the relay version arrives
    /// through the importer: the real path to a conflict.
    @discardableResult
    private func conflict(_ date: String, local: String, localPrivate: Bool = true,
                          account: String, accountPrivate: Bool = true, at: Int = 500) throws -> NostrEvent {
        let d = day(date)
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: local, now: t0, ownerPubkey: owner)
        entry.isPrivate = localPrivate
        context.insert(entry)
        try context.save()
        let event = try remote(date, account, at: at, private: accountPrivate)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [event], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row(date).syncState, .conflict)
        return event
    }

    private func row(_ date: String) throws -> JournalEntry {
        let key: String? = JournalEntry.key(owner: owner, dateString: date)
        return try XCTUnwrap(context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first)
    }

    private func setAside() throws -> [EarlierVersion] {
        try JournalRepository(context: context, activeOwner: owner).setAsideVersions()
    }

    // MARK: - Loading

    func testImporterKeepsAccountPrivacyAndCreatedAt() throws {
        let event = try conflict("2026-11-20", local: "here", account: "there", accountPrivate: false, at: 777)
        let archive = try XCTUnwrap(context.fetch(FetchDescriptor<EarlierVersion>()).first { $0.reason == .remoteInConflict })
        XCTAssertFalse(archive.isPrivate)
        XCTAssertEqual(archive.eventCreatedAt, 777)
        XCTAssertEqual(archive.eventId, event.id)
    }

    func testLoadListsBothTextsWithLabelsAccountFirst() throws {
        try conflict("2026-11-20", local: "from this iPhone", account: "from web")
        let days = try review.load()
        XCTAssertEqual(days.items.count, 1)
        XCTAssertEqual(days.items[0].accountText, "from web")
        XCTAssertEqual(days.items[0].iPhoneText, "from this iPhone")
        XCTAssertFalse(days.items[0].afterSaving, "found on connecting/reading, not after saving")
        XCTAssertTrue(days.blocked.isEmpty)
    }

    /// §5: a blocked day with pending edits is listed apart, with no choice.
    func testBlockedConflictIsListedApartAndNeverChanged() throws {
        let d = day("2026-11-21")
        let row = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                               timeZoneID: zone.identifier, notesText: "written here", now: t0, ownerPubkey: owner)
        context.insert(row)
        try context.save()
        try RemoteImporter(context: context, owner: owner)
            .apply(["2026-11-21": .blocked(eventId: String(repeating: "a", count: 64), createdAt: 400)], zone: zone)
        let days = try review.load()
        XCTAssertEqual(days.blocked.map(\.dateString), ["2026-11-21"])
        XCTAssertTrue(days.items.isEmpty)
        try review.apply(["2026-11-21": .keepBoth])
        _ = try review.keepBothForAll()
        XCTAssertEqual(try self.row("2026-11-21").syncState, .conflict, "never changed here")
        XCTAssertEqual(try self.row("2026-11-21").notesText, "written here")
    }

    /// §6: a conflict found after the day was saved uses the re-check heading.
    func testAfterSavingWhenTheDayHadBeenAcknowledged() throws {
        try conflict("2026-11-20", local: "saved here", account: "changed elsewhere")
        let e = try remote("2026-11-20", "saved here", at: 450)
        let ob = try Outbox(context: context, owner: owner).enqueue(e, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        ob.ackedRelays = ["wss://a"]
        try context.save()
        XCTAssertTrue(try review.load().allAfterSaving)
    }

    /// Chief P33: the Today and day-view links only open the screen for a
    /// day it lists: never for a blocked today or a today deleted elsewhere.
    func testListsDayOnlyForDaysWithAChoice() throws {
        try conflict("2026-11-20", local: "mine", account: "theirs")
        XCTAssertTrue(try review.listsDay("2026-11-20"))

        let d = day("2026-11-21")
        let blocked = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                   timeZoneID: zone.identifier, notesText: "written here", now: t0, ownerPubkey: owner)
        context.insert(blocked)
        try context.save()
        try RemoteImporter(context: context, owner: owner)
            .apply(["2026-11-21": .blocked(eventId: String(repeating: "a", count: 64), createdAt: 400)], zone: zone)
        XCTAssertEqual(try row("2026-11-21").syncState, .conflict)
        XCTAssertFalse(try review.listsDay("2026-11-21"), "blocked today: no link to a screen of blocked rows")

        let base = try remote("2026-11-22", "old", at: 100)
        let e = day("2026-11-22")
        let deleted = JournalEntry(dateString: e.dateString, dayOfYear: e.dayOfYear, publishedAt: e.publishedAt,
                                   timeZoneID: zone.identifier, notesText: "old", now: t0, ownerPubkey: owner)
        deleted.remoteEventID = base.id
        deleted.remoteCreatedAt = base.createdAt
        context.insert(deleted)
        try context.save()
        deleted.notesText = "edited here"
        deleted.syncStateRaw = SyncState.localOnly.rawValue
        try context.save()
        let del = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-22", eventId: base.id)
            .signed(privateKey: secret, createdAt: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, del], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-22").syncState, .conflict)
        XCTAssertTrue(try review.listsDay("2026-11-22"), "§7: deleted elsewhere is a row with a choice")
    }

    // MARK: - Choices

    func testKeepBothJoinsAccountFirstAndPublishesNext() throws {
        let event = try conflict("2026-11-20", local: "iPhone 1\n\niPhone 2", account: "web 1")
        try review.apply(["2026-11-20": .keepBoth])
        let r = try row("2026-11-20")
        XCTAssertEqual(EntryNotes.split(r.notesText), ["web 1", "iPhone 1", "iPhone 2"])
        XCTAssertEqual(r.syncState, .localOnly, "published next, then shows Saving")
        XCTAssertEqual(r.remoteEventID, event.id, "based on the account's version")
        XCTAssertEqual(r.remoteCreatedAt, event.createdAt)
        XCTAssertTrue(try setAside().isEmpty, "nothing set aside: every word is on the day")
        XCTAssertTrue(try review.load().items.isEmpty)
    }

    /// Chief P31: only the account's text was private, so the combined day is.
    func testCombinedDayIsPrivateWhenOnlyAccountTextWasPrivate() throws {
        try conflict("2026-11-20", local: "public here", localPrivate: false, account: "private there", accountPrivate: true)
        XCTAssertTrue(try review.load().items[0].keepBothBecomesPrivate)
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(try row("2026-11-20").isPrivate)
    }

    func testCombinedDayIsPrivateWhenOnlyIPhoneTextWasPrivate() throws {
        try conflict("2026-11-20", local: "private here", localPrivate: true, account: "public there", accountPrivate: false)
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(try row("2026-11-20").isPrivate)
    }

    func testKeepOneKeepsItsOwnPrivacy() throws {
        try conflict("2026-11-20", local: "public here", localPrivate: false, account: "private there", accountPrivate: true)
        try review.apply(["2026-11-20": .keepThisIPhone])
        XCTAssertFalse(try row("2026-11-20").isPrivate)
        try conflict("2026-11-21", local: "private here", localPrivate: true, account: "public there", accountPrivate: false)
        try review.apply(["2026-11-21": .keepAccount])
        XCTAssertFalse(try row("2026-11-21").isPrivate)
    }

    func testKeepThisIPhoneSetsAccountTextAside() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "theirs")
        try review.apply(["2026-11-20": .keepThisIPhone])
        let r = try row("2026-11-20")
        XCTAssertEqual(r.notesText, "mine")
        XCTAssertEqual(r.syncState, .localOnly)
        XCTAssertEqual(r.remoteEventID, event.id)
        let aside = try setAside()
        XCTAssertEqual(aside.map(\.notesText), ["theirs"])
        XCTAssertEqual(aside.first?.reason, .notKept)
        XCTAssertTrue(try JournalRepository(context: context, activeOwner: owner).surfacedEarlierVersions().isEmpty,
                      "no 'replaced' Today line for a text the person chose not to keep")
    }

    func testKeepAccountSetsIPhoneTextAsideAndNeedsNoPublish() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "theirs", accountPrivate: false)
        try review.apply(["2026-11-20": .keepAccount])
        let r = try row("2026-11-20")
        XCTAssertEqual(r.notesText, "theirs")
        XCTAssertFalse(r.isPrivate)
        XCTAssertEqual(r.syncState, .synced, "already the account's version")
        XCTAssertEqual(r.remoteEventID, event.id)
        XCTAssertEqual(try setAside().map(\.notesText), ["mine"])
    }

    func testQueuedEventsFromBeforeTheChoiceAreNeverSent() throws {
        try conflict("2026-11-20", local: "mine", account: "theirs")
        let e = try remote("2026-11-20", "mine", at: 450)
        try Outbox(context: context, owner: owner).enqueue(e, dateString: "2026-11-20", baseEventId: nil, baseCreatedAt: nil)
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertNil(try Outbox(context: context, owner: owner).liveRow(dateString: "2026-11-20"))
    }

    /// Not now: loading changes nothing.
    func testLoadingChangesNothing() throws {
        try conflict("2026-11-20", local: "mine", account: "theirs")
        _ = try review.load()
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    // MARK: - Keep both for all

    func testKeepBothForAllAppliesToEveryChoiceAndSavesTheNotice() throws {
        try conflict("2026-11-20", local: "a", localPrivate: false, account: "b", accountPrivate: true)
        try conflict("2026-11-21", local: "c", account: "d")
        let kept = try review.keepBothForAll()
        XCTAssertEqual(kept.dates, ["2026-11-20", "2026-11-21"])
        XCTAssertTrue(kept.madePrivate)
        try review.saveKeptBothNotice(kept)
        XCTAssertEqual(try review.keptBothNotice(), kept)
        XCTAssertEqual(EntryNotes.split(try row("2026-11-21").notesText), ["d", "c"])
        try review.clearKeptBothNotice()
        XCTAssertNil(try review.keptBothNotice())
    }

    // MARK: - Publishing after a choice

    /// The kept day publishes: the pre-send check treats the account's
    /// version as the base, not as a new conflict.
    func testKeptDayPublishesAndIsNotStoppedByTheAccountVersion() async throws {
        let event = try conflict("2026-11-20", local: "mine", account: "theirs")
        try review.apply(["2026-11-20": .keepBoth])
        let relays = ["a", "b"].map { FakeRelay($0, events: [event]) }
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        let pass = PublishPass(context: context, owner: owner, secret: secret,
                               set: RelaySet(read: relays.map(\.url), write: relays.map(\.url)),
                               fetcher: fetcher, publisher: publisher, now: { self.t0 })
        let s = try await pass.run()
        XCTAssertEqual(s?.conflicts, 0)
        XCTAssertEqual(s?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }

    // MARK: - Copy

    func testHeadingsAndLines() {
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20"], afterSaving: false), "You wrote on November 20 in both places.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], afterSaving: false),
                       "You wrote on 3 days in both places.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20"], afterSaving: true),
                       "Your reflection for November 20 was also changed elsewhere.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], afterSaving: true),
                       "3 reflections were also changed elsewhere.")
        XCTAssertEqual(ConflictCopy.keptBoth(dates: ["2026-11-20"], madePrivate: false), "Kept both versions on November 20.")
        XCTAssertEqual(ConflictCopy.keptBoth(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], madePrivate: true),
                       "Kept both versions on 3 days. Days where either version was private are now private.")
        XCTAssertEqual(ConflictCopy.comeBack(dates: ["2026-11-20"]),
                       "Your reflection from November 20 was also changed elsewhere. Choose what to keep.")
        XCTAssertEqual(ConflictCopy.comeBack(dates: ["2026-11-20", "2026-11-21"]),
                       "2 reflections were also changed elsewhere. Choose what to keep.")
        for text in [ConflictCopy.subheading, ConflictCopy.keepBothLine, ConflictCopy.keepThisIPhoneLine, ConflictCopy.keepAccountLine,
                     ConflictCopy.privateWins, ConflictCopy.cantOpenAccount, ConflictCopy.cantCompareLine, ConflictCopy.notKeptReason] {
            for term in ["relay", "event", "sync", "key", "Nostr"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(term), "\(term) in \(text)")
            }
        }
    }

    // MARK: - V6 → V7

    func testV6StoreMigratesToV7AndOldArchivesReadAsPrivate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "v6-journal", withExtension: "store"))
        let location = StoreLocation(directory: root.appendingPathComponent("Store", isDirectory: true))
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: location.storeURL)
        let store = JournalStore(location: location, defaults: UserDefaults(suiteName: "v7-\(UUID().uuidString)")!)
        store.openIfPossible(protectedDataAvailable: true)
        let ctx = try XCTUnwrap(store.container, "\(store.state)").mainContext
        let rows = try ctx.fetch(FetchDescriptor<JournalEntry>(sortBy: [SortDescriptor(\.dateString)]))
        let o = String(repeating: "b", count: 64)
        XCTAssertEqual(rows.map(\.notesText), ["Guest note", "iPhone note"])
        XCTAssertEqual(rows[1].syncState, .conflict)
        let archive = try XCTUnwrap(ctx.fetch(FetchDescriptor<EarlierVersion>()).first)
        XCTAssertEqual(archive.notesText, "Account note")
        XCTAssertTrue(archive.isPrivate, "archived before V7: the stricter choice")
        XCTAssertNil(archive.eventCreatedAt)
        let outbox = try XCTUnwrap(ctx.fetch(FetchDescriptor<OutboxEvent>()).first)
        XCTAssertTrue(outbox.supersededByRemote)
        XCTAssertEqual(outbox.ackedRelays, ["wss://nos.lol"])
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<AccountMarker>()).first?.pubkey, o)
        // The migrated conflict can be reviewed and kept private.
        let days = try ConflictReview(context: ctx, owner: o).load()
        XCTAssertEqual(days.items.first?.accountText, "Account note")
        XCTAssertTrue(days.allAfterSaving)
        try ConflictReview(context: ctx, owner: o).apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(rows[1].isPrivate)
        XCTAssertEqual(EntryNotes.split(rows[1].notesText), ["Account note", "iPhone note"])
    }

    // MARK: - Audit FAIL at 7f2dc6f

    /// M1: a resolved conflict's archive is never offered for a later one.
    func testResolvedArchiveIsNotReusedForLaterDeletionConflict() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "old account text", at: 500)
        try review.apply(["2026-11-20": .keepThisIPhone])
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
        // Before this iPhone's edit is sent, another device deletes the day.
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: event.id)
            .signed(privateKey: secret, createdAt: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [event, k5], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try review.load().items.map(\.kind), [.deletedFromAccount], "§7 row, no stale 'Your account' text")
        XCTAssertEqual(try review.load().items.map(\.accountText), [""])
        XCTAssertTrue(try review.listsDay("2026-11-20"))
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict, "never marked synced with stale text")
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    /// M1: a second, newer remote version after a resolved conflict is shown,
    /// not the first one.
    func testSecondConflictShowsTheNewerAccountText() throws {
        try conflict("2026-11-20", local: "mine", account: "first", at: 500)
        try review.apply(["2026-11-20": .keepThisIPhone])
        let second = try remote("2026-11-20", "second", at: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [second], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try review.load().items.map(\.accountText), ["second"])
    }

    /// M2: deleted on this iPhone, edited elsewhere: a §9 row. A choice it
    /// doesn't offer, and Keep both for all, change nothing.
    func testLocalDeleteVsRemoteEditIsNotOfferedOrChanged() throws {
        let base = try remote("2026-11-20", "v1", at: 100)
        let d = day("2026-11-20")
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: "", now: t0, ownerPubkey: owner)
        entry.remoteEventID = base.id; entry.remoteCreatedAt = 100; entry.deletedAt = t0
        context.insert(entry); try context.save()
        let edit = try remote("2026-11-20", "edited elsewhere", at: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, edit], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        let items = try review.load().items
        XCTAssertEqual(items.map(\.kind), [.deletedHere])
        XCTAssertEqual(items.map(\.accountText), ["edited elsewhere"])
        XCTAssertEqual(items.map(\.iPhoneText), [""])
        XCTAssertEqual(items.first?.choices, [.keepAccount, .deleteEverywhere])
        try review.apply(["2026-11-20": .keepThisIPhone])
        _ = try review.keepBothForAll()
        let r = try row("2026-11-20")
        XCTAssertNotNil(r.deletedAt, "the person's delete stands")
        XCTAssertEqual(r.syncState, .conflict, "nothing published until the person chooses")
        XCTAssertEqual(try earlier("2026-11-20"), ["edited elsewhere"], "the account's text is kept")
    }

    /// P34: deleted on the account, edited here: a §7 row. A choice it
    /// doesn't offer, and Keep both for all, change nothing.
    func testAccountDeleteVsLocalEditIsNotOfferedOrChanged() throws {
        let base = try remote("2026-11-20", "v1", at: 100)
        let d = day("2026-11-20")
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: "edited here", now: t0, ownerPubkey: owner)
        entry.remoteEventID = base.id; entry.remoteCreatedAt = 100
        context.insert(entry); try context.save()
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: base.id)
            .signed(privateKey: secret, createdAt: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, k5], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        let items = try review.load().items
        XCTAssertEqual(items.map(\.kind), [.deletedFromAccount])
        XCTAssertEqual(items.first?.choices, [.keepThisIPhone, .letItStayDeleted])
        XCTAssertFalse(try review.load().showsKeepBothForAll)
        try review.apply(["2026-11-20": .keepAccount])
        _ = try review.keepBothForAll()
        let r = try row("2026-11-20")
        XCTAssertEqual(r.notesText, "edited here")
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.syncState, .conflict)
    }

    /// M1/P34: an open conflict the account then deletes. The earlier
    /// account text is no longer the account's; the day becomes a §7 row.
    func testOpenConflictThenAccountDeleteBecomesADeletedRow() throws {
        let event = try conflict("2026-11-20", local: "mine", account: "account text", at: 500)
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-20", eventId: event.id)
            .signed(privateKey: secret, createdAt: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [event, k5], owner: owner, privateKey: secret), zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try review.load().items.map(\.kind), [.deletedFromAccount])
        XCTAssertEqual(try review.load().items.map(\.accountText), [""], "the deleted account text isn't offered")
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict, "never marked synced with deleted text")
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    /// The same, found by the pre-send check rather than on connecting.
    func testOpenConflictThenAccountDeleteFoundBeforeSendingBecomesADeletedRow() throws {
        _ = try conflict("2026-11-20", local: "mine", account: "account text", at: 500)
        try RemoteImporter(context: context, owner: owner)
            .conflict(dateString: "2026-11-20", remote: .deleted(at: 900, by: []))
        XCTAssertEqual(try review.load().items.map(\.kind), [.deletedFromAccount])
        XCTAssertEqual(try review.load().items.map(\.accountText), [""])
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
    }

    // MARK: - Audit #16 L2

    private func blockedConflict(_ date: String, local: String, at: Int = 400) throws {
        let d = day(date)
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: local, now: t0, ownerPubkey: owner))
        try context.save()
        try RemoteImporter(context: context, owner: owner)
            .apply([date: .blocked(eventId: String(repeating: "a", count: 64), createdAt: at)], zone: zone)
        XCTAssertEqual(try review.load().blocked.map(\.dateString), [date])
    }

    /// L2: blocked, then readable: a normal row, no longer blocked.
    func testBlockedDayThatBecomesReadableLeavesCantCompare() throws {
        try blockedConflict("2026-11-21", local: "written here")
        let readable = try remote("2026-11-21", "account text", at: 500)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [readable], owner: owner, privateKey: secret), zone: zone)
        let days = try review.load()
        XCTAssertTrue(days.blocked.isEmpty)
        XCTAssertEqual(days.items.map(\.accountText), ["account text"])
    }

    /// L2 (Audit's case): blocked, then readable, then deleted on the
    /// account: never back under "Can't compare these yet".
    func testBlockedThenReadableThenDeletedIsNotBlockedAgain() throws {
        try blockedConflict("2026-11-21", local: "written here")
        let readable = try remote("2026-11-21", "account text", at: 500)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [readable], owner: owner, privateKey: secret), zone: zone)
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: "2026-11-21", eventId: readable.id)
            .signed(privateKey: secret, createdAt: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [readable, k5], owner: owner, privateKey: secret), zone: zone)
        let days = try review.load()
        XCTAssertTrue(days.blocked.isEmpty, "not shown as unreadable again")
        XCTAssertEqual(days.items.map(\.kind), [.deletedFromAccount], "§10: a §7 row")
        XCTAssertEqual(try row("2026-11-21").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-21").notesText, "written here")
    }

    /// L2: blocked, then deleted on the account.
    func testBlockedThenDeletedLeavesCantCompare() throws {
        try blockedConflict("2026-11-21", local: "written here")
        try RemoteImporter(context: context, owner: owner)
            .apply(["2026-11-21": .deleted(at: 900, by: [])], zone: zone)
        XCTAssertTrue(try review.load().blocked.isEmpty)
        XCTAssertEqual(try row("2026-11-21").notesText, "written here")
    }

    // MARK: - §7, §8, §9 (publishing PR, Chief P32/P35)

    /// §7 setup: written here, then deleted on the account at 900.
    private func deletedFromAccount(_ date: String, local: String) throws -> NostrEvent {
        let base = try remote(date, "v1", at: 100)
        let d = day(date)
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: local, now: t0, ownerPubkey: owner)
        entry.remoteEventID = base.id; entry.remoteCreatedAt = 100
        context.insert(entry); try context.save()
        let k5 = try EntryDeletion.template(pubkey: owner, dateString: date, eventId: base.id)
            .signed(privateKey: secret, createdAt: 900)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, k5], owner: owner, privateKey: secret), zone: zone)
        return k5
    }

    /// §9 setup: deleted here, then edited on the account at 200.
    @discardableResult
    private func deletedHere(_ date: String, account: String) throws -> NostrEvent {
        let base = try remote(date, "v1", at: 100)
        let d = day(date)
        let entry = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                 timeZoneID: zone.identifier, notesText: "", now: t0, ownerPubkey: owner)
        entry.remoteEventID = base.id; entry.remoteCreatedAt = 100; entry.deletedAt = t0
        context.insert(entry); try context.save()
        let edit = try remote(date, account, at: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, edit], owner: owner, privateKey: secret), zone: zone)
        return edit
    }

    private func setAsideItems(_ date: String) throws -> [(String, EarlierVersionReason)] {
        try setAside().filter { $0.dateString == date }.map { ($0.notesText, $0.reason) }
    }

    /// §7 Keep this iPhone's: the day goes back, signed after the deletion,
    /// and meeting the same deletion again isn't a new conflict.
    func testDeletedFromAccountKeepThisIPhoneRestoresTheDay() throws {
        let k5 = try deletedFromAccount("2026-11-20", local: "written here")
        try review.apply(["2026-11-20": .keepThisIPhone])
        var r = try row("2026-11-20")
        XCTAssertEqual(r.syncState, .localOnly, "published next")
        XCTAssertEqual(r.notesText, "written here")
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.remoteCreatedAt, 900, "signed after the deletion")
        XCTAssertTrue(try setAsideItems("2026-11-20").isEmpty)
        XCTAssertTrue(try review.load().items.isEmpty)
        let base = try remote("2026-11-20", "v1", at: 100)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [base, k5], owner: owner, privateKey: secret), zone: zone)
        r = try row("2026-11-20")
        XCTAssertEqual(r.syncState, .localOnly, "the same deletion again is nothing new")
        XCTAssertEqual(r.notesText, "written here")
    }

    /// §7 Let it stay deleted: this iPhone's text goes to Set aside with
    /// §7's reason, and the day is removed here.
    func testDeletedFromAccountLetItStayDeleted() throws {
        _ = try deletedFromAccount("2026-11-20", local: "written here")
        try review.apply(["2026-11-20": .letItStayDeleted])
        let r = try row("2026-11-20")
        XCTAssertNotNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "")
        XCTAssertEqual(r.syncState, .synced, "nothing to send: the account already deleted it")
        let items = try setAsideItems("2026-11-20")
        XCTAssertEqual(items.map(\.0), ["written here"])
        XCTAssertEqual(items.map(\.1), [.deletedFromAccount])
        XCTAssertEqual(ConflictCopy.setAsideReason(.deletedFromAccount), "This day was deleted from your account.")
    }

    /// §9 Keep your account's: the day comes back with the account's text.
    func testDeletedHereKeepAccountRestoresTheDay() throws {
        let edit = try deletedHere("2026-11-20", account: "edited elsewhere")
        try review.apply(["2026-11-20": .keepAccount])
        let r = try row("2026-11-20")
        XCTAssertNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "edited elsewhere")
        XCTAssertEqual(r.syncState, .synced)
        XCTAssertEqual(r.remoteEventID, edit.id)
        XCTAssertTrue(try setAsideItems("2026-11-20").isEmpty)
    }

    /// §9 Delete it everywhere: the account's text goes to Set aside with
    /// §9's reason; the day stays deleted and a deletion is sent next.
    func testDeletedHereDeleteEverywhere() throws {
        let edit = try deletedHere("2026-11-20", account: "edited elsewhere")
        try review.apply(["2026-11-20": .deleteEverywhere])
        let r = try row("2026-11-20")
        XCTAssertNotNil(r.deletedAt)
        XCTAssertEqual(r.notesText, "")
        XCTAssertEqual(r.syncState, .localOnly, "a deletion is sent next")
        XCTAssertEqual(r.remoteEventID, edit.id, "it covers the account's version")
        XCTAssertEqual(r.remoteCreatedAt, 200)
        let items = try setAsideItems("2026-11-20")
        XCTAssertEqual(items.map(\.0), ["edited elsewhere"])
        XCTAssertEqual(items.map(\.1), [.deletedHere])
        XCTAssertEqual(ConflictCopy.setAsideReason(.deletedHere), "You deleted this day here.")
    }

    /// Keep both for all skips §7 and §9 rows; they stay on the screen.
    func testKeepBothForAllSkipsDeletionRows() throws {
        try conflict("2026-11-19", local: "mine", account: "theirs")
        _ = try deletedFromAccount("2026-11-20", local: "written here")
        try deletedHere("2026-11-21", account: "edited elsewhere")
        XCTAssertTrue(try review.load().showsKeepBothForAll)
        let kept = try review.keepBothForAll()
        XCTAssertEqual(kept.dates, ["2026-11-19"])
        let left = try review.load()
        XCTAssertEqual(left.items.map(\.dateString), ["2026-11-20", "2026-11-21"])
        XCTAssertFalse(left.showsKeepBothForAll, "hidden when only these rows are left")
        XCTAssertEqual(ConflictCopy.comeBack(dates: left.items.map(\.dateString)),
                       "2 reflections were also changed elsewhere. Choose what to keep.", "the come-back line counts them")
    }

    /// §8: Keep both past one event's size: a warning on the row, Keep
    /// both stays the default, Keep both for all skips it; after keeping
    /// both, the day view says it stays on this iPhone.
    func testKeepBothTooLongWarnsAndIsSkippedByKeepBothForAll() throws {
        let half = String(repeating: "a", count: DailyEntry.maxContentBytes / 2 + 10)
        try conflict("2026-11-20", local: half, account: half + "b")
        let item = try XCTUnwrap(review.load().items.first)
        XCTAssertTrue(item.keepBothTooLong)
        XCTAssertEqual(item.defaultChoice, .keepBoth)
        XCTAssertFalse(item.keepBothForAllApplies)
        XCTAssertEqual(try review.keepBothForAll().dates, [])
        XCTAssertEqual(try review.load().items.count, 1, "stays on the screen")
        try review.apply(["2026-11-20": .keepBoth])
        XCTAssertTrue(try setAsideItems("2026-11-20").isEmpty, "nothing goes to Set aside")
        XCTAssertEqual(try review.dayLine("2026-11-20", isToday: false), .tooLong(isToday: false))
        XCTAssertEqual(ConflictCopy.dayLine(.tooLong(isToday: false)),
                       "This reflection is too long to save to your account. It's kept on this iPhone only.")
        XCTAssertEqual(ConflictCopy.dayLine(.tooLong(isToday: true)),
                       "This reflection is too long to save to your account. It's kept on this iPhone. Shorten it to save it.")
    }

    /// Day-view lines per case (§7, §9, "Coming back later").
    func testDayLines() throws {
        try conflict("2026-11-19", local: "mine", account: "theirs")
        _ = try deletedFromAccount("2026-11-20", local: "written here")
        try deletedHere("2026-11-21", account: "edited elsewhere")
        XCTAssertEqual(try review.dayLine("2026-11-19", isToday: false), .alsoChangedElsewhere)
        XCTAssertEqual(try review.dayLine("2026-11-20", isToday: false), .deletedFromAccount)
        XCTAssertEqual(try review.dayLine("2026-11-21", isToday: false), .deletedHere)
        XCTAssertNil(try review.dayLine("2026-11-22", isToday: false))
        XCTAssertEqual(ConflictCopy.dayLine(.deletedFromAccount),
                       "This day was deleted from your account. What you wrote here is kept on this iPhone.")
        XCTAssertEqual(ConflictCopy.dayLine(.deletedHere),
                       "You deleted this day here, but it was changed in your account. Choose what to keep.")
    }

    /// §7/§9 headings when every row is that case; mixed rows use §1.
    func testDeletionHeadings() {
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20"], afterSaving: false, allKind: .deletedFromAccount),
                       "November 20 was deleted from your account, but you changed it on this iPhone.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], afterSaving: false, allKind: .deletedFromAccount),
                       "3 days were deleted from your account, but you changed them on this iPhone.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20"], afterSaving: false, allKind: .deletedHere),
                       "You deleted November 20 here, but it was changed in your account.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21", "2026-11-22"], afterSaving: false, allKind: .deletedHere),
                       "You deleted 3 days here, but they were changed in your account.")
        XCTAssertEqual(ConflictCopy.heading(dates: ["2026-11-20", "2026-11-21"], afterSaving: false, allKind: nil),
                       "You wrote on 2 days in both places.")
    }

    /// Acceptance 6: every conflict day has a row or a day-view line,
    /// including an unreadable version found before sending.
    func testUnreadableVersionFoundBeforeSendingIsListedAsBlocked() throws {
        let d = day("2026-11-21")
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: "written here", now: t0, ownerPubkey: owner))
        try context.save()
        try RemoteImporter(context: context, owner: owner)
            .conflict(dateString: "2026-11-21", remote: .blocked(eventId: String(repeating: "b", count: 64), createdAt: 400))
        XCTAssertEqual(try review.load().blocked.map(\.dateString), ["2026-11-21"])
    }

    private func earlier(_ date: String) throws -> [String] {
        try context.fetch(FetchDescriptor<EarlierVersion>()).filter { $0.dateString == date && $0.reason == .remoteInConflict }.map(\.notesText)
    }
}
