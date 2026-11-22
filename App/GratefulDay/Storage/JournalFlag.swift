import Foundation
import SwiftData

/// A one-time app fact that is personal (it implies journal activity), so
/// it lives in the journal store rather than UserDefaults, which is backed
/// up. Example: the reminder offer after the 2nd reflection was shown.
@Model
final class JournalFlag {
    @Attribute(.unique) var name: String
    var setAt: Date

    init(name: String, setAt: Date) {
        self.name = name
        self.setAt = setAt
    }

    static let reminderOfferShown = "reminderOfferShown"
}
