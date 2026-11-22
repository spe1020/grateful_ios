import SwiftUI

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
