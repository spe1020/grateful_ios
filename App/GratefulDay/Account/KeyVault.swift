import Foundation
import Security
import NostrCore

/// The journal key on this iPhone, and its optional iCloud Keychain backup
/// (design r3.1 §3, written fresh per Seth's decision 9.5).
///
/// - Primary key: generic password, `WhenUnlockedThisDeviceOnly`, never
///   synchronized. Never in UserDefaults, SwiftData, logs or analytics.
/// - Backup: a separate synchronized item, `WhenUnlocked`, opaque name,
///   holding the key with no extra secret (Seth: no PIN). Only created by
///   an affirmative choice.
final class KeyVault {
    static let primaryService = "app.gratefulday.ios.journal-key"
    static let primaryAccount = "primary"
    static let backupService = "app.gratefulday.ios.journal-key-backup"

    private let keychain: KeychainStoring

    init(keychain: KeychainStoring = SystemKeychain()) {
        self.keychain = keychain
    }

    // MARK: Primary key

    enum PrimaryRead: Equatable {
        case key(secret: Data, pubkey: String)
        case notFound
        case locked
        case failed(OSStatus)
    }

    func readPrimary() -> PrimaryRead {
        switch keychain.read(service: Self.primaryService, account: Self.primaryAccount, synchronizable: false) {
        case .found(let data):
            guard let pubkey = Self.pubkeyHex(for: data) else { return .failed(errSecDecode) }
            return .key(secret: data, pubkey: pubkey)
        case .notFound: return .notFound
        case .locked: return .locked
        case .failed(let s): return .failed(s)
        }
    }

    enum WriteError: Error, Equatable {
        case alreadyPresent
        case invalidKey
        case keychain(OSStatus)
        /// Read-back didn't match; what was written has been removed.
        case verificationFailed
    }

    /// Store the primary key, then read it back and compare the derived
    /// pubkey. On mismatch or error, remove what was written (design §6a).
    func savePrimaryVerified(_ secret: Data) throws(WriteError) -> String {
        guard let pubkey = Self.pubkeyHex(for: secret) else { throw .invalidKey }
        let status = keychain.add(secret, service: Self.primaryService, account: Self.primaryAccount,
                                  synchronizable: false, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        if status == errSecDuplicateItem { throw .alreadyPresent }
        guard status == errSecSuccess else { throw .keychain(status) }
        guard case .key(_, let readBack) = readPrimary(), readBack == pubkey else {
            _ = keychain.delete(service: Self.primaryService, account: Self.primaryAccount, synchronizable: false)
            throw .verificationFailed
        }
        return pubkey
    }

    /// Delete the primary key and confirm it's gone: success only when a
    /// re-read returns `notFound` (design §6).
    enum DeleteOutcome: Equatable {
        /// Deleted, and a re-read confirms it's gone.
        case deleted
        /// The delete call itself failed: the key is still there.
        case deleteFailed
        /// The delete call succeeded but the re-read couldn't confirm it
        /// (locked or failed): the key may or may not be gone (Audit #13 L1).
        case unconfirmed
    }

    func deletePrimary() -> DeleteOutcome {
        let status = keychain.delete(service: Self.primaryService, account: Self.primaryAccount, synchronizable: false)
        guard status == errSecSuccess || status == errSecItemNotFound else { return .deleteFailed }
        switch readPrimary() {
        case .notFound: return .deleted
        case .key: return .deleteFailed
        case .locked, .failed: return .unconfirmed
        }
    }

    func deletePrimaryVerified() -> Bool { deletePrimary() == .deleted }

    // MARK: iCloud Keychain backup

    struct Backup: Equatable {
        let account: String
        let pubkey: String
        let created: Date?
    }

    enum BackupList: Equatable {
        case backups([Backup])
        /// Couldn't list or decode: "backup unavailable", never "no backup".
        case unavailable
    }

    private struct BackupPayload: Codable {
        let v: Int
        let kind: String
        let key: String
        let created: Date?
    }

    /// Backup items that couldn't be read or decoded in the last listing.
    /// They're skipped, not treated as "no backup" (Audit M5a L3).
    private(set) var skippedBackups = 0

    /// Backups visible on this device (those synced here by iCloud Keychain).
    /// An item that can't be read is skipped and counted, so it doesn't
    /// block restoring the others (Audit M5a L3).
    func listBackups() -> BackupList {
        switch keychain.accounts(service: Self.backupService, synchronizable: true) {
        case .failure: return .unavailable
        case .success(let accounts):
            var found: [Backup] = []
            var skipped = 0
            for account in accounts.sorted() {
                guard case .found(let data) = keychain.read(service: Self.backupService, account: account, synchronizable: true),
                      let payload = Self.decodePayload(data), let secret = Data(base64Encoded: payload.key),
                      let pubkey = Self.pubkeyHex(for: secret)
                else { skipped += 1; continue }
                found.append(Backup(account: account, pubkey: pubkey, created: payload.created))
            }
            skippedBackups = skipped
            if found.isEmpty && skipped > 0 { return .unavailable }
            // Newest first (Prep F3).
            return .backups(found.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) })
        }
    }

    /// The key held by a backup, or nil if it can't be read.
    func backupSecret(_ backup: Backup) -> Data? {
        guard case .found(let data) = keychain.read(service: Self.backupService, account: backup.account, synchronizable: true)
        else { return nil }
        return Self.decodeBackup(data)
    }

    /// Write a new backup item. Never overwrites an existing one. A successful
    /// write only means "saved"; whether it syncs depends on iCloud Keychain
    /// being on, which the app can't detect (design §5).
    func saveBackup(_ secret: Data) throws(WriteError) -> Backup {
        guard let pubkey = Self.pubkeyHex(for: secret) else { throw .invalidKey }
        let created = Date()
        let payload = BackupPayload(v: 1, kind: "plain", key: secret.base64EncodedString(), created: created)
        guard let data = try? JSONEncoder().encode(payload) else { throw .invalidKey }
        let account = "bk_\(UUID().uuidString)"
        let status = keychain.add(data, service: Self.backupService, account: account,
                                  synchronizable: true, accessibility: kSecAttrAccessibleWhenUnlocked)
        guard status == errSecSuccess else { throw .keychain(status) }
        return Backup(account: account, pubkey: pubkey, created: created)
    }

    func deleteBackup(_ backup: Backup) -> Bool {
        let status = keychain.delete(service: Self.backupService, account: backup.account, synchronizable: true)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: Helpers

    static func pubkeyHex(for secret: Data) -> String? {
        guard NostrKeys.isValidPrivateKey(secret), let pub = try? NostrKeys.publicKey(for: secret) else { return nil }
        return NostrKeys.hex(pub)
    }

    private static func decodePayload(_ data: Data) -> BackupPayload? {
        guard let payload = try? JSONDecoder().decode(BackupPayload.self, from: data),
              payload.v == 1, payload.kind == "plain" else { return nil }
        return payload
    }

    private static func decodeBackup(_ data: Data) -> Data? {
        decodePayload(data).flatMap { Data(base64Encoded: $0.key) }
    }
}
