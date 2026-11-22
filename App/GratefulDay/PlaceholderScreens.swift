import SwiftUI

/// Settings. Privacy holds the pre-account statement.
struct SettingsPlaceholderView: View {
    @Environment(ReminderModel.self) private var reminder

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Account") { AccountView() }
                    .accessibilityIdentifier("settings.account")
                NavigationLink("Privacy") { PrivacyView() }
                    .accessibilityIdentifier("settings.privacy")
                NavigationLink {
                    ReminderView(model: reminder)
                } label: {
                    LabeledContent("Daily reminder", value: reminder.isOn
                        ? reminder.time.formatted(date: .omitted, time: .shortened) : "Off")
                }
                .accessibilityIdentifier("settings.reminder")
            }
            .navigationTitle("Settings")
        }
    }
}
