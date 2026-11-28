import Foundation
import SQLite3

/// D10 (Audit's "no real write" definition, Chief P214): what a store looks
/// like on disk, so a test can tell a real write to the journal (data or file
/// identity changed) from SQLite bookkeeping (bytes moved, data the same).
/// Reads the real files only; every SQL read runs on a temporary copy.
struct StoreSnapshot {
    static let suffixes = ["", "-wal", "-shm"]

    /// Bytes of `journal.store`, `-wal` and `-shm`; nil for a missing file.
    let bytes: [String: Data?]
    /// The store file's inode, nil when it is missing.
    let inode: UInt64?
    /// Schema, every table's rows and `user_version`, read from a copy.
    let logical: [String]

    init(storeURL: URL) throws {
        var bytes: [String: Data?] = [:]
        for suffix in Self.suffixes {
            bytes[suffix] = try? Data(contentsOf: Self.url(storeURL, suffix))
        }
        self.bytes = bytes
        let attributes = try? FileManager.default.attributesOfItem(atPath: storeURL.path)
        inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
        logical = inode == nil ? [] : try Self.dump(copyOf: storeURL)
    }

    static func url(_ storeURL: URL, _ suffix: String) -> URL {
        URL(fileURLWithPath: storeURL.path + suffix)
    }

    /// Checkpoints the WAL into the main file and truncates it, on the real
    /// store. Only for setup, before any snapshot.
    static func checkpoint(storeURL: URL) throws {
        try withDatabase(storeURL) { db in
            try exec(db, "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// The test's planted faults (M1/M3) write through this; nothing else does.
    static func execute(_ sql: String, storeURL: URL) throws {
        try withDatabase(storeURL) { db in try exec(db, sql) }
    }

    /// The first `limit` offsets where `a` and `b` differ, counting a length
    /// difference from the shorter end. Offsets only: never content.
    static func differingOffsets(_ a: Data, _ b: Data, limit: Int = 16) -> [Int] {
        var offsets: [Int] = []
        let common = min(a.count, b.count)
        a.withUnsafeBytes { pa in
            b.withUnsafeBytes { pb in
                var i = 0
                while i < common && offsets.count < limit {
                    if pa[i] != pb[i] { offsets.append(i) }
                    i += 1
                }
            }
        }
        if offsets.count < limit && a.count != b.count { offsets.append(common) }
        return offsets
    }

    // MARK: - SQLite

    struct SQLiteError: Error, CustomStringConvertible {
        let description: String
    }

    private static func dump(copyOf storeURL: URL) throws -> [String] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("d10-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appendingPathComponent(storeURL.lastPathComponent)
        for suffix in suffixes where FileManager.default.fileExists(atPath: url(storeURL, suffix).path) {
            try FileManager.default.copyItem(at: url(storeURL, suffix), to: url(copy, suffix))
        }
        return try withDatabase(copy) { db in
            var lines: [String] = []
            let schema = try rows(db, "SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name")
            lines += schema.map { "schema " + $0.joined(separator: "|") }
            // Values are tagged by storage class, so a table name is "t:NAME".
            for table in schema where table[0] == "t:table" {
                let raw = String(table[1].dropFirst(2))
                let name = raw.replacingOccurrences(of: "\"", with: "\"\"")
                // Core Data's tables all have a rowid; fall back to the first
                // column so a WITHOUT ROWID table still dumps in a stable order.
                let ordered: [[String]]
                if let byRowid = try? rows(db, "SELECT * FROM \"\(name)\" ORDER BY rowid") {
                    ordered = byRowid
                } else {
                    ordered = try rows(db, "SELECT * FROM \"\(name)\" ORDER BY 1")
                }
                lines += ordered.map { "row \(raw) " + $0.joined(separator: "|") }
            }
            lines += try rows(db, "PRAGMA user_version").map { "user_version " + $0.joined() }
            return lines
        }
    }

    private static func withDatabase<T>(_ url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"
            sqlite3_close(db)
            throw SQLiteError(description: "open: \(message)")
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError(description: "exec: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    private static func rows(_ db: OpaquePointer, _ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError(description: "prepare: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw SQLiteError(description: "step: \(String(cString: sqlite3_errmsg(db)))") }
            result.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
        }
        return result
    }

    /// One value, tagged with its storage class so 1, 1.0, "1" and a blob differ.
    private static func column(_ statement: OpaquePointer, _ i: Int32) -> String {
        switch sqlite3_column_type(statement, i) {
        case SQLITE_NULL: return "null"
        case SQLITE_INTEGER: return "i:\(sqlite3_column_int64(statement, i))"
        case SQLITE_FLOAT: return "f:\(sqlite3_column_double(statement, i).bitPattern)"
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, i))
            guard count > 0, let pointer = sqlite3_column_blob(statement, i) else { return "b:" }
            return "b:" + Data(bytes: pointer, count: count).base64EncodedString()
        default:
            return "t:" + String(cString: sqlite3_column_text(statement, i))
        }
    }
}
