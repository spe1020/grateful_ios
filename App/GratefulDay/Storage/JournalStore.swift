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

    let location: StoreLocation

    init(location: StoreLocation = .standard) {
        self.location = location
    }

    var container: ModelContainer? {
        if case .open(let container) = state { return container }
        return nil
    }

    static let schema = Schema([JournalEntry.self])

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
            // An existing store we can't read is "unknown", never "empty":
            // fail here rather than let anything create a new one in its place.
            let path = location.storeURL.path
            if FileManager.default.fileExists(atPath: path), !FileManager.default.isReadableFile(atPath: path) {
                StorageLog.error("Existing store not readable", file: location.storeURL.lastPathComponent)
                state = .failed
                return
            }
            let container = try ModelContainer(for: Self.schema, configurations: Self.configuration(url: location.storeURL))
            // A protection failure never locks the user out (P10.5).
            let filesProtected = location.protectFiles()
            backupExclusionFailed = !prepared.backupExclusionApplied
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
        let filesProtected = location.protectFiles()
        backupExclusionFailed = !prepared.backupExclusionApplied
        protectionFailed = !(prepared.protectionApplied && filesProtected)
    }

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
