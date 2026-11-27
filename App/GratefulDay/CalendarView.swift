import SwiftUI
import GratefulDayCore

/// Calendar: the month, with days that have a reflection marked (dot plus
/// bold number, never colour alone). Past days open read-only; future days
/// are disabled; today goes to the Today tab.
struct CalendarView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: AppTab
    @Environment(AccountModel.self) private var account
    @Environment(SyncService.self) private var sync
    @State private var model: CalendarModel?

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if let model {
                        CalendarContent(model: model, selection: $selection)
                    } else {
                        // Never an empty calendar when the journal can't be read.
                        JournalUnavailableView()
                    }
                }
                .padding(GDSpacing.medium)
            }
            .background(GDColor.background.ignoresSafeArea())
            .navigationTitle("Calendar")
            .navigationDestination(for: String.self) { dateString in
                if let container = store.container {
                    DayDetailView(dateString: dateString,
                                  repository: JournalRepository(context: container.mainContext, activeOwner: account.activeOwner))
                }
            }
        }
        .onChange(of: EditorIdentity(container: store.container.map(ObjectIdentifier.init), owner: account.activeOwner),
                  initial: true) { _, identity in
            if let container = store.container {
                model = CalendarModel(repository: JournalRepository(context: container.mainContext, activeOwner: identity.owner))
            } else {
                model = nil
            }
        }
        // Today's edits and day changes show up when the tab is opened again.
        .onChange(of: selection) { _, tab in if tab == .calendar { model?.load() } }
        .onChange(of: sync.status) { _, status in if case .done = status { model?.load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model?.load() } }
    }
}

private struct CalendarContent: View {
    @Environment(JournalStore.self) private var store
    @Bindable var model: CalendarModel

