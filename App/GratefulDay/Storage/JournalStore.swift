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
    /// Non-sensitive diagnostic: the backup exclusion could not be applied.
    private(set) var backupExclusionFailed = false

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
    func openIfPossible(protectedDataAvailable: Bool) {
        if case .open = state { return }
        guard protectedDataAvailable else {
            state = .waitingForUnlock
            return
        }
        do {
            let preparation = try location.prepare()
            backupExclusionFailed = !preparation.backupExclusionApplied
            // An existing store we can't read is "unknown", never "empty":
            // fail here rather than let anything create a new one in its place.
            let path = location.storeURL.path
            if FileManager.default.fileExists(atPath: path), !FileManager.default.isReadableFile(atPath: path) {
                state = .failed
                return
            }
            let container = try ModelContainer(for: Self.schema, configurations: Self.configuration(url: location.storeURL))
            try location.protectFiles()
            state = .open(container)
        } catch {
            state = .failed
        }
    }

    /// Finish any pending save before the device locks the files.
    func saveBeforeLock() {
        guard let context = container?.mainContext, context.hasChanges else { return }
        try? context.save()
    }
}
