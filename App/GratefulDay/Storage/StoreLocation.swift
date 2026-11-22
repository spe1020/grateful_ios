import Foundation

/// Where the journal lives on disk, and the protection applied to it
/// (storage recommendation §1–3).
///
/// Everything that holds reflection text goes in one `Store/` directory under
/// Application Support. Not Caches or tmp (the system can purge them), not
/// Documents (backed up, can be exposed in Files), not UserDefaults.
struct StoreLocation: Sendable {
    let directory: URL

    var storeURL: URL { directory.appendingPathComponent("journal.store", isDirectory: false) }

    static var standard: StoreLocation {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StoreLocation(directory: support
            .appendingPathComponent("GratefulDay", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true))
    }

    struct Preparation: Equatable, Sendable {
        /// False when setting `isExcludedFromBackup` failed. The store still
        /// opens (refusing would lock the user out of their journal); the
        /// failure is reported, without content, as a diagnostic.
        var backupExclusionApplied: Bool
    }

    /// Run on every launch, before the store opens: create `Store/` with
    /// complete protection if it's missing, then (re)apply the backup
    /// exclusion. The exclusion is lost if the directory is ever recreated,
    /// so it's applied every time.
    func prepare(fileManager: FileManager = .default) throws -> Preparation {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        try? fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        do {
            try url.setResourceValues(values)
            return Preparation(backupExclusionApplied: true)
        } catch {
            return Preparation(backupExclusionApplied: false)
        }
    }

    /// Set complete protection on every file in `Store/` (the store and its
    /// SQLite `-wal`/`-shm` sidecars), in case the directory attribute or the
    /// app-wide entitlement didn't carry over to a file. Only called while
    /// protected data is available.
    func protectFiles(fileManager: FileManager = .default) throws {
        for name in try fileManager.contentsOfDirectory(atPath: directory.path) {
            let path = directory.appendingPathComponent(name).path
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        }
    }
}
