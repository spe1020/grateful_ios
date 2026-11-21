import XCTest
@testable import NostrCore

final class NostrEventTests: XCTestCase {
    struct Cases: Decodable {
        struct IdCase: Decodable { let pubkey: String; let created_at: Int; let kind: Int; let tags: [[String]]; let content: String; let id: String }
        struct KeyCase: Decodable { let hex: String?; let npub: String?; let secretHex: String?; let nsec: String?; let pubkeyHex: String? }
        let eventIds: [IdCase]
        let nip19: [KeyCase]
    }

    func load() throws -> Cases {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "nostr_tools_cases", withExtension: "json"))
        return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }

    /// Ids must match nostr-tools byte for byte, including escapes for quotes,
    /// control characters, `/`, U+2028/2029 and NUL.
    func testEventIdsMatchNostrTools() throws {
        let cases = try load().eventIds
        XCTAssertEqual(cases.count, 8)
        for c in cases {
            XCTAssertEqual(NostrEvent.computeId(pubkey: c.pubkey, createdAt: c.created_at, kind: c.kind, tags: c.tags, content: c.content), c.id, c.content.debugDescription)
        }
    }

    func testNip19MatchesNostrTools() throws {
        for c in try load().nip19 {
            if let hex = c.hex, let npub = c.npub {
                XCTAssertEqual(try NostrKeys.npub(try XCTUnwrap(Hex.decode(hex))), npub)
                XCTAssertEqual(Hex.encode(try NostrKeys.decodeNpub(npub)), hex)
            }
            if let sk = c.secretHex, let nsec = c.nsec, let pk = c.pubkeyHex {
                let key = try XCTUnwrap(Hex.decode(sk))
                XCTAssertEqual(try NostrKeys.nsec(key), nsec)
                XCTAssertEqual(try NostrKeys.decodeNsec(nsec), key)
                XCTAssertEqual(Hex.encode(try NostrKeys.publicKey(for: key)), pk)
            }
        }
    }

    func testBech32RejectsWrongPrefixAndBadChecksum() throws {
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        XCTAssertThrowsError(try NostrKeys.decodeNsec(npub))
        XCTAssertThrowsError(try NostrKeys.decodeNpub(String(npub.dropLast()) + "h"))
    }

    /// L4: BIP-173 forbids mixed case; all-lowercase and all-uppercase are both valid.
    func testBech32RejectsMixedCaseButAcceptsSingleCase() throws {
        let npub = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"
        let expected = try NostrKeys.decodeNpub(npub)
        XCTAssertEqual(try NostrKeys.decodeNpub(npub.uppercased()), expected)
        XCTAssertThrowsError(try NostrKeys.decodeNpub("Npub" + npub.dropFirst(4))) { XCTAssertEqual($0 as? NostrKeyError, .invalidBech32) }
        XCTAssertThrowsError(try NostrKeys.decodeNpub(String(npub.dropLast()) + "G"))
        let nsec = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"
        XCTAssertNoThrow(try NostrKeys.decodeNsec(nsec.uppercased()))
        XCTAssertThrowsError(try NostrKeys.decodeNsec("nsec1VL029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"))
    }

    /// L3: generated keys are valid scalars; out-of-range scalars are rejected.
    func testGeneratedKeysAreValidAndInvalidScalarsAreRejected() throws {
        for _ in 0..<20 {
            let key = try NostrKeys.generatePrivateKey()
            XCTAssertEqual(key.count, 32)
            XCTAssertTrue(NostrKeys.isValidPrivateKey(key))
            XCTAssertNoThrow(try NostrKeys.publicKey(for: key))
        }
        let n = try XCTUnwrap(Hex.decode("fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"))
        XCTAssertFalse(NostrKeys.isValidPrivateKey(n))                     // == curve order
        XCTAssertFalse(NostrKeys.isValidPrivateKey(Data(repeating: 0xff, count: 32))) // > order
        XCTAssertFalse(NostrKeys.isValidPrivateKey(Data(repeating: 0, count: 32)))    // zero
        XCTAssertFalse(NostrKeys.isValidPrivateKey(Data(repeating: 1, count: 31)))    // wrong length
    }

    func testSignAndVerifyRoundTrip() throws {
        let sk = try NostrKeys.generatePrivateKey()
        let ev = try UnsignedEvent(kind: 1, tags: [["t", "x"]], content: "hi").signed(privateKey: sk, createdAt: 1_700_000_000)
        XCTAssertTrue(ev.isValid)
        var tampered = ev; tampered.content = "hj"
        XCTAssertFalse(tampered.isValid)
        var badSig = ev; badSig.sig = String(repeating: "0", count: 128)
        XCTAssertFalse(badSig.isValid)
    }

    func testRejectsInvalidPrivateKeys() {
        XCTAssertThrowsError(try NostrKeys.publicKey(for: Data(repeating: 0, count: 32)))
        XCTAssertThrowsError(try NostrKeys.publicKey(for: Data(repeating: 1, count: 31)))
    }
}
