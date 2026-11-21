import Foundation

/// A day's entry holds one or more notes in the single 36669 event's plain-text
/// content, separated by a blank line. Port of web `src/lib/entryNotes.ts`
/// (interop spec r3 §1.2). Never JSON.
public enum EntryNotes {
    public static let separator = "\n\n"

    /// Normalize CR/CRLF to LF, split on one or more blank lines (whitespace-only
    /// lines count as blank), trim each note, drop empties.
    public static func split(_ content: String) -> [String] {
        let lf = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Web: /\n[ \t]*(?:\n[ \t]*)+/
        let pieces = lf.replacingOccurrences(
            of: "\n[ \t]*(?:\n[ \t]*)+", with: "\u{0}", options: .regularExpression
        ).split(separator: "\u{0}", omittingEmptySubsequences: false)
        return pieces.map { trimJS(String($0)) }.filter { !$0.isEmpty }
    }

    public static func join(_ notes: [String]) -> String {
        notes.map(trimJS).filter { !$0.isEmpty }.joined(separator: separator)
    }

    public static func normalize(_ content: String) -> String { join(split(content)) }

    /// JavaScript `String.prototype.trim` semantics (whitespace + line terminators).
    static func trimJS(_ s: String) -> String {
        s.trimmingCharacters(in: jsWhitespace)
    }

    private static let jsWhitespace: CharacterSet = {
        var set = CharacterSet.whitespacesAndNewlines
        set.insert(charactersIn: "\u{FEFF}")
        return set
    }()
}
