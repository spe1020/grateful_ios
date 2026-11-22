import SwiftUI
import GratefulDayCore

/// Today: the date, room for the day's wisdom (M4) and the writing area,
/// which becomes active in M3.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(JournalStore.self) private var store
    /// The local day, using the same day identity as entries on Nostr
    /// (`DailyEntry.Day`, interop spec §1.8). Re-read when the app becomes
    /// active and when the calendar day changes, so Today never shows
    /// yesterday's date after midnight.
    @State private var day = DailyEntry.Day(containing: .now)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GDSpacing.large) {
                    Text(TodayView.title(for: day))
                        .font(GDFont.dateTitle)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("today.date")
                        // Read first by VoiceOver (criterion 5).
                        .accessibilitySortPriority(2)

                    WisdomPlaceholder()

                    if store.container != nil {
                        WritingAreaPlaceholder()
                            .accessibilitySortPriority(1)
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
            .background(GDColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        // Posted on an arbitrary thread: hop to main before touching @State (Audit L1).
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            refreshDay()
        }
    }

    private func refreshDay() {
        let now = DailyEntry.Day(containing: .now)
        if now != day { day = now }
    }

    /// The date in the user's locale, e.g. "Saturday, November 21".
    static func title(for day: DailyEntry.Day) -> String {
        let midnight = Date(timeIntervalSince1970: TimeInterval(day.publishedAt))
        return midnight.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

/// Space kept for the day's wisdom, which M4 fills in. Purely decorative
/// until then, so VoiceOver skips it.
private struct WisdomPlaceholder: View {
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 96

    var body: some View {
        RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous)
            .fill(GDColor.secondary)
            .frame(maxWidth: .infinity, minHeight: height)
            .accessibilityHidden(true)
    }
}

/// The writing area, shown but not yet active (M3 makes it editable).
private struct WritingAreaPlaceholder: View {
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            Text("Today's reflection")
                .font(GDFont.sectionLabel)
                .foregroundStyle(GDColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous)
                .fill(GDColor.card)
                .overlay(
                    RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous)
                        .strokeBorder(GDColor.border, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, minHeight: height)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today.writingArea")
    }
}

#Preview("Light") { TodayView().environment(JournalStore()) }
#Preview("Dark, largest text") {
    TodayView()
        .environment(JournalStore())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
