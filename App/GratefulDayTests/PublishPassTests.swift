import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// M5b-2 slice 2: the publish pass end to end against fake relays (M5b plan
/// r2, r2.1, P22; interop r5.1 §0.1; Seth 5c471a7e, 3f1c5fd4; Audit A2, M3a
/// I4; Chief P29). Test-plan rows are named in each test's comment.
@MainActor
final class PublishPassTests: XCTestCase {
    private let secret = try! NostrKeys.generatePrivateKey()
    private let otherSecret = try! NostrKeys.generatePrivateKey()
    private var owner: String { KeyVault.pubkeyHex(for: secret)! }
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let zone = TimeZone(identifier: "America/Chicago")!

    override func setUp() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: JournalStore.schema, configurations: config)
    }

    // MARK: - Helpers

    private func day(_ date: String) -> DailyEntry.Day {
        let p = date.split(separator: "-").compactMap { Int($0) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return DailyEntry.Day(containing: cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))!, timeZone: zone)
    }

    private func remote(_ date: String, _ text: String, at: Int, key: Data? = nil) throws -> NostrEvent {
        let k = key ?? secret
        return try DailyEntry.privateTemplate(day: day(date), notes: [text], privateKey: k).signed(privateKey: k, createdAt: at)
    }

    /// An owner row, optionally based on a relay version (then `.synced`).
    @discardableResult
    private func entry(_ date: String, _ text: String, base: NostrEvent? = nil, owner o: String? = nil) throws -> JournalEntry {
        let d = day(date)
        let row = JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                               timeZoneID: zone.identifier, notesText: text, now: t0, ownerPubkey: o ?? owner)
        if let base {
            row.remoteEventID = base.id
            row.remoteCreatedAt = base.createdAt
            row.syncStateRaw = SyncState.synced.rawValue
        }
        context.insert(row)
        try context.save()
        return row
    }

    private func row(_ date: String, owner o: String? = nil) throws -> JournalEntry {
        let key: String? = JournalEntry.key(owner: o ?? owner, dateString: date)
        return try XCTUnwrap(context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.entryKey == key })).first)
    }

    private func edit(_ date: String, _ text: String, at: Date) throws {
        let r = try row(date)
        r.notesText = text
        r.deletedAt = nil
        r.updatedAt = at
        if r.syncState == .synced { r.syncStateRaw = SyncState.localOnly.rawValue }
        try context.save()
    }

    private func delete(_ date: String, at: Date) throws {
        let r = try row(date)
        r.notesText = ""
        r.deletedAt = at
        r.updatedAt = at
        if r.syncState == .synced { r.syncStateRaw = SyncState.localOnly.rawValue }
        try context.save()
    }

    private func pass(_ relays: [FakeRelay], read: [FakeRelay] = [], write: [URL]?, key: Data? = nil,
                      at: Date? = nil, isCurrent: @escaping @MainActor () -> Bool = { true }) -> PublishPass {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: (relays + read).map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        let k = key ?? secret
        let now = at ?? t0
        return PublishPass(context: context, owner: KeyVault.pubkeyHex(for: k)!, secret: k,
                           set: RelaySet(read: (relays + read).map(\.url), write: write),
                           fetcher: fetcher, publisher: publisher, isCurrent: isCurrent, now: { now })
    }

    private func relays(_ names: String..., reply: FakeRelay.OkReply = .accept, events: [NostrEvent] = []) -> [FakeRelay] {
        names.map { let r = FakeRelay($0, events: events); r.okReply = reply; return r }
    }

    private func sent(_ relay: FakeRelay) -> [NostrEvent] {
        relay.publishedFrames.compactMap { frame in
            guard let a = try? JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [Any], a.count == 2,
                  let data = try? JSONSerialization.data(withJSONObject: a[1]) else { return nil }
            return try? JSONDecoder().decode(NostrEvent.self, from: data)
        }
    }

    private func outbox(_ key: Data? = nil) -> Outbox {
        Outbox(context: context, owner: KeyVault.pubkeyHex(for: key ?? secret)!)
    }

    private func earlier(_ date: String) throws -> [EarlierVersion] {
        try context.fetch(FetchDescriptor<EarlierVersion>()).filter { $0.dateString == date }
    }

    // MARK: - Publishing and acknowledgements

    /// C1: OK true from 2 distinct write relays is synced; the entry is then
    /// based on the event it published.
    func testPublishesNewDayAndTwoAcksMarkItSynced() async throws {
        try entry("2026-11-20", "first light")
        let w = relays("a", "b", "c")
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.signed, 1)
        XCTAssertEqual(s?.synced, 1)
        let r = try row("2026-11-20")
        XCTAssertEqual(r.syncState, .synced)
        for relay in w {
            let events = sent(relay)
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(events.first?.id, r.remoteEventID)
            XCTAssertEqual(try NIP44.decryptFromSelf(events[0].content, privateKey: secret), "first light")
        }
    }

    /// C2, C7: 1 ack of 3 is sent, not synced, and the day keeps its local
    /// label; the retry sends the stored event byte for byte.
    func testOneAckOfThreeStaysPendingAndRetrySendsSameBytes() async throws {
        try entry("2026-11-20", "one ack")
        let first = relays("a") + relays("b", "c", reply: .reject)
        _ = try await pass(first, write: first.map(\.url)).run()
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
        XCTAssertEqual(try outbox().state(dateString: "2026-11-20", write: first.map(\.url)), .sent)

        let again = relays("a", "b", "c")
        again[0].events = first[0].events
        let s = try await pass(again, write: again.map(\.url), at: t0.addingTimeInterval(3600)).run()
        XCTAssertEqual(s?.signed, 0, "no re-sign for a delivery failure")
        XCTAssertEqual(again[1].publishedFrames, first[1].publishedFrames, "same id, created_at and sig")
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }

    /// The importer never marks a day synced because this device's own event
    /// was seen on a relay: only the outbox's acks do.
    func testOwnEventSeenOnOneRelayDoesNotMarkDaySynced() async throws {
        try entry("2026-11-20", "own")
        let w = relays("a") + relays("b", "c", reply: .reject)
        _ = try await pass(w, write: w.map(\.url)).run()
        let days = RemoteJournal.days(from: w[0].events, owner: owner, privateKey: secret)
        try RemoteImporter(context: context, owner: owner).apply(days, zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
    }

    // MARK: - §0.1 lookup gate (P29: the .unresolved gate)

    /// B1: 2 empty answers of 3 publish; the silent relay is asked again later.
    func testTwoEmptyOfThreePublishAndSilentRelayIsRemembered() async throws {
        try entry("2026-11-20", "two answers")
        let w = relays("a", "b") + [FakeRelay("c", behavior: .silent)]
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.synced, 1)
        let r = try XCTUnwrap(outbox().liveRow(dateString: "2026-11-20"))
        XCTAssertEqual(r.recheckRelays, [w[2].url])
    }

    /// B2: 1 empty answer of 3 defers quietly; nothing is sent; text kept.
    func testOneEmptyOfThreeDefersAndSendsNothing() async throws {
        try entry("2026-11-20", "not yet")
        let w = relays("a") + [FakeRelay("b", behavior: .silent), FakeRelay("c", behavior: .closeWithAuth)]
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.deferred, 1)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try row("2026-11-20").notesText, "not yet")
        XCTAssertNotNil(try outbox().liveRow(dateString: "2026-11-20")?.nextAttemptAt, "retried with backoff")
    }

    /// L3 saturation: a write relay whose page was capped is `.unresolved`
    /// and never counts toward "no copy".
    func testSaturatedWriteRelayNeverPermitsPublish() async throws {
        try entry("2026-11-20", "capped")
        // Two versions in one second, a page size of 1: relay "b" is capped.
        let x = try remote("2026-11-20", "x", at: 500, key: otherSecret)
        let y = try remote("2026-11-20", "y", at: 500, key: otherSecret)
        let z = try remote("2026-11-20", "z", at: 400, key: otherSecret)
        let b = FakeRelay("b", events: [x, y, z], pageCap: 1)
        let w = relays("a") + [b]
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.deferred, 1, "other authors' events are ignored, but the capped relay still isn't an answer")
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// B5, B6: a single write relay's empty answer publishes; its timeout defers.
    func testSingleWriteRelayNeedsItsOwnAnswer() async throws {
        try entry("2026-11-20", "one relay")
        let silent = [FakeRelay("only", behavior: .silent)]
        let deferred = try await pass(silent, write: silent.map(\.url)).run()
        XCTAssertEqual(deferred?.deferred, 1)
        let only = relays("only")
        let s = try await pass(only, write: only.map(\.url), at: t0.addingTimeInterval(3600)).run()
        XCTAssertEqual(s?.synced, 1, "Option A: one write relay, one ack")
    }

    /// A2, A5: an unknown write set or an empty one publishes nothing.
    func testUnknownOrEmptyWriteSetPublishesNothing() async throws {
        try entry("2026-11-20", "nowhere")
        let w = relays("a", "b")
        let unknown = try await pass(w, write: nil).run()
        let empty = try await pass(w, write: []).run()
        XCTAssertNil(unknown)
        XCTAssertNil(empty)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty && $0.requests.isEmpty })
        XCTAssertTrue(try outbox().rows(dateString: "2026-11-20").isEmpty, "nothing is even signed")
    }

    // MARK: - Unbased versions (r2.1, D-rows)

    /// D2, first send: an *older* version this device never saw stops the
    /// send. The day is a conflict with both texts kept.
    func testUnseenOlderVersionStopsFirstSendAndKeepsBothTexts() async throws {
        try entry("2026-11-20", "from A")
        let fromB = try remote("2026-11-20", "from B", at: Int(t0.timeIntervalSince1970) - 300)
        let w = relays("a", events: [fromB]) + relays("b", "c")
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty }, "never sent")
        let r = try row("2026-11-20")
        XCTAssertEqual(r.syncState, .conflict)
        XCTAssertEqual(r.notesText, "from A", "local text kept")
        XCTAssertEqual(try earlier("2026-11-20").map(\.notesText), ["from B"], "remote text kept")
        XCTAssertTrue(try XCTUnwrap(outbox().rows(dateString: "2026-11-20").first).supersededByRemote)
    }

    /// D2 / D1, retry: A's queued edit failed; B's edit then reached relays.
    /// A's retry refetches, finds B's version and never sends.
    func testDelayedRetryDoesNotOverwriteEditFromB() async throws {
        let base = try remote("2026-11-20", "start", at: 100)
        try entry("2026-11-20", "start", base: base)
        try edit("2026-11-20", "A offline", at: t0)
        let first = relays("a", "b", "c", reply: .reject, events: [base])
        _ = try await pass(first, write: first.map(\.url)).run()
        let fromB = try remote("2026-11-20", "B later", at: Int(t0.timeIntervalSince1970) + 60)
        for r in first { r.okReply = .accept; r.events.append(fromB) }
        let s = try await pass(first, write: first.map(\.url), at: t0.addingTimeInterval(3600)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertTrue(first.allSatisfy { $0.publishedFrames.count == 1 }, "the retry never went out")
        XCTAssertEqual(try row("2026-11-20").notesText, "A offline")
        XCTAssertEqual(try earlier("2026-11-20").map(\.notesText), ["B later"])
    }

    /// B3: a version on a read-only relay also stops the send.
    func testVersionOnReadOnlyRelayStopsTheSend() async throws {
        try entry("2026-11-20", "mine")
        let readOnly = FakeRelay("readonly", events: [try remote("2026-11-20", "web", at: 50)])
        let w = relays("a", "b")
        let s = try await pass(w, read: [readOnly], write: w.map(\.url)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// §0.1 item 3, D3: a write relay that didn't answer before the send is
    /// asked again; an unmerged version found there (even an older one) is
    /// a conflict, never ignored.
    func testSilentRelayRecheckedLaterAndUnmergedVersionBecomesConflict() async throws {
        try entry("2026-11-20", "A text")
        let w = relays("a", "b") + [FakeRelay("c", behavior: .silent)]
        _ = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
        let olderFromB = try remote("2026-11-20", "B text", at: Int(t0.timeIntervalSince1970) - 600)
        let c = FakeRelay("c", events: [olderFromB])
        let later = relays("a", "b") + [c]
        let s = try await pass(later, write: later.map(\.url), at: t0.addingTimeInterval(60)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try earlier("2026-11-20").map(\.notesText), ["B text"])
        XCTAssertTrue(c.publishedFrames.isEmpty, "nothing republished over it")
    }

    /// Once the silent relay answers with nothing unbased, it's crossed off.
    func testRecheckClearsWhenRelayAnswersClean() async throws {
        try entry("2026-11-20", "A text")
        let w = relays("a", "b") + [FakeRelay("c", behavior: .silent)]
        _ = try await pass(w, write: w.map(\.url)).run()
        let later = relays("a", "b", "c")
        _ = try await pass(later, write: later.map(\.url), at: t0.addingTimeInterval(60)).run()
        XCTAssertEqual(try outbox().liveRow(dateString: "2026-11-20")?.recheckRelays, [])
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }

    /// D5: a newer local edit supersedes the queued one, which is never resent.
    func testNewerEditSupersedesQueuedEventInThePass() async throws {
        try entry("2026-11-20", "v1")
        let w = relays("a", "b", "c", reply: .reject)
        _ = try await pass(w, write: w.map(\.url)).run()
        let firstId = try XCTUnwrap(sent(w[0]).first?.id)
        try edit("2026-11-20", "v2", at: t0.addingTimeInterval(10))
        for r in w { r.okReply = .accept }
        _ = try await pass(w, write: w.map(\.url), at: t0.addingTimeInterval(3600)).run()
        let ids = sent(w[0]).map(\.id)
        XCTAssertEqual(ids.filter { $0 == firstId }.count, 1, "v1 never resent")
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(try row("2026-11-20").remoteEventID, ids.last)
    }

    // MARK: - Tombstones (I4, G15)

    /// A local delete of a synced day sends a kind 5 covering that version.
    func testDeleteSendsKind5CoveringTheSyncedVersion() async throws {
        let base = try remote("2026-11-20", "gone soon", at: 100)
        try entry("2026-11-20", "gone soon", base: base)
        try delete("2026-11-20", at: t0)
        let w = relays("a", "b", events: [base])
        _ = try await pass(w, write: w.map(\.url)).run()
        let k5 = try XCTUnwrap(sent(w[0]).first)
        XCTAssertEqual(k5.kind, 5)
        XCTAssertTrue(k5.tags.contains(["a", EntryDeletion.address(pubkey: owner, dateString: "2026-11-20")]))
        XCTAssertTrue(k5.tags.contains(["e", base.id]))
        XCTAssertGreaterThanOrEqual(k5.createdAt, base.createdAt)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }

    /// A delete of a day that never reached a relay sends nothing.
    func testDeleteOfNeverPublishedDaySendsNothing() async throws {
        try entry("2026-11-20", "local")
        try delete("2026-11-20", at: t0)
        let w = relays("a", "b")
        _ = try await pass(w, write: w.map(\.url)).run()
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// I4 / G15: writing on a deleted day waits until its kind 5 is
    /// delivered; the revived entry is signed strictly after the deletion.
    func testRevivedDaySendsDeletionFirst() async throws {
        let base = try remote("2026-11-20", "old", at: 100)
        try entry("2026-11-20", "old", base: base)
        try delete("2026-11-20", at: t0)
        let w = relays("a", "b", reply: .reject, events: [base])
        _ = try await pass(w, write: w.map(\.url)).run()
        try edit("2026-11-20", "new", at: t0.addingTimeInterval(5))
        // The kind 5 still isn't acknowledged: the 36669 waits.
        let waiting = try await pass(w, write: w.map(\.url), at: t0.addingTimeInterval(3600)).run()
        XCTAssertEqual(waiting?.waitingOnDeletion, 1)
        XCTAssertTrue(sent(w[0]).allSatisfy { $0.kind == 5 })
        for r in w { r.okReply = .accept }
        _ = try await pass(w, write: w.map(\.url), at: t0.addingTimeInterval(7200)).run()
        let kinds = sent(w[0]).map(\.kind)
        XCTAssertEqual(kinds.last, DailyEntry.kind)
        XCTAssertEqual(kinds.dropLast().allSatisfy { $0 == 5 }, true, "the deletion went out first")
        let k5 = try XCTUnwrap(sent(w[0]).first)
        let revived = try XCTUnwrap(sent(w[0]).last)
        XCTAssertGreaterThan(revived.createdAt, k5.createdAt)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
        XCTAssertEqual(try row("2026-11-20").remoteEventID, revived.id)
    }

    // MARK: - Isolation and safety

    /// E5: A's queued rows never send after B connects.
    func testSignOutAThenConnectBPublishesNothingFromA() async throws {
        try entry("2026-11-20", "A only")
        let w = relays("a", "b", reply: .reject)
        _ = try await pass(w, write: w.map(\.url)).run()
        let aIds = Set(try outbox().rows(dateString: "2026-11-20").map(\.eventId))
        for r in w { r.okReply = .accept }
        _ = try await pass(w, write: w.map(\.url), key: otherSecret, at: t0.addingTimeInterval(3600)).run()
        let after = w.flatMap { sent($0) }.filter { aIds.contains($0.id) }
        XCTAssertEqual(after.count, w.count, "only A's first attempt, nothing under B")
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly, "A's row untouched")
    }

    /// Audit M3: if the account or store changes mid-pass, nothing is sent.
    func testPassStopsWhenAccountIsNoLongerCurrent() async throws {
        try entry("2026-11-20", "stale")
        let w = relays("a", "b")
        _ = try await pass(w, write: w.map(\.url), isCurrent: { false }).run()
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// Conflict and blocked days are never signed or sent; guest rows wait
    /// for the first-connect sort.
    func testConflictBlockedAndGuestDaysAreNeverPublished() async throws {
        try entry("2026-11-18", "conflict").syncStateRaw = SyncState.conflict.rawValue
        try entry("2026-11-19", "").syncStateRaw = SyncState.blocked.rawValue
        let d = day("2026-11-20")
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: "guest", now: t0, ownerPubkey: nil))
        try context.save()
        let w = relays("a", "b")
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.signed, 0)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// A queued row whose day the read pass then found in conflict is never
    /// sent, even when no relay shows the other version right now.
    func testQueuedRowOfConflictDayIsNeverSent() async throws {
        try entry("2026-11-20", "queued")
        let w = relays("a", "b", reply: .reject)
        _ = try await pass(w, write: w.map(\.url)).run()
        try row("2026-11-20").syncStateRaw = SyncState.conflict.rawValue
        try context.save()
        for r in w { r.okReply = .accept }
        _ = try await pass(w, write: w.map(\.url), at: t0.addingTimeInterval(3600)).run()
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.count == 1 }, "only the first attempt")
    }

    /// Interop §1.8: the event's date tags are the row's stored identity,
    /// never recomputed from a time zone.
    func testEventTagsComeFromStoredDayIdentity() async throws {
        let row = JournalEntry(dateString: "2026-11-20", dayOfYear: 324, publishedAt: 1_795_590_000,
                               timeZoneID: "Pacific/Kiritimati", notesText: "far east", now: t0, ownerPubkey: owner)
        context.insert(row)
        try context.save()
        let w = relays("a", "b")
        _ = try await pass(w, write: w.map(\.url)).run()
        let e = try XCTUnwrap(sent(w[0]).first)
        XCTAssertEqual(e.tagValue("d"), "2026-11-20")
        XCTAssertEqual(e.tagValue("day"), "324")
        XCTAssertEqual(e.tagValue("published_at"), "1795590000")
    }

    // MARK: - SyncService gates

    private func service(_ relays: [FakeRelay]) -> SyncService {
        let transport = FakeTransport(relays: Dictionary(uniqueKeysWithValues: relays.map { ($0.url, $0) }))
        var fetcher = RelayFetcher(transport: transport); fetcher.pageTimeout = .milliseconds(300)
        var publisher = RelayPublisher(transport: transport); publisher.timeout = .milliseconds(300)
        return SyncService(fetcher: fetcher, publisher: publisher)
    }

    /// Spec A: nothing is published before the disclosure is accepted.
    func testNothingPublishedBeforeDisclosure() async throws {
        try entry("2026-11-20", "private until told")
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.publishDeferral, .notAllowedYet)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// First connect on a new key (no relay list anywhere) while one
    /// bootstrap relay never finishes connecting: the pass still ends, at the
    /// disclosure, with nothing sent.
    func testFirstConnectReachesTheDisclosureDespiteARelayThatNeverConnects() async throws {
        // Audit #20 L1: with the fix reverted this hangs; fail it instead
        // (the scheme turns test time limits on; XCTest rounds up to 1 min).
        executionTimeAllowance = 60
        try entry("2026-11-20", "private until told")
        let relays = RelaySet.defaultRead.enumerated().map { FakeRelay($1.host!, behavior: $0 == 1 ? .neverConnects : .normal) }
        let sync = service(relays)
        let started = Date()
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "three page timeouts, not three of URLSession's")
        XCTAssertEqual(sync.publishDeferral, .notAllowedYet, "the state that brings up the sheet")
        XCTAssertFalse(sync.couldNotReach)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty }, "nothing before the disclosure")
    }

    /// Stuck on "Saving to your account" (iPhone, 2026-11-22): with the
    /// disclosure accepted and relay.nostr.band never connecting, a pass
    /// waited out that relay in each of its five reads before the first
    /// send (40 s at the real timeout) and was cancelled when the iPhone
    /// locked. The relay is now dialed once in the pass, and the day is saved
    /// to the two write relays that answered and acknowledged.
    func testPublishesDespiteADefaultRelayThatNeverConnects() async throws {
        // Audit #20 L1: with the fix reverted this hangs; fail it instead
        // (the scheme turns test time limits on; XCTest rounds up to 1 min).
        executionTimeAllowance = 60
        try entry("2026-11-20", "saved in one pass")
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        // The defaults as on the iPhone: nostr.band never connects, damus
        // refuses the connection (its 503).
        let relays = RelaySet.defaultRead.map { url -> FakeRelay in
            switch url.host! {
            case "relay.nostr.band": return FakeRelay(url.host!, behavior: .neverConnects)
            case "relay.damus.io": return FakeRelay(url.host!, behavior: .refuseConnect)
            default: return FakeRelay(url.host!)
            }
        }
        let byHost = Dictionary(uniqueKeysWithValues: relays.map { ($0.url.host!, $0) })
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        // Waited on once, not once for each of the pass's seven reads.
        // Counted, not timed: a wall-clock bound fails on a slow CI runner.
        XCTAssertEqual(byHost["relay.nostr.band"]!.connectCount, 1, "the relay that never connects is dialed once")
        XCTAssertEqual(sync.lastPublish?.sent, 1)
        XCTAssertEqual(sync.lastPublish?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
        XCTAssertEqual(byHost["nos.lol"]!.publishedFrames.count, 1)
        XCTAssertEqual(byHost["relay.primal.net"]!.publishedFrames.count, 1)
        // Only the approved write relays are ever sent to.
        XCTAssertTrue(byHost["nostr.wine"]!.publishedFrames.isEmpty, "a read relay")
        XCTAssertTrue(byHost["relay.nostr.band"]!.publishedFrames.isEmpty)
    }

    /// The skipped relay never counts as having answered: when it is one of
    /// only two write relays that can be reached, nothing is sent.
    func testRelayDialedOnceStillNeverCountsAsAnswered() async throws {
        // Audit #20 L1: with the fix reverted this hangs; fail it instead
        // (the scheme turns test time limits on; XCTest rounds up to 1 min).
        executionTimeAllowance = 60
        try entry("2026-11-20", "stays here")
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let list = try UnsignedEvent(kind: 10002, tags: [["r", "wss://nos.lol"], ["r", "wss://relay.nostr.band"]], content: "")
            .signed(privateKey: secret, createdAt: 1)
        let relays = RelaySet.defaultRead.map {
            FakeRelay($0.host!, events: [list], behavior: $0.host == "relay.nostr.band" ? .neverConnects : .normal)
        }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.relays?.write?.count, 2)
        XCTAssertEqual(sync.lastPublish?.sent, 0)
        XCTAssertEqual(sync.lastPublish?.deferred, 1, "one of two write relays answered: unknown, so not sent")
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly)
    }

    /// The same with too few answers to know whether the account has a relay
    /// list: the write set stays unknown (never the defaults), even with the
    /// disclosure accepted, and Account says it couldn't reach the journal.
    func testTooFewBootstrapAnswersNeverPublishToDefaults() async throws {
        // Audit #20 L1: with the fix reverted this hangs; fail it instead
        // (the scheme turns test time limits on; XCTest rounds up to 1 min).
        executionTimeAllowance = 60
        try entry("2026-11-20", "stays here")
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let relays = RelaySet.defaultRead.enumerated().map { FakeRelay($1.host!, behavior: $0 == 0 ? .normal : .neverConnects) }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.publishDeferral, .relayListUnknown)
        XCTAssertNil(sync.relays?.write, "unknown, not the defaults")
        XCTAssertTrue(sync.couldNotReach)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// The app resets the service when an account connects and starts a pass
    /// straight away. That start must not be swallowed by the pass it just
    /// cancelled: it runs once the old one has closed its sockets.
    func testStartRightAfterResetRunsANewPass() async throws {
        // Audit #20 L1: with the fix reverted this hangs; fail it instead
        // (the scheme turns test time limits on; XCTest rounds up to 1 min).
        executionTimeAllowance = 60
        try entry("2026-11-20", "private until told")
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(relays)
        sync.start(owner: owner, secret: secret, context: context) { true }
        sync.reset()
        sync.start(owner: owner, secret: secret, context: context) { true }
        let started = Date()
        while sync.publishDeferral == nil, Date().timeIntervalSince(started) < 5 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(sync.publishDeferral, .notAllowedYet)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// Spec A, once per account on this iPhone: another account's
    /// acceptance (or the old account-less flag) never allows publishing.
    func testDisclosureIsPerAccount() async throws {
        try entry("2026-11-20", "mine")
        let repo = JournalRepository(context: context, activeOwner: owner)
        try repo.setFlag(JournalFlag.publishDisclosureAccepted)
        try repo.setFlag(PublishDisclosure.flagName(owner: KeyVault.pubkeyHex(for: otherSecret)!))
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.publishDeferral, .notAllowedYet)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
        let disclosure = PublishDisclosure(context: context, owner: owner)
        XCTAssertFalse(try disclosure.isAccepted())
        try disclosure.accept()
        XCTAssertTrue(try disclosure.isAccepted())
    }

    /// Spec B: a day written before connecting is published after the
    /// disclosure, sorted first (it was never sent as a guest row).
    func testGuestDayIsPublishedAfterDisclosure() async throws {
        let d = day("2026-11-20")
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: "before connecting", now: t0, ownerPubkey: nil))
        try context.save()
        XCTAssertEqual(try PublishDisclosure(context: context, owner: owner).pendingCount(), 1)
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty }, "nothing before the disclosure")
        try PublishDisclosure(context: context, owner: owner).accept()
        await sync.run(owner: owner, secret: secret, context: context)
        let sentDays = relays.flatMap(sent).filter { $0.kind == DailyEntry.kind }.compactMap { $0.tagValue("d") }
        XCTAssertTrue(sentDays.contains("2026-11-20"))
        XCTAssertEqual(try row("2026-11-20").ownerPubkey, owner)
    }

    /// The sheet's count line counts this account's unsaved reflections only.
    func testDisclosureCountsUnsavedReflectionsOfThisAccount() throws {
        try entry("2026-11-18", "one")
        try entry("2026-11-19", "two")
        try entry("2026-11-20", "saved", base: try remote("2026-11-20", "saved", at: 100))
        try entry("2026-11-21", "")
        try entry("2026-11-22", "other's", owner: KeyVault.pubkeyHex(for: otherSecret)!)
        XCTAssertEqual(try PublishDisclosure(context: context, owner: owner).pendingCount(), 2)
        XCTAssertEqual(DisclosureCopy.countLine(2), "2 reflections will be backed up to your account.")
        XCTAssertEqual(DisclosureCopy.countLine(1), "1 reflection will be backed up to your account.")
    }

    /// After the disclosure, a resolved "no list" publishes to the default
    /// write relays only, never to the read-only defaults.
    func testPublishesToDefaultWriteRelaysOnlyAfterDisclosure() async throws {
        try entry("2026-11-20", "told")
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!) }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertNil(sync.publishDeferral)
        XCTAssertEqual(sync.lastPublish?.synced, 1)
        for r in relays {
            XCTAssertEqual(!r.publishedFrames.isEmpty, RelaySet.defaultWrite.contains(r.url), r.url.absoluteString)
        }
    }

    /// A2: the relay-list lookup didn't resolve: defer, never the defaults.
    func testUnresolvedRelayListDefersPublishing() async throws {
        try entry("2026-11-20", "unknown list")
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let relays = RelaySet.defaultRead.enumerated().map { i, url in
            FakeRelay(url.host!, behavior: i == 0 ? .normal : .silent)
        }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.publishDeferral, .relayListUnknown)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
    }

    /// A5 / Seth 3f1c5fd4: a list with no write relay publishes nowhere and
    /// records why (Prep's copy explains it in slice 4).
    func testZeroWriteRelaysNeverPublishesAndExplains() async throws {
        try entry("2026-11-20", "read only list")
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let list = try UnsignedEvent(kind: 10002, tags: [["r", "wss://relay.damus.io", "read"]], content: "")
            .signed(privateKey: secret, createdAt: 1)
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!, events: [list]) }
        let sync = service(relays)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.publishDeferral, .noWriteRelays)
        XCTAssertTrue(relays.allSatisfy { $0.publishedFrames.isEmpty })
    }

    // MARK: - Audit FAIL at 4d58d90 (Chief P30)

    /// Real relays keep only the newest 36669 per address.
    private func keepNewest(_ r: FakeRelay) {
        let newest = Dictionary(grouping: r.events.filter { $0.kind == DailyEntry.kind }, by: { $0.tagValue("d") ?? "" })
            .mapValues { $0.max { $0.createdAt < $1.createdAt }!.id }
        r.events = r.events.filter { $0.kind != DailyEntry.kind || newest[$0.tagValue("d") ?? ""] == $0.id }
    }

    private func kind5(_ date: String, target: String, at: Int) throws -> NostrEvent {
        try EntryDeletion.template(pubkey: owner, dateString: date, eventId: target).signed(privateKey: secret, createdAt: at)
    }

    /// H1 (Audit probe): web wrote V0 to every default relay; iOS imported it
    /// and edits twice. V0, still on a read-only relay, is older than the
    /// base and is not a conflict.
    func testOlderAncestorOnReadOnlyRelayIsNotAConflict() async throws {
        let v0 = try remote("2026-11-20", "from web", at: 100)
        try entry("2026-11-20", "from web", base: v0)
        let w = relays("a", "b", events: [v0])
        let readOnly = FakeRelay("readonly", events: [v0])
        try edit("2026-11-20", "ios edit 1", at: t0)
        let s1 = try await pass(w, read: [readOnly], write: w.map(\.url)).run()
        w.forEach(keepNewest)
        XCTAssertEqual(s1?.synced, 1)
        try edit("2026-11-20", "ios edit 2", at: t0.addingTimeInterval(60))
        let s2 = try await pass(w, read: [readOnly], write: w.map(\.url), at: t0.addingTimeInterval(120)).run()
        XCTAssertEqual(s2?.conflicts, 0, "V0 is an ancestor of the base, not an unseen edit")
        XCTAssertEqual(s2?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
    }

    /// H1: a 3rd write relay that rejected V1 still holds V0; the next edit
    /// isn't stopped by it.
    func testWriteRelayThatMissedV1DoesNotStopNextEdit() async throws {
        let v0 = try remote("2026-11-20", "from web", at: 100)
        try entry("2026-11-20", "from web", base: v0)
        let w = relays("a", "b", events: [v0]) + relays("c", reply: .reject, events: [v0])
        try edit("2026-11-20", "v1", at: t0)
        _ = try await pass(w, write: w.map(\.url)).run()
        w.forEach(keepNewest)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
        XCTAssertTrue(w[2].events.contains { $0.id == v0.id }, "c still has V0")
        try edit("2026-11-20", "v2", at: t0.addingTimeInterval(60))
        let s = try await pass(w, write: w.map(\.url), at: t0.addingTimeInterval(120)).run()
        XCTAssertEqual(s?.conflicts, 0)
        XCTAssertEqual(s?.synced, 1)
    }

    /// H1 keeps r2.1: an unseen edit newer than the base, even if older than
    /// this row, still stops the send.
    func testUnseenEditNewerThanBaseStillConflicts() async throws {
        let base = try remote("2026-11-20", "start", at: 100)
        try entry("2026-11-20", "start", base: base)
        try edit("2026-11-20", "A later", at: t0)
        let fromB = try remote("2026-11-20", "B in between", at: 200)
        let w = relays("a", "b", events: [base, fromB])
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try earlier("2026-11-20").map(\.notesText), ["B in between"])
    }

    /// M1 (Audit probe): delete a synced day, the kind 5 is delivered, then
    /// revive it. The real order, import then publish, sends the revival.
    func testReviveAfterDeliveredDeletionThroughImporter() async throws {
        let base = try remote("2026-11-20", "old", at: 100)
        try entry("2026-11-20", "old", base: base)
        try delete("2026-11-20", at: t0)
        let w = relays("a", "b", events: [base])
        _ = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
        try edit("2026-11-20", "new", at: t0.addingTimeInterval(5))
        let days = RemoteJournal.days(from: w[0].events, owner: owner, privateKey: secret)
        try RemoteImporter(context: context, owner: owner).apply(days, zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .localOnly, "own kind 5 isn't a remote delete")
        let s = try await pass(w, write: w.map(\.url), at: t0.addingTimeInterval(3600)).run()
        XCTAssertEqual(s?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").notesText, "new")
    }

    /// M1: a kind 5 from another device, signed with the same key, still
    /// applies, even when this device has its own kind 5 rows for the day.
    func testKind5FromAnotherDeviceWithSameKeyStillApplies() async throws {
        let base = try remote("2026-11-20", "old", at: 100)
        try entry("2026-11-20", "old", base: base)
        try delete("2026-11-20", at: t0)
        let w = relays("a", "b", reply: .reject, events: [base])
        _ = try await pass(w, write: w.map(\.url)).run()
        XCTAssertFalse(try outbox().rows(dateString: "2026-11-20").filter { $0.kind == 5 }.isEmpty)
        // Revived here; another device deleted later.
        try edit("2026-11-20", "revived here", at: t0.addingTimeInterval(5))
        let theirs = try kind5("2026-11-20", target: base.id, at: Int(t0.timeIntervalSince1970) + 600)
        let days = RemoteJournal.days(from: [base, theirs], owner: owner, privateKey: secret)
        try RemoteImporter(context: context, owner: owner).apply(days, zone: zone)
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict, "their delete meets a pending edit")
        XCTAssertEqual(try row("2026-11-20").notesText, "revived here")

        // Without pending edits it tombstones the day.
        let other = try remote("2026-11-21", "kept", at: 100)
        try entry("2026-11-21", "kept", base: other)
        let theirs2 = try kind5("2026-11-21", target: other.id, at: 200)
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: [other, theirs2], owner: owner, privateKey: secret), zone: zone)
        XCTAssertNotNil(try row("2026-11-21").deletedAt)
    }

    /// L1: a kind 5 the read pass didn't see, newer than the base, found by
    /// the pre-send refetch: conflict, nothing sent.
    func testUnseenKind5InPreSendRefetchIsConflict() async throws {
        let base = try remote("2026-11-20", "start", at: 100)
        try entry("2026-11-20", "start", base: base)
        try edit("2026-11-20", "pending", at: t0)
        let theirs = try kind5("2026-11-20", target: base.id, at: Int(t0.timeIntervalSince1970) + 600)
        let w = relays("a", "b", events: [base, theirs])
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-20").notesText, "pending")
    }

    /// L1: a kind 5 that only covers the base or older isn't a conflict.
    func testOldKind5AtOrBeforeBaseDoesNotStopSend() async throws {
        let base = try remote("2026-11-20", "start", at: 100)
        try entry("2026-11-20", "start", base: base)
        try edit("2026-11-20", "pending", at: t0)
        let old = try kind5("2026-11-20", target: "00", at: 50)
        let w = relays("a", "b", events: [base, old])
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.synced, 1)
    }

    /// L1: reviving a day another device deleted signs strictly after that
    /// deletion, even with a clock behind it, and isn't stopped by it.
    func testReviveOfRemotelyDeletedDaySignsAfterTheDeletion() async throws {
        let base = try remote("2026-11-20", "old", at: 100)
        try entry("2026-11-20", "old", base: base)
        let future = Int(t0.timeIntervalSince1970) + 86_400
        let theirs = try kind5("2026-11-20", target: base.id, at: future)
        let w = relays("a", "b", events: [base, theirs])
        try RemoteImporter(context: context, owner: owner)
            .apply(RemoteJournal.days(from: w[0].events, owner: owner, privateKey: secret), zone: zone)
        XCTAssertNotNil(try row("2026-11-20").deletedAt)
        try edit("2026-11-20", "back again", at: t0)
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.conflicts, 0)
        XCTAssertEqual(s?.synced, 1)
        let revived = try XCTUnwrap(sent(w[0]).last)
        XCTAssertGreaterThan(revived.createdAt, future, "not hidden by the deletion")
    }

    /// End to end through SyncService (read, import, publish): delete,
    /// sync, revive, sync. The revival reaches relays and stays synced.
    func testSyncServiceDeleteThenReviveEndToEnd() async throws {
        let base = try remote("2026-11-20", "old", at: 100)
        try entry("2026-11-20", "old", base: base)
        try JournalRepository(context: context, activeOwner: owner).setFlag(PublishDisclosure.flagName(owner: owner))
        let relays = RelaySet.defaultRead.map { FakeRelay($0.host!, events: [base]) }
        let sync = service(relays)
        try delete("2026-11-20", at: Date.now)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.lastPublish?.synced, 1)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced)
        relays.forEach(keepNewest)
        try edit("2026-11-20", "new", at: Date.now.addingTimeInterval(1))
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(sync.lastPublish?.conflicts, 0)
        XCTAssertEqual(sync.lastPublish?.synced, 1)
        let r = try row("2026-11-20")
        XCTAssertEqual(r.syncState, .synced)
        XCTAssertEqual(r.notesText, "new")
        relays.forEach(keepNewest)
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertEqual(try row("2026-11-20").syncState, .synced, "a later read leaves it alone")
        XCTAssertEqual(try row("2026-11-20").notesText, "new")
    }

    // MARK: - Audit #16 L1

    /// L1: the pre-send refetch finds another device's kind 5 on its own
    /// (no 36669 beside it). The importer is told the account deleted the
    /// day, so an open copy of the account's earlier text is retired and
    /// never offered as "Your account" (Prep §10).
    func testPreSendLoneKind5IsADeletionNotNothing() async throws {
        let base = try remote("2026-11-20", "start", at: 100)
        try entry("2026-11-20", "start", base: base)
        try edit("2026-11-20", "mine", at: t0)
        context.insert(EarlierVersion(ownerPubkey: owner, dateString: "2026-11-20", notesText: "account text",
                                      reason: .remoteInConflict, eventId: String(repeating: "e", count: 64),
                                      surfaced: true, eventCreatedAt: 300, now: t0))
        try context.save()
        let k5 = try kind5("2026-11-20", target: base.id, at: 900)
        let w = relays("a", "b", events: [k5])
        let s = try await pass(w, write: w.map(\.url)).run()
        XCTAssertEqual(s?.conflicts, 1)
        XCTAssertTrue(w.allSatisfy { $0.publishedFrames.isEmpty })
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict)
        XCTAssertEqual(try row("2026-11-20").notesText, "mine")
        let review = ConflictReview(context: context, owner: owner)
        XCTAssertEqual(try review.load().items.map(\.kind), [.deletedFromAccount], "§10: a §7 row")
        XCTAssertEqual(try review.load().items.map(\.accountText), [""], "the deleted account text is never offered")
        try review.apply(["2026-11-20": .keepAccount])
        XCTAssertEqual(try row("2026-11-20").syncState, .conflict, "never marked saved with deleted text")
    }
}