    @Binding var selection: AppTab
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.medium) {
            HStack {
                Button { model.showPreviousMonth() } label: {
                    Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Previous month")
                .accessibilityIdentifier("calendar.previous")
                Spacer()
                Text(model.monthTitle)
                    .font(GDFont.sectionLabel)
                    .foregroundStyle(GDColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("calendar.month")
                Spacer()
                Button { model.showNextMonth() } label: {
                    Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!model.canShowNextMonth)
                .accessibilityLabel("Next month")
                .accessibilityIdentifier("calendar.next")
            }

            switch model.loadState {
            case .readFailed:
                VStack(alignment: .leading, spacing: GDSpacing.small) {
                    Text(JournalUnavailableView.failedText(removalIncomplete: store.removalIncomplete))
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { model.load() }
                        .accessibilityIdentifier("calendar.retry")
                }
                .accessibilityIdentifier("calendar.readFailed")
            case .loading:
                ProgressView().accessibilityHidden(true)
            case .ready:
                VStack(alignment: .leading, spacing: GDSpacing.small) {
                    Text(CalendarModel.monthCountText(model.monthCount))
                        .accessibilityIdentifier("calendar.monthCount")
                    Text(CalendarModel.totalCountText(model.totalCount))
                        .accessibilityIdentifier("calendar.totalCount")
                    if model.otherAccountReflectionCount > 0 {
                        Text(AccountCopy.otherAccountKept(model.otherAccountReflectionCount))
                            .accessibilityIdentifier("calendar.otherAccountKept")
                    }
                }
                .font(GDFont.body)
                // Body colour: muted text fails contrast at the largest sizes.
                .foregroundStyle(GDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: columns, spacing: 4) {
                    // Weekday headings in the user's locale and first weekday.
                    // Hidden from VoiceOver: each day's label names its weekday.
                    ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(GDFont.sectionLabel)
                            .foregroundStyle(GDColor.foreground)
                            .accessibilityHidden(true)
                    }
                    ForEach(Array(model.grid.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(day: day, selection: $selection)
                        } else {
                            Color.clear.frame(minHeight: 44).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: CalendarDay
    @Binding var selection: AppTab

    var body: some View {
        // The label and identifier go on the control itself, so VoiceOver
        // hears "dimmed" on a disabled future day and "button" on the rest.
        if day.isFuture {
            Button {} label: { content.opacity(0.35) }
                .buttonStyle(.plain)
                .disabled(true)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
        } else if day.isToday {
            Button { selection = .today } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
        } else if day.hasReflection {
            NavigationLink(value: day.dateString) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(identifier)
        }
    }

    private var identifier: String { "calendar.day.\(day.dateString)" }

    private var content: some View {
        VStack(spacing: 2) {
            Text("\(day.dayNumber)")
                .font(day.hasReflection ? GDFont.body.weight(.bold) : GDFont.body)
                .foregroundStyle(GDColor.foreground)
            ZStack {
                Circle()
                    .fill(day.hasReflection ? GDColor.accent : Color.clear)
                // Another account's day: an outlined dot, not colour alone.
                if day.otherAccountOnly {
                    Circle().strokeBorder(GDColor.foreground, lineWidth: 1)
                }
            }
            .frame(width: 6, height: 6)
        }
        .overlay(alignment: .topTrailing) {
            // The Saving mark: a symbol, not colour alone.
            if day.saving {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(GDColor.mutedForeground)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GDColor.accent, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if let date = TodayEditorModel.parse(day.dateString, timeZone: .current) {
            parts.append(date.start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        }
        if day.isToday { parts.append("Today") }
        if day.hasReflection { parts.append("Reflection written") }
        if day.saving { parts.append(SyncCopy.savingVoiceOver) }
        if day.otherAccountOnly { parts.append("Reflection from another account") }
        if day.isFuture { parts.append("Unavailable") }
        return parts.joined(separator: ", ")
    }
}

/// A past day's reflection, read-only (web `isPast`): no edit control.
struct DayDetailView: View {
    @Environment(JournalStore.self) private var store
    @Environment(SyncService.self) private var sync
    let dateString: String
    let repository: JournalRepository
    @State private var notes: [String]?
    @State private var otherText: String?
    @State private var failed = false
    /// This day's versions in Set aside (P22).
    @State private var earlierIds: Set<UUID> = []
    @State private var blocked = false
    @State private var setAside: SetAsideFilter?
    /// M6: the day has a choice to make (opens the conflict screen).
    @State private var dayLine: ConflictReview.DayLine?
    @State private var showingConflicts = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                if let day = TodayEditorModel.parse(dateString, timeZone: .current) {
                    Text(TodayView.title(for: day.day))
                        .font(GDFont.dateTitle)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if failed {
                    Text(JournalUnavailableView.failedText(removalIncomplete: store.removalIncomplete))
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                    Button("Try again") { load() }
                } else if let notes {
                    if blocked {
                        Text(SyncCopy.blockedDay)
                            .font(GDFont.sectionLabel)
                            .foregroundStyle(GDColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("day.blocked")
                    }
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(GDFont.body)
                            .foregroundStyle(GDColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("day.notes")
                    // Chief P42: a day public on the account says so wherever it's shown.
                    if !notes.isEmpty, repository.showsPublicLabel(dateString) {
                        PublicDayLabel(identifier: "day.public")
                    }
                    if let dayLine, !dayLine.opensScreen {
                        Text(ConflictCopy.dayLine(dayLine))
                            .font(GDFont.sectionLabel)
                            .foregroundStyle(GDColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("day.tooLong")
                    } else if let dayLine {
                        Button { showingConflicts = true } label: {
                            Text(ConflictCopy.dayLine(dayLine))
                                .font(GDFont.sectionLabel)
                                .foregroundStyle(GDColor.foreground)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("day.conflict")
                    } else if !earlierIds.isEmpty {
                        EarlierVersionLine { setAside = SetAsideFilter(ids: earlierIds) }
                            .accessibilityIdentifier("day.earlierVersion")
                    }
                    // Chief P25: only an imported day still matching its relay
                    // version drops "On this iPhone only".
                    if !notes.isEmpty {
                        switch repository.dayMark(dateString) {
                        case .localOnly:
                            Label(PrivacyCopy.localOnlyLabel, systemImage: "iphone")
                                .font(GDFont.sectionLabel)
                                .foregroundStyle(GDColor.mutedForeground)
                        case .saving:
                            SavingMark(detail: SyncService.savingDetail(sync, text: EntryNotes.join(notes)),
                                       identifier: "day.saving")
                        case .none:
                            EmptyView()
                        }
                    }
                    if let otherText {
                        if notes.isEmpty {
                            OtherAccountEntryView(dateString: dateString, text: otherText)
                        } else {
                            DisclosureGroup(AccountCopy.fromAnotherAccount) {
                                OtherAccountEntryView(dateString: dateString, text: otherText)
                            }
                            .accessibilityIdentifier("day.otherAccountSection")
                        }
                    }
                }
            }
            .padding(GDSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GDColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(item: $setAside) { filter in
            NavigationStack { SetAsideView(only: filter.ids) }
        }
        .sheet(isPresented: $showingConflicts, onDismiss: load) {
            if let owner = repository.activeOwner {
                NavigationStack {
                    ConflictReviewView(review: ConflictReview(context: repository.context, owner: owner)) { showingConflicts = false }
                }
            }
        }
    }

    private func load() {
        guard let day = TodayEditorModel.parse(dateString, timeZone: .current) else { return }
        do {
            notes = EntryNotes.split(try repository.text(for: day))
            otherText = try repository.otherAccountText(for: dateString)
            blocked = try repository.isBlocked(dateString)
            if let owner = repository.activeOwner {
                let days = try ConflictReview(context: repository.context, owner: owner).load()
                let today = JournalDay(containing: .now).day.dateString
                dayLine = try ConflictReview(context: repository.context, owner: owner)
                    .dayLine(dateString, isToday: today == dateString)
                // §5: a blocked day with pending edits shows the blocked line too.
                if days.blocked.contains(where: { $0.dateString == dateString }) { blocked = true }
            }
            earlierIds = Set(try repository.dayLineSetAsideVersions(dateString).map(\.id))
            failed = false
        } catch {
            failed = true
            StorageLog.error("Reading a past day failed", error: error)
        }
    }
}
