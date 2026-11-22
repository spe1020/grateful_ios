import Foundation

/// Sync copy: Prep's final lines (flows doc, "Final copy for #14's DRAFT
/// keys" and "Zero write relays and surfaced earlier versions").
/// Change only together with that document.
enum SyncCopy {
    static let blockedDay = "We can't open this day's reflection from your account on this iPhone. What you wrote here is kept, but it can't be changed for now."
    /// The day's own view (P22). Tap opens the item in Set aside.
    static let earlierVersionKept = "An earlier version of this reflection is in Set aside."
    static let alsoChangedElsewhere = "This reflection was also changed elsewhere. Both versions are kept on this iPhone."

    /// The Today line for surfaced replaced versions (P22), until tapped or dismissed.
    static func replaced(dates: [String]) -> String {
        if dates.count == 1, let date = dates.first {
            return "Your reflection from \(monthDay(date)) was replaced by a version saved elsewhere. Your earlier text is in Set aside."
        }
        return "\(dates.count) reflections were replaced by versions saved elsewhere. Your earlier text is in Set aside."
    }
    static let dismiss = "Dismiss"

    static let setAsideTitle = "Set aside"
    static let replacedReason = "Replaced by a version saved elsewhere"
    static let copy = "Copy"

    /// Settings → Account while the account's own relay list has no write relay (§1).
    static let noWriteRelays = "Your reflections aren't being saved to your account. Your Nostr account doesn't list anywhere to save them. They're kept on this iPhone. To start saving, add a relay for writing in the app you use to manage your Nostr account."

    /// "November 20" for a YYYY-MM-DD day, in the user's language. Gregorian,
    /// never Calendar.current, so the day isn't shifted by another calendar.
    static func monthDay(_ dateString: String) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return dateString }
        let f = DateFormatter()
        f.calendar = gregorian
        f.timeZone = gregorian.timeZone
        f.setLocalizedDateFormatFromTemplate("MMMMd")
        return f.string(from: date)
    }
}
