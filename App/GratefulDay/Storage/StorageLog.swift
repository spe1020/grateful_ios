import Foundation
import os

/// Storage diagnostics. Never logs reflection text, dates or counts: only a
/// fixed message, a store file name and an error domain/code.
enum StorageLog {
    static let logger = Logger(subsystem: "app.gratefulday.ios", category: "storage")

    /// The most recent messages, kept in memory so tests can check what was
    /// logged (and that it holds no content).
    @MainActor private(set) static var recent: [String] = []

    static func error(_ message: StaticString, file: String? = nil, error: Error? = nil) {
        var line = "\(message)"
        if let file { line += " [file: \(file)]" }
        if let error {
            let ns = error as NSError
            line += " [\(ns.domain) \(ns.code)]"
        }
        logger.error("\(line, privacy: .public)")
        Task { @MainActor in
            recent.append(line)
            if recent.count > 50 { recent.removeFirst(recent.count - 50) }
        }
    }

    @MainActor static func clearRecent() { recent.removeAll() }
}
