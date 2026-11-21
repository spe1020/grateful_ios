import SwiftUI

/// Calendar placeholder. The month view arrives in M3. Until the journal can
/// be read, it says so instead of showing an empty calendar.
struct CalendarPlaceholderView: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.container != nil {
                    PlaceholderBody()
                } else {
                    ScrollView {
                        JournalUnavailableView()
                            .padding(GDSpacing.medium)
                    }
                    .background(GDColor.background.ignoresSafeArea())
                }
            }
            .navigationTitle("Calendar")
        }
    }
}

/// Settings. Privacy holds the pre-account statement.
struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Privacy") { PrivacyView() }
                    .accessibilityIdentifier("settings.privacy")
            }
            .navigationTitle("Settings")
        }
    }
}

/// An intentionally empty, calm screen: just the background.
private struct PlaceholderBody: View {
    var body: some View {
        GDColor.background
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
