import Foundation
import CryptoKit

/// A signed Nostr event (NIP-01). Written fresh for Grateful Day.
public struct NostrEvent: Codable, Equatable, Sendable {
    public var id: String
    public var pubkey: String
    public var createdAt: Int
    public var kind: Int
    public var tags: [[String]]
    public var content: String
    public var sig: String

    enum CodingKeys: String, CodingKey {
        case id, pubkey, kind, tags, content, sig
        case createdAt = "created_at"
    }

    public init(id: String, pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String, sig: String) {
        self.id = id; self.pubkey = pubkey; self.createdAt = createdAt
        self.kind = kind; self.tags = tags; self.content = content; self.sig = sig
    }

    /// First value of the first tag with this name.
    public func tagValue(_ name: String) -> String? {
        tags.first { $0.first == name && $0.count > 1 }?[1]
    }

    /// True when `id` is the NIP-01 hash of the event and `sig` is a valid
    /// BIP-340 signature by `pubkey`. Never trust relays without this.
    public var isValid: Bool {
        guard let pk = Hex.decode(pubkey), pk.count == 32,
              let idBytes = Hex.decode(id), idBytes.count == 32,
              let sigBytes = Hex.decode(sig), sigBytes.count == 64,
              NostrEvent.computeId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content) == id
        else { return false }
        return Schnorr.verify(sig64: sigBytes, messageId32: idBytes, xonlyPubkey32: pk)
    }

    /// NIP-01 event id: sha256 of `[0,pubkey,created_at,kind,tags,content]`.
    public static func computeId(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
        let serialized = serialize(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        return Hex.encode(Data(SHA256.hash(data: Data(serialized.utf8))))
    }

    /// The exact NIP-01 serialization (no whitespace; only the escapes NIP-01 lists).
    static func serialize(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) -> String {
        let tagJson = tags.map { "[" + $0.map(escape).joined(separator: ",") + "]" }.joined(separator: ",")
        return "[0,\(escape(pubkey)),\(createdAt),\(kind),[\(tagJson)],\(escape(content))]"
    }

    static func escape(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

/// An unsigned event: what app code builds before signing.
public struct UnsignedEvent: Equatable, Sendable {
    public var kind: Int
    public var tags: [[String]]
    public var content: String

    public init(kind: Int, tags: [[String]], content: String) {
        self.kind = kind; self.tags = tags; self.content = content
    }

    /// Sign with a private key at `createdAt` (unix seconds).
    public func signed(privateKey: Data, createdAt: Int) throws -> NostrEvent {
        let pubkey = Hex.encode(try NostrKeys.publicKey(for: privateKey))
        let id = NostrEvent.computeId(pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content)
        guard let idBytes = Hex.decode(id) else { throw NostrKeyError.invalidPrivateKey }
        let sig = try Schnorr.sign(messageId32: idBytes, privkey32: privateKey)
        return NostrEvent(id: id, pubkey: pubkey, createdAt: createdAt, kind: kind, tags: tags, content: content, sig: Hex.encode(sig))
    }
}
