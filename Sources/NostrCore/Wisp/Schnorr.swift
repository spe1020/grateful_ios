// ---------------------------------------------------------------------------
// Third-party file. Copied verbatim from Wisp iOS; see THIRD_PARTY_NOTICES.md §1.
// Source: https://github.com/barrydeen/wisp-ios/blob/914febaf597fc044a680ead632931009b21d641a/Schnorr.swift
// Upstream commit: 914febaf597fc044a680ead632931009b21d641a
// Upstream blob: 7b3981e580ba63f17cb2490fbb6395834c4dd0b8
// Copyright (c) 2025 Barry Deen. Licensed under the MIT License.
// Everything below this header is unmodified. Changes, if ever needed, are
// marked "Modified for Grateful Day" with a date.
// ---------------------------------------------------------------------------
import Foundation
import P256K

nonisolated enum Schnorr {

    static func sign(messageId32: Data, privkey32: Data) throws -> Data {
        let priv = try P256K.Schnorr.PrivateKey(dataRepresentation: privkey32)
        var msg = [UInt8](messageId32)
        var aux = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &aux)
        let sig = try aux.withUnsafeMutableBytes { rawAux -> P256K.Schnorr.SchnorrSignature in
            try priv.signature(message: &msg, auxiliaryRand: rawAux.baseAddress)
        }
        return sig.dataRepresentation
    }

    static func verify(sig64: Data, messageId32: Data, xonlyPubkey32: Data) -> Bool {
        guard sig64.count == 64, messageId32.count == 32, xonlyPubkey32.count == 32 else { return false }
        let xonly = P256K.Schnorr.XonlyKey(dataRepresentation: xonlyPubkey32)
        guard let signature = try? P256K.Schnorr.SchnorrSignature(dataRepresentation: sig64) else { return false }
        var msg = [UInt8](messageId32)
        return xonly.isValid(signature, for: &msg)
    }

    /// NIP-44 ECDH: returns the raw 32-byte x-coordinate of `privkey × pubkey`,
    /// without the SHA-256 hashing that NIP-04 uses.
    static func ecdhRawX(privkey32: Data, xonlyPubkey32: Data) throws -> Data {
        let priv = try P256K.KeyAgreement.PrivateKey(dataRepresentation: privkey32)
        // Reconstruct a compressed pubkey by prefixing 0x02 (even Y, Schnorr/x-only convention).
        var compressed = Data([0x02])
        compressed.append(xonlyPubkey32)
        let pub = try P256K.KeyAgreement.PublicKey(dataRepresentation: compressed, format: .compressed)
        let shared = priv.sharedSecretFromKeyAgreement(with: pub, format: .compressed)
        // SharedSecret is 33 bytes in compressed form: [version_byte || x_coordinate(32)]
        return shared.withUnsafeBytes { raw -> Data in
            precondition(raw.count == 33)
            return Data(bytes: raw.baseAddress!.advanced(by: 1), count: 32)
        }
    }

    static func randomPrivkey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }

    /// Returns the 32-byte x-only pubkey for the given 32-byte private key.
    static func xonlyPubkey(privkey32: Data) throws -> Data {
        let priv = try P256K.Schnorr.PrivateKey(dataRepresentation: privkey32)
        return Data(priv.xonly.bytes)
    }
}
