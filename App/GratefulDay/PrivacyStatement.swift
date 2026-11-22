import SwiftUI

/// Approved copy (MVP doc, "Local drafts are not backed up", Prep 2026-11-21;
/// Chief P3). Change only together with those documents.
enum PrivacyCopy {
    static let preAccountStatement = "Until you connect an account, nothing you write is published. Your reflections are saved only on this iPhone and aren't included in iCloud or iPhone backups. If you lose or replace this iPhone, or delete the app, they can't be recovered."
    /// Shown instead of `preAccountStatement` while the backup exclusion is
    /// not in effect on this device (Chief P10). DRAFT from the facts Chief
    /// listed; Prep owns the final wording.
    /// While the backup exclusion has failed on this iPhone (Chief P10).
    /// Prep's final copy (scope doc, "Alternate pre-account statement").
    static let backupExclusionFailedStatement = "Until you connect an account, nothing you write is published. Your reflections are saved on this iPhone. We weren't able to keep them out of iCloud and iPhone backups on this iPhone, so they may be included in one. We'll keep trying each time you open the app. If you lose or replace this iPhone, or delete the app, they may not be recoverable."
    /// Before the first exclusion check of this launch (Chief P11): makes no
    /// claim either way. Prep's final copy ("Final journal copy", item 2).
    static let neutralStatement = "Until you connect an account, nothing you write is published. Your reflections are saved only on this iPhone. If you lose or replace this iPhone, or delete the app, they may not be recoverable."

    /// The statement that is true on this device right now: the backup
    /// claim only once exclusion is confirmed in effect (P10, P11).
    static func statement(exclusionChecked: Bool, exclusionFailed: Bool) -> String {
        if exclusionFailed { return backupExclusionFailedStatement }
        return exclusionChecked ? preAccountStatement : neutralStatement
    }

    /// The local status label for an entry (Chief P3). No synced state until M5.
    static let localOnlyLabel = "On this iPhone only"
}

/// Settings → Privacy.
struct PrivacyView: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        ScrollView {
            // Never claims backup exclusion while it isn't in effect (P10).
            Text(PrivacyCopy.statement(exclusionChecked: store.backupExclusionConfirmed,
                                       exclusionFailed: store.backupExclusionFailed))
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
    /// Prep (M2 copy review): says what happened to the data.
    static let failedMessage = "Your journal couldn't be opened just now. Nothing has been deleted."

    /// What a failed open says. After an unfinished "Remove account and
    /// local data" some files may already be gone, so it uses Prep's F8
    /// failure copy instead and never claims nothing was deleted.
    static func failedText(removalIncomplete: Bool) -> String {
        removalIncomplete ? AccountCopy.removeKeyOnly : failedMessage
    }
    /// Added after a "Try again" that fails again.
    static let repeatedFailureMessage = "If this keeps happening, try restarting your iPhone."

    @State private var failedRetries = 0

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            if case .failed = store.state {
                let _ = store.removalIncompleteVersion
                Text(Self.failedText(removalIncomplete: store.removalIncomplete))
                    .accessibilityIdentifier("journal.failedText")
                    .font(GDFont.body)
                    .foregroundStyle(GDColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if failedRetries > 0 {
                    Text(Self.repeatedFailureMessage)
                        .font(GDFont.body)
                        .foregroundStyle(GDColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("journal.repeatedFailure")
                }
                Button("Try again") {
                    if store.removalIncomplete {
                        // Finish the removal the person already confirmed.
                        _ = store.removeAllData()
                    } else {
                        store.openIfPossible(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
                    }
                    if case .failed = store.state { failedRetries += 1 }
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
