import Foundation
import Observation

/// Holds what the user typed until it's saved. A failed save never clears or
/// replaces the text: it stays here and the user is told.
@MainActor
@Observable
final class DraftBuffer {
    static let saveFailedMessage = "Couldn't save just now. Your text is still here."

    var text: String
    private(set) var saveError: String?
    private let saver: (String) throws -> Void

    init(text: String = "", saver: @escaping (String) throws -> Void) {
        self.text = text
        self.saver = saver
    }

    /// Try to save the current text. Returns whether it was saved.
    @discardableResult
    func commit() -> Bool {
        do {
            try saver(text)
            saveError = nil
            return true
        } catch {
            saveError = Self.saveFailedMessage
            return false
        }
    }
}
