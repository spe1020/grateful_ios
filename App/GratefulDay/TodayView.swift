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
    /// The day whose question "Reflect on this" pinned (kept for this session).
    @State private var pinnedDay: String?
    @State private var showingReminder = false

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
                        // VoiceOver order: date, passage, author, question, editor.
                        .accessibilitySortPriority(5)

                    if let editor, editor.showWelcomeBack {
                        Text(TodayEditorModel.welcomeBackMessage)
                            .font(GDFont.body)
                            .foregroundStyle(GDColor.mutedForeground)
                            .accessibilityIdentifier("today.welcomeBack")
                            .accessibilitySortPriority(4)
                    }

                    if let wisdom = DailyWisdom.item(for: day) {
                        WisdomCard(item: wisdom, isPinned: pinnedDay == day.dateString) {
                            pinnedDay = day.dateString
                        }
                        .accessibilitySortPriority(3)
                    }

                    if let wisdom = DailyWisdom.item(for: day), pinnedDay == day.dateString, editor != nil {
                        PinnedQuestion(question: DailyWisdom.prompt(wisdom)) { pinnedDay = nil }
                            .accessibilitySortPriority(2)
                    }

                    if let editor {
                        TodayEditorSection(model: editor)
                            .accessibilitySortPriority(1)
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

                    LocalOnlyFooter()
                }
                .padding(.horizontal, GDSpacing.medium)
                .padding(.vertical, GDSpacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(GDColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
        .onChange(of: store.container.map(ObjectIdentifier.init), initial: true) { _, _ in
            if let container = store.container, editor == nil {
                editor = TodayEditorModel(repository: JournalRepository(context: container.mainContext), day: day)
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

    /// The date in the user's locale, e.g. "Saturday, November 21".
    static func title(for day: DailyEntry.Day) -> String {
        let midnight = Date(timeIntervalSince1970: TimeInterval(day.publishedAt))
        return midnight.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// The writing area, its notes and the delete action.
private struct TodayEditorSection: View {
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
                    Text(JournalUnavailableView.failedMessage)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { model.load() }
                        .accessibilityIdentifier("today.retryRead")
                }
                .accessibilityIdentifier("today.readFailed")
            case .loading:
                ProgressView().accessibilityHidden(true)
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

#Preview("Light") { TodayView().environment(JournalStore()).environment(ReminderModel()) }
#Preview("Dark, largest text") {
    TodayView()
        .environment(JournalStore())
        .environment(ReminderModel())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
