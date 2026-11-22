import Foundation

/// Where the journal lives on disk, and the protection applied to it
/// (storage recommendation §1–3; failure handling per Chief P10).
///
/// Everything that holds reflection text goes in one `Store/` directory under
/// Application Support. Not Caches or tmp (the system can purge them), not
/// Documents (backed up, can be exposed in Files), not UserDefaults.
struct StoreLocation: Sendable {
    /// The two file-system calls whose failure must be reported, never
    /// thrown into the open path or ignored. Injectable so tests can force
    /// failures.
    struct Attributes: Sendable {
        var excludeFromBackup: @Sendable (URL) throws -> Void
        var setCompleteProtection: @Sendable (String) throws -> Void

        static let system = Attributes(
            excludeFromBackup: { directory in
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var url = directory
                try url.setResourceValues(values)
            },
            setCompleteProtection: { path in
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
            }
        )
    }

    let directory: URL
    var attributes: Attributes = .system

    var storeURL: URL { directory.appendingPathComponent("journal.store", isDirectory: false) }

    static var standard: StoreLocation {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return StoreLocation(directory: support
            .appendingPathComponent("GratefulDay", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true))
    }

    /// What `prepare` / `protectFiles` managed to apply. Failures are
    /// reported here (and logged without content), never thrown: the
    /// journal still opens, because refusing would lock the user out of
    /// their only copy (P10).
    struct Result: Equatable, Sendable {
        var backupExclusionApplied = true
        var protectionApplied = true
    }

    /// Run on every open and every foreground: create `Store/` with complete
    /// protection if it's missing, then (re)apply protection and the backup
    /// exclusion. The exclusion is lost if the directory is ever recreated,
    /// so it's applied every time. Throws only if the directory can't be
    /// created at all.
    func prepare(fileManager: FileManager = .default) throws -> Result {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        }
        var result = Result()
        do {
            try attributes.setCompleteProtection(directory.path)
        } catch {
            result.protectionApplied = false
            StorageLog.error("Protection class not applied", file: directory.lastPathComponent, error: error)
        }
        do {
            try attributes.excludeFromBackup(directory)
        } catch {
            result.backupExclusionApplied = false
            StorageLog.error("Backup exclusion not applied", file: directory.lastPathComponent, error: error)
        }
        return result
    }

    /// Set complete protection on every file in `Store/` (the store and its
    /// SQLite `-wal`/`-shm` sidecars), in case the directory attribute or the
    /// app-wide entitlement didn't carry over to a file. Only called while
    /// protected data is available. Returns false if any file failed.
    func protectFiles(fileManager: FileManager = .default) -> Bool {
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: directory.path)
        } catch {
            StorageLog.error("Store directory not listable", file: directory.lastPathComponent, error: error)
            return false
        }
        var allApplied = true
        for name in names {
            do {
                try attributes.setCompleteProtection(directory.appendingPathComponent(name).path)
            } catch {
                allApplied = false
                StorageLog.error("Protection class not applied", file: name, error: error)
            }
        }
        return allApplied
    }
}
