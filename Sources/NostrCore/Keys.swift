import Foundation
import Security
import P256K

/// Errors from key handling.
public enum NostrKeyError: Error, Equatable {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidBech32
    case randomGenerationFailed
}

/// Key helpers. Private keys are 32 raw bytes; public keys are 32-byte x-only (BIP-340).
/// Key *storage* is deliberately not here (see the storage recommendation; Phase 2).
public enum NostrKeys {
    /// A new random private key: 32 bytes from `SecRandomCopyBytes` (the status
    /// is checked), accepted only if swift-secp256k1 confirms it is a valid
    /// secp256k1 scalar (non-zero, below the curve order). Out-of-range draws
    /// are retried. Not used for production keys yet: key creation and storage
    /// are Phase 2 work and need their own review.
    public static func generatePrivateKey() throws -> Data {
        for _ in 0..<8 {
            var bytes = [UInt8](repeating: 0, count: 32)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else { throw NostrKeyError.randomGenerationFailed }
            let key = Data(bytes)
            if isValidPrivateKey(key) { return key }
        }
        throw NostrKeyError.randomGenerationFailed
    }

    /// True when `key` is 32 bytes and a valid secp256k1 private key.
    public static func isValidPrivateKey(_ key: Data) -> Bool {
        key.count == 32 && (try? P256K.Schnorr.PrivateKey(dataRepresentation: key)) != nil
    }

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
        // BIP-173: a string may be all lowercase or all uppercase, never mixed.
        guard value == value.lowercased() || value == value.uppercased() else { throw NostrKeyError.invalidBech32 }
        guard let (got, data) = Bech32.decode(value.lowercased()), got == hrp, data.count == 32 else {
            throw NostrKeyError.invalidBech32
        }
        return data
    }

    public static func hex(_ data: Data) -> String { Hex.encode(data) }
    public static func data(hex: String) -> Data? { Hex.decode(hex) }
}
