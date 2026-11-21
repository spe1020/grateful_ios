import Foundation

/// Public NIP-44 v2 API over the copied Wisp implementation (`Wisp/Nip44.swift`).
public enum NIP44 {
    public enum Failure: Error, Equatable {
        case invalidKey
        case invalidPlaintextLength
        case invalidPayload
        case unknownVersion
        case invalidMAC
        case invalidPadding
    }

    /// Conversation key for (my private key, their x-only public key). For a
    /// self-encrypted journal entry, `peerPublicKey` is the user's own pubkey.
    public static func conversationKey(privateKey: Data, peerPublicKey: Data) throws -> Data {
        guard privateKey.count == 32, peerPublicKey.count == 32 else { throw Failure.invalidKey }
        do { return try Nip44.getConversationKey(privkey32: privateKey, peerXonlyPubkey32: peerPublicKey) }
        catch { throw Failure.invalidKey }
    }

    /// Encrypt. `nonce` is for test vectors only; production code passes nil (random nonce).
    public static func encrypt(_ plaintext: String, conversationKey: Data, nonce: Data? = nil) throws -> String {
        do { return try Nip44.encrypt(plaintext: plaintext, conversationKey: conversationKey, nonce: nonce) }
        catch { throw map(error) }
    }

    public static func decrypt(_ payload: String, conversationKey: Data) throws -> String {
        do { return try Nip44.decrypt(payload: payload, conversationKey: conversationKey) }
        catch { throw map(error) }
    }

    /// Encrypt to self: the encryption private journal entries and settings use.
    public static func encryptToSelf(_ plaintext: String, privateKey: Data) throws -> String {
        let key = try conversationKey(privateKey: privateKey, peerPublicKey: try NostrKeys.publicKey(for: privateKey))
        return try encrypt(plaintext, conversationKey: key)
    }

    public static func decryptFromSelf(_ payload: String, privateKey: Data) throws -> String {
        let key = try conversationKey(privateKey: privateKey, peerPublicKey: try NostrKeys.publicKey(for: privateKey))
        return try decrypt(payload, conversationKey: key)
    }

    private static func map(_ error: Error) -> Failure {
        switch error as? Nip44.Error {
        case .invalidVersion: return .unknownVersion
        case .macMismatch: return .invalidMAC
        case .invalidPadding: return .invalidPadding
        case .invalidPlaintextLength: return .invalidPlaintextLength
        case .invalidPayload, .none: return .invalidPayload
        }
    }
}
