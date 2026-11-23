import XCTest
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
}
