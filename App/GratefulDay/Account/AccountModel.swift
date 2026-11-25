import Foundation
import Observation
import Security
import SwiftData
import NostrCore

/// The account state of this install and the key actions (design r3.1 §5–7,
/// Seth's decisions, Chief P13–P17). No network code: connecting and sync
/// are M5b.
@MainActor
@Observable
final class AccountModel {
    /// Design §7. Only `.guest` and `.signedOut` may offer creating a key, and
    /// only after an explicit confirmation.
    enum State: Equatable {
        /// The marker can't be read (store locked, failed or not open yet).
        /// Onboarding, key creation and publishing are all blocked.
        case unknown
        case guest
        case connected(pubkey: String)
        case signedOut(pubkey: String)
        /// The marker says connected but the key isn't on this iPhone. Never a new key.
        case keyMissing(pubkey: String)
        case locked
        case keyUnavailable(OSStatus)
        case mismatch(keyPubkey: String, markerPubkey: String)
    }

    enum ActionError: Error, Equatable {
        case notAllowedNow
        case invalidKey
        case belongsToAnotherAccount
        case keychain
        case journalUnreadable
    }

    private(set) var state: State = .unknown
    private let vault: KeyVault
    private let now: () -> Date

    init(vault: KeyVault = KeyVault(), now: @escaping () -> Date = { .now }) {
        self.vault = vault
        self.now = now
    }

    /// The pubkey whose rows the editor and calendar use, if connected.
    var activeOwner: String? {
        if case .connected(let pubkey) = state { return pubkey }
        return nil
    }

    // MARK: Marker

    private func marker(_ context: ModelContext) throws -> AccountMarker? {
        var d = FetchDescriptor<AccountMarker>()
        d.fetchLimit = 1
        return try context.fetch(d).first
    }

    private func setMarker(_ context: ModelContext, pubkey: String, state markerState: AccountMarkerState) throws {
        if let m = try marker(context) {
            m.pubkey = pubkey
            m.stateRaw = markerState.rawValue
            m.updatedAt = now()
        } else {
            context.insert(AccountMarker(pubkey: pubkey, state: markerState, now: now()))
        }
        try context.save()
    }

    // MARK: State (design §7)

