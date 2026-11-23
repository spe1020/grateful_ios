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

/// The M6 conflict screen: Prep's final copy (flows doc, "M6 conflict
/// screen"). Growth may tune wording only if every fact stays. Change only
/// together with that document.
enum ConflictCopy {
    /// §7 or §9 when every row is that case; otherwise §1, or §6 when every
    /// row came from the re-check after saving.
    static func heading(dates: [String], afterSaving: Bool, allKind: ConflictReview.Kind?) -> String {
        let one = dates.count == 1 ? dates.first.map(SyncCopy.monthDay) : nil
        switch allKind {
        case .deletedFromAccount?:
            if let one { return "\(one) was deleted from your account, but you changed it on this iPhone." }
            return "\(dates.count) days were deleted from your account, but you changed them on this iPhone."
        case .deletedHere?:
            if let one { return "You deleted \(one) here, but it was changed in your account." }
            return "You deleted \(dates.count) days here, but they were changed in your account."
        default:
            return heading(dates: dates, afterSaving: afterSaving)
        }
    }

    /// §1, or §6 when every row came from the re-check after saving.
    static func heading(dates: [String], afterSaving: Bool) -> String {
        if dates.count == 1, let date = dates.first {
            return afterSaving
                ? "Your reflection for \(SyncCopy.monthDay(date)) was also changed elsewhere."
                : "You wrote on \(SyncCopy.monthDay(date)) in both places."
        }
        return afterSaving ? "\(dates.count) reflections were also changed elsewhere." : "You wrote on \(dates.count) days in both places."
    }
    static let subheading = "Choose what to keep for each day. Any text you don't keep goes to Set aside on this iPhone."

    static let yourAccount = "Your account"
    static let thisIPhone = "This iPhone"
    static let showAll = "Show all"

    static let keepBoth = "Keep both"
    static let keepThisIPhone = "Keep this iPhone's"
    static let keepAccount = "Keep your account's"
    static let keepBothLine = "Both texts stay on this day as separate notes, your account's first."
    static let keepThisIPhoneLine = "Your account's text goes to Set aside."
    static let keepAccountLine = "This iPhone's text goes to Set aside."
    static let privateWins = "This day will be private, because one of the texts was private."

    static let done = "Done"
    static let notNow = "Not now"
    static let keepBothForAll = "Keep both for all"

    /// Set aside reason for a text that wasn't kept.
    static let notKeptReason = "You kept the other version of this day."

    /// §7: deleted from the account, changed on this iPhone.
    static let deletedFromAccount = "This day was deleted from your account."
    static let letItStayDeleted = "Let it stay deleted"
    static let keepThisIPhoneRestoresLine = "This day goes back to your account with what you wrote here."
    static let letItStayDeletedLine = "What you wrote here goes to Set aside, and this day is removed from this iPhone."
    static let deletedFromAccountDayLine = "This day was deleted from your account. What you wrote here is kept on this iPhone."

    /// §9: deleted on this iPhone, changed in the account.
    static let deletedHere = "You deleted this day here."
    static let deleteEverywhere = "Delete it everywhere"
    static let keepAccountRestoresLine = "This day comes back on this iPhone with your account's text."
    static let deleteEverywhereLine = "Your account's text goes to Set aside on this iPhone, and this day is deleted from your account."
    static let deletedHereDayLine = "You deleted this day here, but it was changed in your account. Choose what to keep."

    /// §8: Keep both would be too long to save to the account.
    static let keepBothTooLong = "Together these are too long to save to your account. If you keep both, this day stays on this iPhone only. To save it to your account, keep one instead."
    static let tooLongPastDay = "This reflection is too long to save to your account. It's kept on this iPhone only."
    static let tooLongToday = "This reflection is too long to save to your account. It's kept on this iPhone. Shorten it to save it."

    /// The day view's line for a day (§5–§9, "Coming back later").
    static func dayLine(_ line: ConflictReview.DayLine) -> String {
        switch line {
        case .alsoChangedElsewhere: return SyncCopy.alsoChangedElsewhere
        case .deletedFromAccount: return deletedFromAccountDayLine
        case .deletedHere: return deletedHereDayLine
        case .tooLong(let isToday): return isToday ? tooLongToday : tooLongPastDay
        }
    }

    /// The reason under a Set aside item.
    static func setAsideReason(_ reason: EarlierVersionReason) -> String {
        switch reason {
        case .notKept: return notKeptReason
        case .deletedFromAccount: return deletedFromAccount
        case .deletedHere: return deletedHere
        default: return SyncCopy.replacedReason
        }
    }

    /// Today line after Keep both for all, until dismissed.
    static func keptBoth(dates: [String], madePrivate: Bool) -> String {
        let first = dates.count == 1 && dates.first != nil
            ? "Kept both versions on \(SyncCopy.monthDay(dates[0]))."
            : "Kept both versions on \(dates.count) days."
        return madePrivate ? first + " Days where either version was private are now private." : first
    }

    /// §5.
    static let cantCompareHeading = "Can't compare these yet"
    static let cantOpenAccount = "We can't open this day's reflection from your account on this iPhone."
    static let cantCompareLine = "What you wrote here is kept on this iPhone. It won't replace the reflection in your account."

    /// Today line while any choice is open, until tapped or dismissed.
    static func comeBack(dates: [String]) -> String {
        if dates.count == 1, let date = dates.first {
            return "Your reflection from \(SyncCopy.monthDay(date)) was also changed elsewhere. Choose what to keep."
        }
        return "\(dates.count) reflections were also changed elsewhere. Choose what to keep."
    }
}
