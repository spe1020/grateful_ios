import Foundation
import Observation
import SwiftData

/// Opens the journal only when it is safe to, and says so when it isn't.
///
/// - The store opens only while protected data is available (Audit S2). iOS can
///   launch the app before first unlock; a `.complete` store can't be read
///   then, and an open attempt must never be mistaken for "no journal".
/// - Any failure leaves the app in `.failed`, with a retry. Nothing here ever
///   deletes, replaces or recreates an existing store file.
/// - CloudKit is off explicitly (Audit S1): the default would start mirroring
///   reflection text if the app ever gained an iCloud entitlement.
@MainActor
@Observable
final class JournalStore {
    enum State {
        /// Protected data isn't available yet (device locked, or not yet
        /// unlocked since restart). Shown as a calm locked state.
        case waitingForUnlock
        case open(ModelContainer)
        case failed
    }

    private(set) var state: State = .waitingForUnlock
    /// The backup exclusion isn't in effect on this device. While set, the
    /// app must not say reflections are left out of backups (Chief P10).
    private(set) var backupExclusionFailed = false
    /// Complete file protection couldn't be applied to the directory or a
    /// store file. No UI state (no copy claims it); it blocks any future
    /// "encrypted" claim and is logged (P10.5).
    private(set) var protectionFailed = false
    /// True once a backup-exclusion check has succeeded in this launch. Until
    /// then the app makes no backup claim (Chief P11).
    private(set) var backupExclusionConfirmed = false

    /// Whether the app may say reflections are left out of backups right now.
    var mayClaimBackupExclusion: Bool { backupExclusionConfirmed && !backupExclusionFailed }

    let location: StoreLocation

    private let defaults: UserDefaults

    init(location: StoreLocation = .standard, defaults: UserDefaults = .standard) {
        self.location = location
        self.defaults = defaults
    }

    var container: ModelContainer? {
        if case .open(let container) = state { return container }
        return nil
    }

    static let schema = Schema(versionedSchema: JournalSchemaV4.self)

    static func configuration(url: URL) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    }

    /// Open the store if it isn't open yet and protected data is available.
    /// Called on every foreground: when the store is already open, it
    /// re-applies the backup exclusion and protection and clears the flags
    /// once they succeed (P10 item 2).
    func openIfPossible(protectedDataAvailable: Bool) {
        if case .open = state {
            if protectedDataAvailable { reapplyProtections() }
            return
        }
        guard protectedDataAvailable else {
            state = .waitingForUnlock
            return
        }
        do {
            let prepared = try location.prepare()
            record(prepared)
            // An existing store we can't read is "unknown", never "empty":
            // fail here rather than let anything create a new one in its place.
            let path = location.storeURL.path
            if FileManager.default.fileExists(atPath: path), !FileManager.default.isReadableFile(atPath: path) {
                StorageLog.error("Existing store not readable", file: location.storeURL.lastPathComponent)
                state = .failed
                return
            }
            let container = try ModelContainer(for: Self.schema, migrationPlan: JournalMigrationPlan.self,
                                               configurations: Self.configuration(url: location.storeURL))
            // A protection failure never locks the user out (P10.5).
            let filesProtected = location.protectFiles()
            protectionFailed = !(prepared.protectionApplied && filesProtected)
            state = .open(container)
        } catch {
            StorageLog.error("Journal store could not be opened", file: location.storeURL.lastPathComponent, error: error)
            state = .failed
        }
    }

    private func reapplyProtections() {
        guard let prepared = try? location.prepare() else {
            backupExclusionFailed = true
            protectionFailed = true
            return
        }
        record(prepared)
        let filesProtected = location.protectFiles()
        protectionFailed = !(prepared.protectionApplied && filesProtected)
    }

    private func record(_ prepared: StoreLocation.Result) {
        backupExclusionFailed = !prepared.backupExclusionApplied
        if prepared.backupExclusionApplied { backupExclusionConfirmed = true }
        if !prepared.protectionApplied { protectionFailed = true }
    }

    /// Delete the journal store files ("Remove account and local data",
    /// design §6), then open a fresh, empty store. Only ever called after
    /// the person's explicit confirmation. On failure the old store is
    /// reopened and false is returned; the caller says "Couldn't remove
    /// your reflections. Try again."
    func removeAllData() -> Bool {
        // Recorded before anything is deleted, and kept across relaunches:
        // a folder delete can remove some files before it fails, so from
        // here until a clean, reopened store, "Nothing has been deleted"
        // would be untrue (Seth, Audit #13 review).
        removalIncomplete = true
        state = .waitingForUnlock
        do {
            if FileManager.default.fileExists(atPath: location.directory.path) {
                try FileManager.default.removeItem(at: location.directory)
            }
        } catch {
            StorageLog.error("Removing the journal store failed", error: error)
            openIfPossible(protectedDataAvailable: true)
            return false
        }
        openIfPossible(protectedDataAvailable: true)
        if container != nil { removalIncomplete = false }
        return container != nil
    }

    /// A "Remove account and local data" started but didn't finish cleanly.
    /// A non-sensitive flag in UserDefaults so it survives a relaunch.
    var removalIncomplete: Bool {
        get { defaults.bool(forKey: Self.removalIncompleteKey) }
        set {
            defaults.set(newValue, forKey: Self.removalIncompleteKey)
            removalIncompleteVersion += 1
        }
    }
    /// Bumped on every change so views observing the store redraw.
    private(set) var removalIncompleteVersion = 0
    static let removalIncompleteKey = "journal.removalIncomplete"

    /// Set when the save before the device locked failed (Audit M2 I2).
    /// Unsaved text is still held by the editor, which retries on unlock.
    private(set) var lockSaveFailed = false

    /// Finish any pending save before the device locks the files.
    func saveBeforeLock() {
        guard let context = container?.mainContext, context.hasChanges else { return }
        do {
            try context.save()
            lockSaveFailed = false
        } catch {
            lockSaveFailed = true
            StorageLog.error("Save before lock failed", error: error)
        }
    }
}
