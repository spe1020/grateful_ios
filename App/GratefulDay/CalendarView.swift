import SwiftUI
import GratefulDayCore

/// Calendar: the month, with days that have a reflection marked (dot plus
/// bold number, never colour alone). Past days open read-only; future days
/// are disabled; today goes to the Today tab.
struct CalendarView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selection: AppTab
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
                    DayDetailView(dateString: dateString, repository: JournalRepository(context: container.mainContext))
                }
            }
        }
        .onChange(of: store.container.map(ObjectIdentifier.init), initial: true) { _, _ in
            if let container = store.container, model == nil {
                model = CalendarModel(repository: JournalRepository(context: container.mainContext))
            }
        }
        // Today's edits and day changes show up when the tab is opened again.
        .onChange(of: selection) { _, tab in if tab == .calendar { model?.load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model?.load() } }
    }
}

private struct CalendarContent: View {
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
                    Text(JournalUnavailableView.failedMessage)
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
            Circle()
                .fill(day.hasReflection ? GDColor.accent : Color.clear)
                .frame(width: 6, height: 6)
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
        if day.isFuture { parts.append("Unavailable") }
        return parts.joined(separator: ", ")
    }
}

/// A past day's reflection, read-only (web `isPast`): no edit control.
struct DayDetailView: View {
    let dateString: String
    let repository: JournalRepository
    @State private var notes: [String]?
    @State private var failed = false

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
                    Text(JournalUnavailableView.failedMessage)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                    Button("Try again") { load() }
                } else if let notes {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(GDFont.body)
                            .foregroundStyle(GDColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .accessibilityIdentifier("day.notes")
                    Label(PrivacyCopy.localOnlyLabel, systemImage: "iphone")
                        .font(GDFont.sectionLabel)
                        .foregroundStyle(GDColor.mutedForeground)
                }
            }
            .padding(GDSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GDColor.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func load() {
        guard let day = TodayEditorModel.parse(dateString, timeZone: .current) else { return }
        do {
            notes = EntryNotes.split(try repository.text(for: day))
            failed = false
        } catch {
            failed = true
            StorageLog.error("Reading a past day failed", error: error)
        }
    }
}