    /// Recompute the state. `context` is nil while the store isn't open.
    func refresh(context: ModelContext?) {
        guard let context, let markerResult = Result(catching: { try marker(context) }).successValue else {
            state = .unknown
            return
        }
        let m = markerResult
        switch vault.readPrimary() {
        case .locked:
            state = .locked
        case .failed(let status):
            StorageLog.error("Journal key read failed", error: NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
            state = .keyUnavailable(status)
        case .notFound:
            switch m?.state {
            case nil: state = .guest
            case .connected: state = .keyMissing(pubkey: m!.pubkey)
            case .signedOut: state = .signedOut(pubkey: m!.pubkey)
            }
        case .key(_, let pubkey):
            switch m?.state {
            case nil:
                // Reinstall: the key survived, the journal didn't. Treat as
                // connected; M5b fetches first before anything else. A failed
                // marker write is logged and retried when it's needed (L4).
                do {
                    try setMarker(context, pubkey: pubkey, state: .connected)
                } catch {
                    StorageLog.error("Recording the connected account failed", error: error)
                }
                state = .connected(pubkey: pubkey)
            case .connected:
                state = m!.pubkey == pubkey ? .connected(pubkey: pubkey)
                    : .mismatch(keyPubkey: pubkey, markerPubkey: m!.pubkey)
            case .signedOut:
                // A key added after sign-out: connecting (the same or another
                // account). Signed-out rows keep their owner (P16/P17).
                if (try? setMarker(context, pubkey: pubkey, state: .connected)) != nil {
                    state = .connected(pubkey: pubkey)
                } else {
                    state = .unknown
                }
            }
        }
    }

    // MARK: Create, import, restore

    /// Create a new journal key. Allowed only as guest or signed out; the UI
    /// must have shown the create-key confirmation (design §5).
    func createKey(context: ModelContext) throws(ActionError) -> String {
        guard state == .guest || isSignedOut else { throw .notAllowedNow }
        let secret: Data
        do { secret = try NostrKeys.generatePrivateKey() } catch { throw .keychain }
        return try connect(secret: secret, context: context)
    }

    /// Import an existing key ("Use my Nostr account", design §6a). Refused
    /// while connected. With a missing key, only the same account.
    func importKey(_ input: String, context: ModelContext) throws(ActionError) -> String {
        guard let secret = KeyInput.parse(input) else { throw .invalidKey }
        return try connectAllowingKeyMissing(secret: secret, context: context)
    }

    /// Restore from an iCloud Keychain backup ("I've used Grateful Day before").
    func restore(_ backup: KeyVault.Backup, context: ModelContext) throws(ActionError) -> String {
        guard let secret = vault.backupSecret(backup) else { throw .keychain }
        return try connectAllowingKeyMissing(secret: secret, context: context)
    }

    private var isSignedOut: Bool {
        if case .signedOut = state { return true }
        return false
    }

    private func connectAllowingKeyMissing(secret: Data, context: ModelContext) throws(ActionError) -> String {
        if case .keyMissing(let marked) = state {
            guard KeyVault.pubkeyHex(for: secret) == marked else { throw .belongsToAnotherAccount }
            return try connect(secret: secret, context: context)
        }
        guard state == .guest || isSignedOut else { throw .notAllowedNow }
        return try connect(secret: secret, context: context)
    }

    private func connect(secret: Data, context: ModelContext) throws(ActionError) -> String {
        let pubkey: String
        do {
            pubkey = try vault.savePrimaryVerified(secret)
        } catch .invalidKey {
            throw .invalidKey
        } catch {
            StorageLog.error("Saving the journal key failed")
            throw .keychain
        }
        do {
            try setMarker(context, pubkey: pubkey, state: .connected)
        } catch {
            // Key saved, marker not: the next refresh sees "key, no marker"
            // and treats it as connected. Log it; no data is at risk.
            StorageLog.error("Recording the connected account failed", error: error)
        }
        state = .connected(pubkey: pubkey)
        return pubkey
    }

    // MARK: Backup

    var backups: KeyVault.BackupList { vault.listBackups() }
    var skippedBackups: Int { vault.skippedBackups }

    /// The connected account's key, for decrypting fetched entries. Nil
    /// unless connected.
    func connectedKey() -> (secret: Data, pubkey: String)? {
        guard case .connected(let p) = state, case .key(let secret, let pubkey) = vault.readPrimary(), pubkey == p
        else { return nil }
        return (secret, pubkey)
    }

    func hasBackup(for pubkey: String) -> Bool? {
        guard case .backups(let list) = vault.listBackups() else { return nil }
        return list.contains { $0.pubkey == pubkey }
    }

    /// Keep a backup copy of the connected key in iCloud Keychain. Only after
    /// the person's affirmative choice (Seth 9.2).
    func backUpKey() throws(ActionError) {
        guard case .connected = state, case .key(let secret, _) = vault.readPrimary() else { throw .notAllowedNow }
        do { _ = try vault.saveBackup(secret) } catch { throw .keychain }
    }

    func deleteBackups(for pubkey: String) -> Bool {
        guard case .backups(let list) = vault.listBackups() else { return false }
        return list.filter { $0.pubkey == pubkey }.allSatisfy { vault.deleteBackup($0) }
    }

    // MARK: Sign out and remove (design §6, Chief P16)

    /// What the sign-out warning counts: this account's reflections not yet
    /// saved to it, and reflections written with no account (#27). Nil when
    /// it can't be read: the action is then blocked.
    func unsyncedCount(context: ModelContext) -> JournalRepository.SignOutCounts? {
        try? JournalRepository(context: context, activeOwner: activeOwner).signOutCounts()
    }

    enum SignOutResult: Equatable { case signedOut, stayedSignedIn, unconfirmed, blocked }

    /// The marker, readable (possibly absent), or nil when it can't be read.
    /// On the reinstall path a missing marker is written now (Audit M5a L4),
    /// so a failed earlier write doesn't block sign-out or removal.
    private func readableMarker(_ context: ModelContext, connectedPubkey: String?) -> AccountMarker?? {
        guard case .success(let m) = Result(catching: { try marker(context) }) else { return nil }
        if m == nil, let connectedPubkey {
            do {
                try setMarker(context, pubkey: connectedPubkey, state: .connected)
                return .some(try marker(context))
            } catch {
                StorageLog.error("Recording the connected account failed", error: error)
                return nil
            }
        }
        return .some(m)
    }

    /// Ordinary sign-out: delete this iPhone's key (confirmed), keep the
    /// journal with every entry's owner, never touch the iCloud backup.
    func signOut(context: ModelContext) -> SignOutResult {
        guard case .connected(let pubkey) = state,
              readableMarker(context, connectedPubkey: pubkey) != nil, unsyncedCount(context: context) != nil
        else { return .blocked }
        switch vault.deletePrimary() {
        case .deleted: break
        case .deleteFailed:
            StorageLog.error("Sign-out: removing the journal key failed")
            return .stayedSignedIn
        case .unconfirmed:
            // State is left as it was, so [Try again] re-runs the delete and
            // its confirmation instead of being blocked by a locked re-read.
            StorageLog.error("Sign-out: couldn't confirm the journal key was removed")
            return .unconfirmed
        }
        do {
            try setMarker(context, pubkey: pubkey, state: .signedOut)
        } catch {
            // Key gone, marker still "connected": next launch shows "Key
            // missing" and offers restore, which is safe (design §6).
            StorageLog.error("Sign-out: recording the signed-out state failed", error: error)
        }
        state = .signedOut(pubkey: pubkey)
        return .signedOut
    }

    enum RemoveResult: Equatable {
        case removed
        /// The key delete call failed; nothing has been deleted.
        case keyDeleteFailed
        /// The key delete succeeded but couldn't be confirmed; the journal
        /// wasn't touched (Audit #13 L1).
        case keyDeleteUnconfirmed
        case journalNotRemoved
        case blocked
    }

    /// "Remove account and local data": delete the key (confirmed, abort on
    /// failure), then the journal store. The iCloud backup is a separate
    /// question afterwards (`deleteBackups`), default keep.
    func removeAccountAndData(context: ModelContext, store: JournalStore) -> RemoveResult {
        switch state {
        case .connected, .signedOut, .keyMissing, .mismatch: break
        default: return .blocked
        }
        guard readableMarker(context, connectedPubkey: activeOwner) != nil, unsyncedCount(context: context) != nil
        else { return .blocked }
        if vault.readPrimary() != .notFound {
            switch vault.deletePrimary() {
            case .deleted: break
            case .deleteFailed:
                StorageLog.error("Remove account: removing the journal key failed")
                return .keyDeleteFailed
            case .unconfirmed:
                // The journal isn't touched until the delete is confirmed;
                // state is kept so [Try again] can re-run it (Prep, F8).
                StorageLog.error("Remove account: couldn't confirm the journal key was removed")
                return .keyDeleteUnconfirmed
            }
        }
        guard store.removeAllData() else {
            StorageLog.error("Remove account: removing the journal failed")
            state = .unknown
            return .journalNotRemoved
        }
        state = .guest
        return .removed
    }
}

private extension Result where Failure == Error {
    var successValue: Success? {
        if case .success(let v) = self { return v }
        return nil
    }
}

/// Parsing an imported key: `nsec1…` or 64 hex characters (design §6a).
enum KeyInput {
    static func parse(_ raw: String) -> Data? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret: Data?
        if text.lowercased().hasPrefix("nsec1") {
            secret = try? NostrKeys.decodeNsec(text.lowercased())
        } else if text.count == 64 {
            secret = NostrKeys.data(hex: text.lowercased())
        } else {
            secret = nil
        }
        guard let secret, secret.count == 32, NostrKeys.isValidPrivateKey(secret) else { return nil }
        return secret
    }
}
