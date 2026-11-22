import Foundation
import SwiftData

/// A reflection-total milestone the user has already been shown. Kept in
/// the journal store, not UserDefaults: counts are personal and UserDefaults
/// is backed up (storage recommendation §2).
@Model
final class AcknowledgedMilestone {
    @Attribute(.unique) var total: Int
    var acknowledgedAt: Date

    init(total: Int, acknowledgedAt: Date) {
        self.total = total
        self.acknowledgedAt = acknowledgedAt
    }
}
