import Foundation
import Observation
import GratefulDayCore

/// The state behind Today's editor: which day it writes to, what has been
/// typed, and saving.
///
/// - **Saves as you type.** Each change is saved after `saveDelay` (0.5 s)
///   without further typing, and immediately when the app leaves the
///   foreground, the device is about to lock, or the day changes. So at most
///   the last 0.5 s of typing is unsaved if the app is killed.
/// - **A failed save never loses text** (M2 #5, Audit M2 I1): `DraftBuffer`
///   keeps it and shows the message; the next change, foregrounding or unlock
///   retries.
/// - **A failed read is never an empty day:** the editor shows `.readFailed`
///   with a retry and accepts no typing, so nothing can overwrite the entry.
/// - **Midnight:** the text stays with the day it was started on; it's saved
///   to that day before Today moves to the new date.
@MainActor
@Observable
final class TodayEditorModel {
    enum LoadState: Equatable { case loading, ready, readFailed, blocked }

    static let saveDelay: Duration = .milliseconds(500)
    /// NIP-44 v2's plaintext cap, applied to every entry (`DailyEntry`).
    static let maxBytes = DailyEntry.maxContentBytes
    /// From here on, the calm "nearly full" note shows.
    static let nearlyFullBytes = 60_000
    static let nearlyFullMessage = "This day's reflection is nearly full."
    static let welcomeBackMessage = "Welcome back."
    /// Days since the last reflection at which "Welcome back." shows: two or
    /// more whole days without one in between.
    static let welcomeBackGap = 3

    private(set) var day: JournalDay
    private(set) var loadState: LoadState = .loading
    private(set) var showWelcomeBack = false
    private(set) var draft: DraftBuffer!
    private(set) var hasUnsavedChanges = false
    /// A milestone reached by this session's saves, shown once (criterion 7).
    private(set) var milestoneMessage: String?
    /// The one-time reminder offer, after the 2nd saved reflection (M4).
    private(set) var showReminderOffer = false
    /// Bumped when an edit is refused at the cap; the editor view reads it.
    private(set) var refusedEdits = 0

    private let repository: JournalRepository
    private let now: () -> Date
    private var pendingSave: Task<Void, Never>?

    /// `save` replaces the repository write; tests use it to inject failures.
    init(repository: JournalRepository, day: JournalDay, now: @escaping () -> Date = { .now },
         save: ((String, JournalDay) throws -> Void)? = nil) {
        self.repository = repository
        self.day = day
        self.now = now
        self.draft = DraftBuffer { [unowned self] text in
            if let save {
                try save(text, self.day)
            } else {
                try self.repository.save(text: text, for: self.day, now: self.now())
            }
        }
        load()
    }

    var text: String { draft.text }
    var saveError: String? { draft.saveError }
    var isEditable: Bool { loadState == .ready }
    var hasReflection: Bool { !EntryNotes.normalize(draft.text).isEmpty }
    var byteCount: Int { EntryNotes.normalize(draft.text).utf8.count }
    var isNearlyFull: Bool { byteCount >= Self.nearlyFullBytes }

    /// (Re)read the day's entry. On failure, nothing is shown as empty and
    /// typing is disabled until a retry succeeds.
    func load() {
        do {
            if try repository.isBlocked(day.dateString) {
                // The relay version can't be read: show this iPhone's copy,
                // read-only, never empty and never written over (interop §0).
                draft.text = try repository.entry(for: day.dateString)?.notesText ?? ""
                hasUnsavedChanges = false
                loadState = .blocked
                return
            }
            draft.text = try repository.text(for: day)
            hasUnsavedChanges = false
            let previous = try repository.latestReflectionDate(before: day.dateString)
            showWelcomeBack = draft.text.isEmpty && Self.isWelcomeBack(lastReflection: previous, today: day)
            loadState = .ready
        } catch let error {
            loadState = .readFailed
            StorageLog.error("Reading today's entry failed", error: error)
        }
    }

