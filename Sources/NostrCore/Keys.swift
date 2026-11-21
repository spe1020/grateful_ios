import Foundation

/// Errors from key handling.
public enum NostrKeyError: Error, Equatable {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidBech32
}

/// Key helpers. Private keys are 32 raw bytes; public keys are 32-byte x-only (BIP-340).
/// Key *storage* is deliberately not here (see the storage recommendation; Phase 2).
public enum NostrKeys {
    /// A new random private key (uses swift-secp256k1's validated key generation).
    public static func generatePrivateKey() -> Data { Schnorr.randomPrivkey() }

    /// The x-only public key for a private key.
    public static func publicKey(for privateKey: Data) throws -> Data {
        guard privateKey.count == 32 else { throw NostrKeyError.invalidPrivateKey }
        do { return try Schnorr.xonlyPubkey(privkey32: privateKey) }
        catch { throw NostrKeyError.invalidPrivateKey }
    }

    // MARK: NIP-19 (npub / nsec only — the rest of NIP-19 isn't needed yet)

    public static func npub(_ publicKey: Data) throws -> String {
        guard publicKey.count == 32 else { throw NostrKeyError.invalidPublicKey }
        return Bech32.encode(hrp: "npub", data: publicKey)
    }

    public static func nsec(_ privateKey: Data) throws -> String {
        guard privateKey.count == 32 else { throw NostrKeyError.invalidPrivateKey }
        return Bech32.encode(hrp: "nsec", data: privateKey)
    }

    public static func decodeNpub(_ value: String) throws -> Data {
        try decode(value, hrp: "npub")
    }

    public static func decodeNsec(_ value: String) throws -> Data {
        try decode(value, hrp: "nsec")
    }

    private static func decode(_ value: String, hrp: String) throws -> Data {
        guard let (got, data) = Bech32.decode(value.lowercased()), got == hrp, data.count == 32 else {
            throw NostrKeyError.invalidBech32
        }
        return data
    }

    public static func hex(_ data: Data) -> String { Hex.encode(data) }
    public static func data(hex: String) -> Data? { Hex.decode(hex) }
}
