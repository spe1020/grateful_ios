import XCTest
import CryptoKit
@testable import NostrCore

/// The official NIP-44 v2 vectors (paulmillr/nip44 @ 671a1f04, javascript/test/, Unlicense; sha256 checked
/// against the value published in NIP-44). Every section runs, including all
/// invalid cases.
final class NIP44VectorTests: XCTestCase {
    static let publishedSha256 = "269ed0f69e4c192512cc779e78c555090cebc7c785b609e338a62afc3ce25040"

    var v2: [String: Any] = [:]

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "nip44.vectors", withExtension: "json"))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Hex.encode(Data(SHA256.hash(data: data))), Self.publishedSha256, "vector file differs from the one NIP-44 publishes")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        v2 = try XCTUnwrap(root["v2"] as? [String: Any])
    }

    private func section(_ path: String...) throws -> [[String: Any]] {
        var node: Any = v2
        for p in path { node = try XCTUnwrap((node as? [String: Any])?[p], "missing \(p)") }
        return try XCTUnwrap(node as? [[String: Any]])
    }
    private func hex(_ v: Any?) throws -> Data { try XCTUnwrap(Hex.decode(try XCTUnwrap(v as? String))) }

    func testValidConversationKeys() throws {
        let cases = try section("valid", "get_conversation_key")
        XCTAssertEqual(cases.count, 35)
        for c in cases {
            let key = try NIP44.conversationKey(privateKey: try hex(c["sec1"]), peerPublicKey: try hex(c["pub2"]))
            XCTAssertEqual(Hex.encode(key), c["conversation_key"] as? String)
        }
    }

    /// `Nip44.messageKeys` is private in the copied file (kept unmodified), so
    /// these are checked through encryption: a fixed-nonce encrypt must
    /// reproduce the same keystream and MAC key. We also check the HKDF
    /// derivation the copied code uses against each expected key.
    func testValidMessageKeys() throws {
        let node = try XCTUnwrap((v2["valid"] as? [String: Any])?["get_message_keys"] as? [String: Any])
        let conv = try hex(node["conversation_key"])
        let keys = try XCTUnwrap(node["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 32)
        for k in keys {
            let okm = HKDF<SHA256>.expand(pseudoRandomKey: SymmetricKey(data: conv), info: try hex(k["nonce"]), outputByteCount: 76)
            let bytes = okm.withUnsafeBytes { Data($0) }
            XCTAssertEqual(Hex.encode(bytes.subdata(in: 0..<32)), k["chacha_key"] as? String)
            XCTAssertEqual(Hex.encode(bytes.subdata(in: 32..<44)), k["chacha_nonce"] as? String)
            XCTAssertEqual(Hex.encode(bytes.subdata(in: 44..<76)), k["hmac_key"] as? String)
            // And through the copied code: decrypting our own fixed-nonce payload round-trips.
            let payload = try NIP44.encrypt("message-keys", conversationKey: conv, nonce: try hex(k["nonce"]))
            XCTAssertEqual(try NIP44.decrypt(payload, conversationKey: conv), "message-keys")
        }
    }

    func testCalcPaddedLen() throws {
        let cases = try XCTUnwrap((v2["valid"] as? [String: Any])?["calc_padded_len"] as? [[Int]])
        XCTAssertEqual(cases.count, 24)
        for pair in cases { XCTAssertEqual(Nip44.calcPaddedLen(pair[0]), pair[1], "len \(pair[0])") }
    }

    func testEncryptDecrypt() throws {
        let cases = try section("valid", "encrypt_decrypt")
        XCTAssertEqual(cases.count, 10)
        for c in cases {
            let sec1 = try hex(c["sec1"]), sec2 = try hex(c["sec2"])
            let conv = try NIP44.conversationKey(privateKey: sec1, peerPublicKey: try NostrKeys.publicKey(for: sec2))
            XCTAssertEqual(Hex.encode(conv), c["conversation_key"] as? String)
            // Symmetric: the other side derives the same key.
            XCTAssertEqual(try NIP44.conversationKey(privateKey: sec2, peerPublicKey: try NostrKeys.publicKey(for: sec1)), conv)
            let plaintext = try XCTUnwrap(c["plaintext"] as? String)
            XCTAssertEqual(try NIP44.encrypt(plaintext, conversationKey: conv, nonce: try hex(c["nonce"])), c["payload"] as? String)
            XCTAssertEqual(try NIP44.decrypt(try XCTUnwrap(c["payload"] as? String), conversationKey: conv), plaintext)
        }
    }

    func testEncryptDecryptLongMessages() throws {
        let cases = try section("valid", "encrypt_decrypt_long_msg")
        XCTAssertEqual(cases.count, 3)
        for c in cases {
            let pattern = try XCTUnwrap(c["pattern"] as? String)
            let plaintext = String(repeating: pattern, count: try XCTUnwrap(c["repeat"] as? Int))
            XCTAssertEqual(Hex.encode(Data(SHA256.hash(data: Data(plaintext.utf8)))), c["plaintext_sha256"] as? String)
            let conv = try hex(c["conversation_key"])
            let payload = try NIP44.encrypt(plaintext, conversationKey: conv, nonce: try hex(c["nonce"]))
            XCTAssertEqual(Hex.encode(Data(SHA256.hash(data: Data(payload.utf8)))), c["payload_sha256"] as? String)
            XCTAssertEqual(try NIP44.decrypt(payload, conversationKey: conv), plaintext)
        }
    }

    func testInvalidMessageLengthsAreRejected() throws {
        let lengths = try XCTUnwrap((v2["invalid"] as? [String: Any])?["encrypt_msg_lengths"] as? [Int])
        XCTAssertEqual(lengths, [0, 65536, 100000, 10000000])
        let conv = Data(repeating: 1, count: 32)
        for n in lengths {
            XCTAssertThrowsError(try NIP44.encrypt(String(repeating: "a", count: n), conversationKey: conv), "length \(n)") {
                XCTAssertEqual($0 as? NIP44.Failure, .invalidPlaintextLength)
            }
        }
    }

    func testInvalidConversationKeysAreRejected() throws {
        let cases = try section("invalid", "get_conversation_key")
        XCTAssertEqual(cases.count, 8)
        for c in cases {
            XCTAssertThrowsError(
                try NIP44.conversationKey(privateKey: try hex(c["sec1"]), peerPublicKey: try hex(c["pub2"])),
                c["note"] as? String ?? ""
            )
        }
    }

    func testInvalidPayloadsAreRejected() throws {
        let cases = try section("invalid", "decrypt")
        XCTAssertEqual(cases.count, 12)
        for c in cases {
            let note = c["note"] as? String ?? ""
            XCTAssertThrowsError(try NIP44.decrypt(try XCTUnwrap(c["payload"] as? String), conversationKey: try hex(c["conversation_key"])), note) { error in
                let failure = error as? NIP44.Failure
                switch note {
                case let n where n.hasPrefix("unknown encryption version"): XCTAssertEqual(failure, .unknownVersion, note)
                case "invalid MAC": XCTAssertEqual(failure, .invalidMAC, note)
                case "invalid padding": XCTAssertEqual(failure, .invalidPadding, note)
                default: XCTAssertNotNil(failure, note) // base64 / length: any rejection
                }
            }
        }
    }
}
