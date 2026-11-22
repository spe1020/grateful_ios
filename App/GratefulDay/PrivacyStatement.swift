import SwiftUI

/// Approved copy (MVP doc, "Local drafts are not backed up", Prep 2026-11-21;
/// Chief P3). Change only together with those documents.
enum PrivacyCopy {
    static let preAccountStatement = "Until you connect an account, nothing you write is published. Your reflections are saved only on this iPhone and aren't included in iCloud or iPhone backups. If you lose or replace this iPhone, or delete the app, they can't be recovered."
    /// The local status label for an entry (Chief P3). No synced state until M5.
    static let localOnlyLabel = "On this iPhone only"
}

/// Settings → Privacy.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            Text(PrivacyCopy.preAccountStatement)
                .font(GDFont.body)
                .foregroundStyle(GDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(GDSpacing.medium)
                .accessibilityIdentifier("privacy.statement")
        }
        .background(GDColor.background.ignoresSafeArea())
        .navigationTitle("Privacy")
    }
}

/// Today's footer: the local status, one tap from the full statement.
struct LocalOnlyFooter: View {
    @State private var showingStatement = false

    var body: some View {
        Button {
            showingStatement = true
        } label: {
            Label(PrivacyCopy.localOnlyLabel, systemImage: "iphone")
                .font(GDFont.sectionLabel)
                .foregroundStyle(GDColor.mutedForeground)
        }
        .accessibilityIdentifier("today.localOnly")
        .sheet(isPresented: $showingStatement) {
            NavigationStack {
                PrivacyView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingStatement = false }
                        }
                    }
            }
        }
    }
}

/// Shown instead of journal content whenever the store isn't open. Never an
/// empty journal.
struct JournalUnavailableView: View {
    @Environment(JournalStore.self) private var store

    static let lockedMessage = "Unlock your iPhone to open your journal."
    static let failedMessage = "Your journal couldn't be opened just now."

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            if case .failed = store.state {
                Text(Self.failedMessage)
                    .font(GDFont.body)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    store.openIfPossible(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
                }
                .accessibilityIdentifier("journal.retry")
            } else {
                Label(Self.lockedMessage, systemImage: "lock")
                    .font(GDFont.body)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("journal.unavailable")
    }
}
