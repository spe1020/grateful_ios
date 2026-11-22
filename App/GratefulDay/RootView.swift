import SwiftUI

/// The three top-level places. Standard tab bar, so each is one tap from any
/// other and VoiceOver announces them as tabs.
enum AppTab: Hashable {
    case today, calendar, settings
}

struct RootView: View {
    /// First launch (and every cold launch) lands on Today.
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            CalendarView(selection: $selection)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(AppTab.calendar)
            SettingsPlaceholderView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(GDColor.accent)
    }
}

#Preview("Light") { RootView().environment(JournalStore()).environment(ReminderModel()).environment(AccountModel()) }
#Preview("Dark") { RootView().environment(JournalStore()).environment(ReminderModel()).environment(AccountModel()).preferredColorScheme(.dark) }
