import SwiftUI
import UIKit
import GratefulDayCore

/// Today: the date, room for the day's wisdom (M4) and the editor, which
/// saves as you type.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(JournalStore.self) private var store
    /// The local day, using the same day identity as entries on Nostr
    /// (`DailyEntry.Day`, interop spec §1.8). Re-read when the app becomes
    /// active and when the calendar day changes.
    @State private var day = JournalDay(containing: .now)
    @State private var editor: TodayEditorModel?
    @Environment(ReminderModel.self) private var reminder
    @Environment(AccountModel.self) private var account
    @Environment(SyncService.self) private var sync
    @State private var showingRestore = false
    @State private var showingOtherAccount = false
    /// The day whose question "Reflect on this" pinned (kept for this session).
    @State private var pinnedDay: String?
    @State private var showingReminder = false
    /// Set aside, filtered to these items (P22); nil when closed.
    @State private var setAside: SetAsideFilter?
    /// Bumped after a dismiss so the plain fetch below is read again.
    @State private var earlierVersionsTick = 0
    /// M6: the conflict screen; the come-back line is hidden for this
    /// launch once dismissed, and returns on the next while choices are open.
    @State private var showingConflicts = false
    @State private var conflictLineDismissed = false
    /// The Today card's page, "YYYY-MM-DD|pageId" (device-local, not synced).
    @AppStorage(TodayCardSelection.defaultsKey) private var storedCardPage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GDSpacing.large) {
                    Text(TodayView.title(for: day.day))
                        .font(GDFont.dateTitle)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("today.date")
                        // VoiceOver order: date, Today card, question, editor.
                        .accessibilitySortPriority(5)

                    if let editor, editor.showWelcomeBack {
                        Text(TodayEditorModel.welcomeBackMessage)
                            .font(GDFont.body)
                            .foregroundStyle(GDColor.mutedForeground)
                            .accessibilityIdentifier("today.welcomeBack")
                            .accessibilitySortPriority(4)
                    }

                    let pages = cardPages
                    if !pages.isEmpty {
                        TodayCard(pages: pages, selection: cardSelection(pageIds: pages.map(\.id)))
                            .accessibilitySortPriority(3)
                    }

                    if let wisdom = DailyWisdom.item(for: day), pinnedDay == day.dateString, editor != nil {
                        PinnedQuestion(question: DailyWisdom.prompt(wisdom)) { pinnedDay = nil }
                            .accessibilitySortPriority(2)
                    }

                    if let context = store.container?.mainContext {
                        let repo = JournalRepository(context: context, activeOwner: account.activeOwner)
                        if account.state == .guest, (try? repo.flag(JournalFlag.restorePending)) == true {
                            Button(AccountCopy.stillLooking) { showingRestore = true }
                                .font(GDFont.sectionLabel)
                                .accessibilityIdentifier("today.stillLooking")
                        }
                        // Quiet lines only, never a modal (Chief P22; Prep's final copy).
                        let _ = earlierVersionsTick
                        if let replaced = try? repo.surfacedEarlierVersions(), !replaced.isEmpty {
                            ReplacedVersionsLine(versions: replaced, onOpen: { setAside = SetAsideFilter(ids: $0) }) { ids in
                                try? repo.dismissEarlierVersions(ids)
                                earlierVersionsTick += 1
                            }
                        }
                        if let owner = account.activeOwner {
                            let review = ConflictReview(context: context, owner: owner)
                            if let kept = try? review.keptBothNotice() {
                                KeptBothLine(kept: kept) {
                                    try? review.clearKeptBothNotice()
                                    earlierVersionsTick += 1
                                }
                            }
                            if !conflictLineDismissed, let open = try? review.load().items, !open.isEmpty {
                                ConflictComeBackLine(dates: open.map(\.dateString), onOpen: { showingConflicts = true }) {
                                    conflictLineDismissed = true
                                }
                            }
                        }
                        if let owner = account.activeOwner,
                           let line = try? ConflictReview(context: context, owner: owner).dayLine(day.dateString, isToday: true),
                           !line.opensScreen {
                            Text(ConflictCopy.dayLine(line))
                                .font(GDFont.sectionLabel)
                                .foregroundStyle(GDColor.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("today.tooLong")
                        } else if let owner = account.activeOwner,
                           let line = try? ConflictReview(context: context, owner: owner).dayLine(day.dateString, isToday: true) {
                            Button { showingConflicts = true } label: {
                                Text(ConflictCopy.dayLine(line))
                                    .font(GDFont.sectionLabel)
                                    .foregroundStyle(GDColor.foreground)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("today.conflict")
                        } else if let kept = try? repo.dayLineSetAsideVersions(day.dateString), !kept.isEmpty {
                            EarlierVersionLine { setAside = SetAsideFilter(ids: Set(kept.map(\.id))) }
                                .accessibilityIdentifier("today.earlierVersion")
                        }
                        if let other = try? repo.otherAccountText(for: day.dateString) {
                            Button(AccountCopy.alsoWroteToday) { showingOtherAccount = true }
                                .font(GDFont.sectionLabel)
                                .accessibilityIdentifier("today.otherAccount")
                                .sheet(isPresented: $showingOtherAccount) {
                                    NavigationStack { OtherAccountEntryView(dateString: day.dateString, text: other) }
                                }
                        }
                    }

                    if let editor {
                        TodayEditorSection(model: editor)
                            .accessibilitySortPriority(1)
                        // Chief P42: a day public on the account says so while it's edited.
                        if store.container.map({ JournalRepository(context: $0.mainContext, activeOwner: account.activeOwner)
                            .showsPublicLabel(day.dateString) }) == true {
                            PublicDayLabel(identifier: "today.public")
                                .accessibilitySortPriority(1)
                        }
                        if editor.showReminderOffer, !reminder.isOn {
                            ReminderOffer(onChoose: {
                                editor.dismissReminderOffer()
                                showingReminder = true
                            }, onDismiss: { editor.dismissReminderOffer() })
                        }
                    } else {
                        // Never an empty Today when the journal can't be read.
                        JournalUnavailableView()
                            .accessibilitySortPriority(1)
                    }

                    // Chief P25: follows today's row. Only an imported day still
                    // matching its relay version drops the label.
                    switch store.container.map({ JournalRepository(context: $0.mainContext, activeOwner: account.activeOwner)
                        .dayMark(day.dateString) }) ?? .localOnly {
                    case .localOnly:
                        LocalOnlyFooter()
                    case .saving:
                        SavingMark(detail: SyncService.savingDetail(
                            sync, text: store.container.flatMap { try? JournalRepository(context: $0.mainContext, activeOwner: account.activeOwner).text(for: day) } ?? "",
                            isToday: true), identifier: "today.saving")
                    case .none:
                        EmptyView()
                    }
                }
                .padding(.horizontal, GDSpacing.medium)
                .padding(.vertical, GDSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            // P59: room below the last line for the floating tab bar, so
            // "On this iPhone only" can be scrolled fully above it.
            .contentMargins(.bottom, GDSpacing.tabBarClearance, for: .scrollContent)
            .background(GDColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $setAside) { filter in
                NavigationStack { SetAsideView(only: filter.ids) }
            }
            .sheet(isPresented: $showingConflicts, onDismiss: {
                earlierVersionsTick += 1
                editor?.reloadIfClean()
            }) {
                if let context = store.container?.mainContext, let owner = account.activeOwner {
                    NavigationStack {
                        ConflictReviewView(review: ConflictReview(context: context, owner: owner)) { showingConflicts = false }
                    }
                }
            }
            .sheet(isPresented: $showingRestore) {
                NavigationStack {
                    RestoreView(onImport: { showingRestore = false }, onDone: { _ in showingRestore = false })
                }
            }
            .sheet(isPresented: $showingReminder) {
                NavigationStack {
                    ReminderView(model: reminder)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingReminder = false }
                            }
                        }
                }
            }
        }
        // Rebuilt when the store is replaced or the connected account changes
        // (P17: the editor writes the active owner's row, otherwise guest).
        .onChange(of: EditorIdentity(container: store.container.map(ObjectIdentifier.init), owner: account.activeOwner),
                  initial: true) { _, identity in
            editor?.flush()
            if let container = store.container {
                editor = TodayEditorModel(repository: JournalRepository(context: container.mainContext,
                                                                        activeOwner: identity.owner), day: day)
            } else {
                editor = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                refreshDay()
                // Retry anything a lock or failure left unsaved.
                editor?.flush()
            default:
                editor?.flush()
            }
        }
        // Leaving Today: save what's typed, then publish it now rather than
        // after the quiet time (Prep §2.2 R2).
        .onDisappear {
            editor?.flush()
            sync.flushPendingSave()
        }
        .onChange(of: sync.status) { _, status in
            if case .done = status { editor?.reloadIfClean() }
        }
        .onReceive(NotificationCenter.default
            .publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
            .receive(on: RunLoop.main)) { _ in
            editor?.flush()
        }
        .onReceive(NotificationCenter.default
            .publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
            .receive(on: RunLoop.main)) { _ in
            editor?.retryIfReadFailed()
            editor?.flush()
        }
        // Posted on an arbitrary thread: hop to main before touching @State.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            refreshDay()
        }
    }

    private func refreshDay() {
        let now = JournalDay(containing: .now)
        guard now != day else { return }
        guard let editor else {
            day = now
            return
        }
        editor.dayChanged(to: now)
        // If saving to the old day failed, the editor stays on it, and so does Today.
        day = editor.day
    }

    /// The Today card's pages, in fixed order: Wisdom, then Affirmation.
    private var cardPages: [TodayCardPage] {
        var pages: [TodayCardPage] = []
        if let wisdom = DailyWisdom.item(for: day) {
            pages.append(TodayCardPage(id: "wisdom", label: TodayCardCopy.wisdomLabel, content: AnyView(
                WisdomCard(item: wisdom, isPinned: pinnedDay == day.dateString) { pinnedDay = day.dateString })))
        }
        if let affirmation = DailyAffirmation.text(for: day) {
            pages.append(TodayCardPage(id: "affirmation", label: TodayCardCopy.affirmationLabel,
                                       content: AnyView(AffirmationPage(text: affirmation))))
        }
        return pages
    }

    private func cardSelection(pageIds: [String]) -> Binding<String?> {
        Binding(
            get: { TodayCardSelection.page(stored: storedCardPage, today: day.dateString, pageIds: pageIds) },
            set: { id in
                guard let id else { return }
                storedCardPage = TodayCardSelection.stored(today: day.dateString, pageId: id)
            })
    }

    /// The date in the user's locale, e.g. "Saturday, November 21".
    static func title(for day: DailyEntry.Day) -> String {
        let midnight = Date(timeIntervalSince1970: TimeInterval(day.publishedAt))
        return midnight.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// The writing area, its notes and the delete action.
private struct TodayEditorSection: View {
    @Environment(JournalStore.self) private var store
    @Bindable var model: TodayEditorModel
    @State private var confirmingDelete = false
    @FocusState private var editorFocused: Bool
    @State private var deleteFailed = false
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 180

    static let placeholder = "What are you grateful for today?"
    static let deleteTitle = "Delete this reflection? This can't be undone."

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            switch model.loadState {
            case .readFailed:
                VStack(alignment: .leading, spacing: GDSpacing.small) {
                    Text(JournalUnavailableView.failedText(removalIncomplete: store.removalIncomplete))
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { model.load() }
                        .accessibilityIdentifier("today.retryRead")
                }
                .accessibilityIdentifier("today.readFailed")
            case .loading:
                ProgressView().accessibilityHidden(true)
            case .blocked:
                VStack(alignment: .leading, spacing: GDSpacing.small) {
                    Text(SyncCopy.blockedDay)
                        .font(GDFont.sectionLabel)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("today.blocked")
                    ForEach(Array(EntryNotes.split(model.text).enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(GDFont.body)
                            .foregroundStyle(GDColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .ready:
                editor
            }
        }
    }

    private var editor: some View {
        // Read so a refused edit redraws the editor from the kept text.
        let _ = model.refusedEdits
        return VStack(alignment: .leading, spacing: GDSpacing.small) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { model.text },
                    set: { model.edit($0) }
                ))
                .font(GDFont.body)
                .foregroundStyle(GDColor.foreground)
                .scrollContentBackground(.hidden)
                .padding(GDSpacing.small)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .focused($editorFocused)
                .accessibilityLabel("Today's reflection")
                .accessibilityIdentifier("today.editor")
                .toolbar {
                    // The keyboard covers the tab bar; this puts it away
                    // (typing is already saved as you go).
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { editorFocused = false }
                            .accessibilityIdentifier("today.keyboardDone")
                    }
                }

                if model.text.isEmpty {
                    Text(Self.placeholder)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.mutedForeground)
                        .padding(.horizontal, GDSpacing.small + 5)
                        .padding(.vertical, GDSpacing.small + 8)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("today.placeholder")
                }
            }
            .background(
                RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous)
                    .fill(GDColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous)
                    .strokeBorder(GDColor.border, lineWidth: 1)
            )

            if let error = model.saveError {
                Text(error)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.saveError")
            }
            if let milestone = model.milestoneMessage {
                Text(milestone)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.milestone")
            }
            if model.isNearlyFull {
                Text(TodayEditorModel.nearlyFullMessage)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.nearlyFull")
            }
            if model.hasReflection {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete reflection", systemImage: "trash")
                        .font(GDFont.sectionLabel)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("today.delete")
            }
        }
        .confirmationDialog(Self.deleteTitle, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                do { try model.deleteReflection() } catch { deleteFailed = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't delete just now. Your reflection is still here.", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        }
    }
}

#Preview("Light") { TodayView().environment(JournalStore()).environment(ReminderModel()).environment(AccountModel()).environment(SyncService()) }
#Preview("Dark, largest text") {
    TodayView()
        .environment(JournalStore())
        .environment(ReminderModel())
        .environment(AccountModel()).environment(SyncService())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

/// What the editor depends on: the store and the connected account.
struct EditorIdentity: Equatable {
    let container: ObjectIdentifier?
    let owner: String?
}

/// Another account's reflection, read-only, with its label (Prep, "Days
/// from another account"). No edit or delete controls.
struct OtherAccountEntryView: View {
    let dateString: String
    let text: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Label(AccountCopy.fromAnotherAccount, systemImage: "person.crop.circle.badge.questionmark")
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .accessibilityIdentifier("otherAccount.label")
                Text(AccountCopy.fromAnotherAccountExplain)
                    .font(.caption)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(EntryNotes.split(text).enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(GDSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GDColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
