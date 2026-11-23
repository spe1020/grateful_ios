import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// Chief P48: the UI-test relays are chosen only by launch argument, only in
/// Debug builds, and never reach the network.
final class UITestRelaysTests: XCTestCase {
    func testNoArgumentMeansTheRealTransport() {
        XCTAssertTrue(UITestRelays.transport(arguments: []) is WebSocketTransport)
        XCTAssertTrue(UITestRelays.transport(arguments: ["-other", "uiTestNoRelays"]) is WebSocketTransport,
                      "only the exact launch argument")
    }

    /// Launch arguments of the form `-name value` also land in UserDefaults'
    /// argument domain; a stored default must never switch the transport.
    func testDefaultsNeverSwitchTheTransport() {
        let key = String(UITestRelays.noRelays.dropFirst())
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        XCTAssertTrue(UITestRelays.transport(arguments: []) is WebSocketTransport)
    }

    func testNoRelaysRefusesEveryConnection() async {
        let t = UITestRelays.transport(arguments: [UITestRelays.noRelays])
        do {
            _ = try await t.connect(URL(string: "wss://nos.lol")!)
            XCTFail("connected")
        } catch {}
    }

    /// Empty relays: REQ → EOSE, EVENT → OK false. Never an acknowledgement.
    func testEmptyRelaysAnswerNothingAndRejectEvents() async throws {
        let t = UITestRelays.transport(arguments: [UITestRelays.emptyRelays, UITestRelays.noRelays])
        let c = try await t.connect(URL(string: "wss://nos.lol")!)
        try await c.send(#"["REQ","s1",{"kinds":[1]}]"#)
        let eose = try await c.receive()
        XCTAssertEqual(RelayMessage.parse(eose), .eose(subscription: "s1"))
        try await c.send(#"["EVENT",{"id":"abc"}]"#)
        let ok = try await c.receive()
        guard case .ok(let id, let accepted, _)? = RelayMessage.parse(ok) else { return XCTFail(ok) }
        XCTAssertEqual(id, "abc")
        XCTAssertFalse(accepted)
        c.close()
        do { _ = try await c.receive(); XCTFail("closed") } catch {}
    }

    /// Chief's conditions for the empty relays (DEBUG only, one UI test): even
    /// with the disclosure accepted, a pass over them publishes into `OK false`
    /// everywhere, so nothing is ever acknowledged or synced.
    @MainActor
    func testEmptyRelaysNeverAcknowledgeOrSync() async throws {
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JournalStore.schema, configurations: config)
        let context = container.mainContext
        let secret = try NostrKeys.generatePrivateKey()
        let owner = KeyVault.pubkeyHex(for: secret)!
        let zone = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let d = DailyEntry.Day(containing: cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!, timeZone: zone)
        context.insert(JournalEntry(dateString: d.dateString, dayOfYear: d.dayOfYear, publishedAt: d.publishedAt,
                                    timeZoneID: zone.identifier, notesText: "never acknowledged", now: .now, ownerPubkey: owner))
        try context.save()
        try PublishDisclosure(context: context, owner: owner).accept()

        let sync = SyncService(transport: UITestRelays.transport(arguments: [UITestRelays.emptyRelays]))
        await sync.run(owner: owner, secret: secret, context: context)
        XCTAssertNotNil(sync.relays?.write, "two empty answers: no list, so the defaults")
        XCTAssertEqual(sync.lastPublish?.synced, 0)
        let rows = try context.fetch(FetchDescriptor<OutboxEvent>())
        XCTAssertFalse(rows.isEmpty, "a signed event was queued and offered")
        XCTAssertTrue(rows.allSatisfy { $0.ackedRelays.isEmpty }, "OK false is never an acknowledgement")
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<JournalEntry>()).first)
        XCTAssertNotEqual(entry.syncState, .synced)
        _ = container
    }
}
