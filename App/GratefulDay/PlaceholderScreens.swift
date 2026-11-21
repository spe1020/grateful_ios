import SwiftUI

/// Calendar placeholder. The month view arrives in M3.
struct CalendarPlaceholderView: View {
    var body: some View {
        NavigationStack {
            PlaceholderBody()
                .navigationTitle("Calendar")
        }
    }
}

/// Settings placeholder. Privacy (M2) and the rest fill this in later.
struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            PlaceholderBody()
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