    /// Apply an edit from the text field. Returns false when the edit is
    /// refused because it would pass the length cap; the text is then left
    /// as it was (nothing typed is cut on save).
    @discardableResult
    func edit(_ newText: String) -> Bool {
        guard isEditable else { return false }
        guard newText != draft.text else { return true }
        guard EntryNotes.normalize(newText).utf8.count <= Self.maxBytes else {
            // Make the editor redraw from the kept text, so it drops the
            // refused characters instead of showing text that won't be saved
            // (Audit M3a L2). Re-assigning the same text wouldn't notify:
            // Observation skips equal values.
            refusedEdits += 1
            return false
        }
        draft.text = newText
        hasUnsavedChanges = true
        scheduleSave()
        return true
    }

    /// Save now (leaving the foreground, locking, midnight). Returns whether
    /// everything typed is on disk.
    @discardableResult
    func flush() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard hasUnsavedChanges, isEditable else { return !hasUnsavedChanges }
        if draft.commit() {
            hasUnsavedChanges = false
            checkMilestone()
            checkReminderOffer()
            return true
        }
        return false
    }

    /// Today has moved to `newDay` (midnight, or returning after days away).
    /// The current text is saved to the day it was written on first. If that
    /// save fails, the editor stays on the old day, so the text is never
    /// attached to the wrong date or dropped.
    func dayChanged(to newDay: JournalDay) {
        guard newDay != day else { return }
        guard flush() else { return }
        day = newDay
        loadState = .loading
        milestoneMessage = nil
        load()
    }

    /// After a relay read imported changes: reload unless the person has
    /// unsaved typing (which always wins locally; M5b-2 handles the rest).
    func reloadIfClean() {
        guard !hasUnsavedChanges else { return }
        load()
    }

    /// After a phone unlock: if the read had failed (for example the day
    /// changed while the files were protected), read again (Audit M3a L1).
    func retryIfReadFailed() {
        if loadState == .readFailed { load() }
    }

    func dismissReminderOffer() { showReminderOffer = false }

    /// Offer the reminder once, when the total first reaches 2. The "shown"
    /// flag is recorded in the journal store when the offer appears.
    private func checkReminderOffer() {
        guard hasReflection,
              let total = try? repository.totalReflectionCount(), total >= 2,
              let shown = try? repository.flag(JournalFlag.reminderOfferShown), !shown
        else { return }
        // Show it only once the "shown" fact is saved, so a failed save can't
        // make it appear again later (Audit M4 L2).
        do {
            try repository.setFlag(JournalFlag.reminderOfferShown, now: now())
        } catch {
            StorageLog.error("Recording the reminder offer failed", error: error)
            return
        }
        showReminderOffer = true
    }

    private func checkMilestone() {
        guard hasReflection, let reached = try? repository.takeMilestone(now: now()) else { return }
        milestoneMessage = Self.milestoneText(reached)
    }

    /// DRAFT copy for Prep/Growth: quiet, one line, totals only.
    static func milestoneText(_ total: Int) -> String {
        total == 1 ? "Your first reflection." : "That's \(total) reflections."
    }

    /// Delete the day's reflection (after the user confirmed).
    func deleteReflection() throws {
        pendingSave?.cancel()
        pendingSave = nil
        try repository.delete(day, now: now())
        draft.text = ""
        hasUnsavedChanges = false
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    static func isWelcomeBack(lastReflection: String?, today: JournalDay) -> Bool {
        guard let lastReflection, let last = parse(lastReflection, timeZone: today.timeZone) else { return false }
        return last.days(until: today) >= welcomeBackGap
    }

    /// A `YYYY-MM-DD` date as a `JournalDay` in `timeZone`.
    static func parse(_ dateString: String, timeZone: TimeZone) -> JournalDay? {
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return nil }
        return JournalDay(containing: date, timeZone: timeZone)
    }
}
