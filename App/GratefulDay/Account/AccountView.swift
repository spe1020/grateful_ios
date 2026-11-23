import SwiftUI
import UIKit
import NostrCore

/// Whether one of the Account sheets (restore, import, backup offer, sign
/// out, remove) is open.
struct AccountFlowOpenKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Settings → Account (Prep's F1–F8). No network: connecting stops once the
/// key is stored (and backed up, if chosen). Publishing is M5b.
struct AccountView: View {
    @Environment(AccountModel.self) private var account
    @Environment(JournalStore.self) private var store
    @Environment(SyncService.self) private var sync

    enum Sheet: String, Identifiable {
        case restore, importKey, backupOffer, signOut, remove
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?
    /// Between a connecting sheet closing and the backup offer opening.
    @State private var offeringBackup = false
    @State private var confirmingCreate = false
    @State private var notice: String?
    /// The flow [Try again] reopens, for notices that offer it.
    @State private var retry: Sheet?

    private var longSaving: Int? {
        guard let context = store.container?.mainContext, let owner = account.activeOwner else { return nil }
        return try? JournalRepository(context: context, activeOwner: owner).longSavingCount()
    }

    var body: some View {
        List {
            switch account.state {
            case .guest, .signedOut:
                Section {
                    Button(AccountCopy.usedBefore) { sheet = .restore }
                        .accessibilityIdentifier("account.usedBefore")
                    Button(AccountCopy.createKey) { confirmingCreate = true }
                        .accessibilityIdentifier("account.create")
                    Button(AccountCopy.useNostr) { sheet = .importKey }
                        .accessibilityIdentifier("account.import")
                } header: {
                    Text(AccountCopy.connectHeading)
                }
            case .connected(let pubkey):
                Section {
                    LabeledContent("Account", value: Self.shortNpub(pubkey))
                        .accessibilityIdentifier("account.npub")
                    if account.hasBackup(for: pubkey) == false {
                        Button(AccountCopy.backUpLater) { sheet = .backupOffer }
                            .accessibilityIdentifier("account.backUp")
                    }
                    Button(AccountCopy.signOut) { sheet = .signOut }
                        .accessibilityIdentifier("account.signOut")
                }
                // The account's own list has nowhere to save (Seth option A,
                // zero write relays): shown while it lasts, no alert (Prep §1).
                if sync.relays?.write?.isEmpty == true {
                    Section {
                        Text(SyncCopy.noWriteRelays)
                            .accessibilityIdentifier("account.noWriteRelays")
                    }
                } else if sync.couldNotReach {
                    // Spec B: the read didn't complete, so nothing was published.
                    Section {
                        Text(SyncCopy.couldNotReach)
                            .accessibilityIdentifier("account.couldNotReach")
                    }
                } else if let n = longSaving, n > 0 {
                    // 7 days in Saving: one quiet line, no alert or badge.
                    Section {
                        Text(SyncCopy.longSaving(n))
                            .accessibilityIdentifier("account.longSaving")
                        Button(SyncCopy.tryNow) { sync.tryNow() }
                            .accessibilityIdentifier("account.tryNow")
                    }
                }
            case .keyMissing:
                Section {
                    Text(AccountCopy.keyMissing)
                    Button(AccountCopy.restore) { sheet = .restore }
                        .accessibilityIdentifier("account.restoreMissing")
                }
            case .mismatch:
                Section { Text(AccountCopy.mismatch) }
            case .unknown, .locked, .keyUnavailable:
                // Prep F6: no new screen and no account prompts while unknown.
                EmptyView()
            }

            if let notice {
                Section {
                    Text(notice).accessibilityIdentifier("account.notice")
                    if let retry {
                        Button(AccountCopy.tryAgain) {
                            self.notice = nil
                            self.retry = nil
                            sheet = retry
                        }
                        .accessibilityIdentifier("account.noticeRetry")
                    }
                }
            }

            switch account.state {
            case .connected, .signedOut, .keyMissing, .mismatch:
                Section {
                    Button(AccountCopy.remove, role: .destructive) { sheet = .remove }
                        .accessibilityIdentifier("account.remove")
                }
            default:
                EmptyView()
            }
        }
        .navigationTitle("Account")
        .onAppear { account.refresh(context: store.container?.mainContext) }
        .confirmationDialog(AccountCopy.createHeading, isPresented: $confirmingCreate, titleVisibility: .visible) {
            Button(AccountCopy.makeNewKey) { create() }
            Button(AccountCopy.usedItBefore) { sheet = .restore }
            Button(AccountCopy.cancel, role: .cancel) {}
        } message: {
            Text(AccountCopy.createBody)
        }
        // The spec A sheet waits for these flows: presenting it over one
        // closes it, and the backup offer must not be lost that way.
        .preference(key: AccountFlowOpenKey.self, value: sheet != nil || offeringBackup)
        .sheet(item: $sheet) { which in
            NavigationStack {
                switch which {
                case .restore: RestoreView(onImport: { sheet = .importKey }, onDone: done)
                case .importKey: ImportKeyView(onDone: done)
                case .backupOffer: BackupOfferView(onDone: done)
                case .signOut: SignOutView(onBackUpFirst: { sheet = .backupOffer }, onDone: done)
                case .remove: RemoveDataView(onDone: done)
                }
            }
        }
    }

    private func create() {
        guard let context = store.container?.mainContext else { return }
        do {
            _ = try account.createKey(context: context)
            sheet = .backupOffer
        } catch {
            notice = AccountCopy.importSaveFailed
        }
    }

    /// A sheet finished. If it connected an account, offer the backup next.
    private func done(_ result: FlowResult) {
        sheet = nil
        retry = nil
        switch result {
        case .connected:
            offeringBackup = true
            DispatchQueue.main.async { sheet = .backupOffer; offeringBackup = false }
        case .message(let text):
            notice = text
        case .retryable(let text, let flow):
            notice = text
            retry = flow
        case .closed:
            break
        }
    }

    static func shortNpub(_ pubkeyHex: String) -> String {
        guard let data = NostrKeys.data(hex: pubkeyHex), let npub = try? NostrKeys.npub(data) else { return "" }
        return String(npub.prefix(12)) + "…" + String(npub.suffix(6))
    }
}

enum FlowResult {
    case connected, message(String), closed
    /// A notice with [Try again], which reopens `flow` (Prep F7/F8).
    case retryable(String, AccountView.Sheet)
}

// MARK: - F3 Restore

struct RestoreView: View {
    @Environment(AccountModel.self) private var account
    @Environment(JournalStore.self) private var store
    let onImport: () -> Void
    let onDone: (FlowResult) -> Void
    @State private var list: KeyVault.BackupList?
    @State private var error: String?

    var body: some View {
        List {
            switch list {
            case nil:
                Text(AccountCopy.searching)
            case .unavailable, .backups([]):
                Section {
                    Text(AccountCopy.noneYet).accessibilityIdentifier("restore.noneYet")
                    Button(AccountCopy.tryAgain) { search() }
                    Button(AccountCopy.useNostr) { onImport() }
                    Button(AccountCopy.back) { onDone(.closed) }
                }
            case .backups(let backups):
                Section {
                    if backups.count == 1 { Text(AccountCopy.foundOne) }
                    ForEach(backups, id: \.account) { backup in
                        Button(backups.count == 1 ? AccountCopy.restore : AccountCopy.backupFrom(backup.created)) {
                            restore(backup)
                        }
                        .accessibilityIdentifier("restore.backup")
                    }
                }
            }
            if account.skippedBackups > 0 {
                Text(AccountCopy.backupsSkipped(account.skippedBackups)).accessibilityIdentifier("restore.skipped")
            }
            if let error { Text(error) }
        }
        .navigationTitle(AccountCopy.usedBefore)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: search)
    }

    private func search() {
        list = account.backups
        guard let context = store.container?.mainContext else { return }
        let repo = JournalRepository(context: context)
        if case .backups(let b) = list, !b.isEmpty {
            try? repo.clearFlag(JournalFlag.restorePending)
        } else {
            // Prep F3: keep checking on later launches; Today shows a quiet line.
            try? repo.setFlag(JournalFlag.restorePending)
        }
    }

    private func restore(_ backup: KeyVault.Backup) {
        guard let context = store.container?.mainContext else { return }
        do {
            _ = try account.restore(backup, context: context)
            try? JournalRepository(context: context).clearFlag(JournalFlag.restorePending)
            onDone(.closed)
        } catch .belongsToAnotherAccount {
            error = AccountCopy.importAnotherAccount
        } catch {
            self.error = AccountCopy.importSaveFailed
        }
    }
}

// MARK: - F5 Import

struct ImportKeyView: View {
    @Environment(AccountModel.self) private var account
    @Environment(JournalStore.self) private var store
    let onDone: (FlowResult) -> Void
    @State private var text = ""
    @State private var parsedNpub: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                // No credential content type: iOS must not offer to save the
                // key as a password (Audit, design §6a).
                SecureField("nsec1…", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("import.field")
                    .onChange(of: text) { _, _ in parsedNpub = nil; error = nil }
                Button("Paste") { paste() }
                    .accessibilityIdentifier("import.paste")
            } footer: {
                Text(AccountCopy.importPrompt + " " + AccountCopy.clipboardHint)
            }
            if let parsedNpub {
                Section {
                    Text(AccountCopy.importConfirm(parsedNpub))
                        .accessibilityIdentifier("import.confirm")
                    Button(AccountCopy.importSave) { save() }
                        .accessibilityIdentifier("import.save")
                }
            } else {
                Button("Continue") { check() }
                    .disabled(text.isEmpty)
                    .accessibilityIdentifier("import.check")
            }
            if let error { Text(error).accessibilityIdentifier("import.error") }
        }
        .navigationTitle(AccountCopy.useNostr)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(AccountCopy.cancel) { text = ""; onDone(.closed) } }
        }
    }

    private func paste() {
        text = PasteboardReader.readOnceAndClear() ?? text
    }

    private func check() {
        guard let secret = KeyInput.parse(text), let pub = KeyVault.pubkeyHex(for: secret),
              let data = NostrKeys.data(hex: pub), let npub = try? NostrKeys.npub(data)
        else { error = AccountCopy.importInvalid; return }
        parsedNpub = npub
    }

    private func save() {
        guard let context = store.container?.mainContext else { return }
        do {
            _ = try account.importKey(text, context: context)
            text = ""
            onDone(.connected)
        } catch .invalidKey {
            error = AccountCopy.importInvalid
        } catch .belongsToAnotherAccount {
            error = AccountCopy.importAnotherAccount
        } catch {
            self.error = AccountCopy.importSaveFailed
        }
    }
}

/// Reads the pasteboard once, on the person's tap, and clears it if nothing
/// newer was copied since (design §6a, Audit: `changeCount`).
enum PasteboardReader {
    @MainActor
    static func readOnceAndClear(_ pasteboard: UIPasteboard = .general) -> String? {
        let count = pasteboard.changeCount
        guard let value = pasteboard.string else { return nil }
        if pasteboard.changeCount == count {
            pasteboard.items = []
        }
        return value
    }
}

// MARK: - F2 Backup offer

struct BackupOfferView: View {
    @Environment(AccountModel.self) private var account
    let onDone: (FlowResult) -> Void
    @State private var confirmingDecline = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Text(AccountCopy.backupHeading).font(.title2.weight(.semibold))
                Text(AccountCopy.backupBody).fixedSize(horizontal: false, vertical: true)
                Button(AccountCopy.backupYes) {
                    do {
                        try account.backUpKey()
                        onDone(.message(AccountCopy.backupSaved))
                    } catch {
                        onDone(.message(AccountCopy.importSaveFailed))
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("backup.yes")
                Button(AccountCopy.backupNo) { confirmingDecline = true }
                    .accessibilityIdentifier("backup.no")
            }
            .padding(GDSpacing.medium)
        }
        .confirmationDialog(AccountCopy.declineConfirm, isPresented: $confirmingDecline, titleVisibility: .visible) {
            Button(AccountCopy.goBack, role: .cancel) {}
            Button(AccountCopy.continueWithout) { onDone(.closed) }
        }
    }
}

// MARK: - F7 Sign out

struct SignOutView: View {
    @Environment(AccountModel.self) private var account
    @Environment(JournalStore.self) private var store
    let onBackUpFirst: () -> Void
    let onDone: (FlowResult) -> Void

    var body: some View {
        let context = store.container?.mainContext
        let unsynced = context.flatMap { account.unsyncedCount(context: $0) }
        let pubkey = account.activeOwner ?? ""
        let hasBackup = account.hasBackup(for: pubkey) == true
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Text(AccountCopy.signOutHeading).font(.title2.weight(.semibold))
                Text(AccountCopy.signOutAlways)
                if let unsynced, unsynced > 0 {
                    Text(AccountCopy.signOutUnsynced(unsynced)).accessibilityIdentifier("signOut.unsynced")
                }
                if !hasBackup {
                    Text(AccountCopy.signOutNoBackup).accessibilityIdentifier("signOut.noBackup")
                    Button(AccountCopy.backUpFirst) { onBackUpFirst() }.buttonStyle(.borderedProminent)
                    Button(AccountCopy.signOutAnyway, role: .destructive) { signOut() }
                        .accessibilityIdentifier("signOut.confirm")
                } else {
                    Button(AccountCopy.signOut, role: .destructive) { signOut() }
                        .accessibilityIdentifier("signOut.confirm")
                }
                Button(AccountCopy.cancel) { onDone(.closed) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(GDSpacing.medium)
        }
    }

    private func signOut() {
        guard let context = store.container?.mainContext else { onDone(.message(AccountCopy.signOutFailed)); return }
        switch account.signOut(context: context) {
        case .signedOut: onDone(.closed)
        case .stayedSignedIn, .blocked: onDone(.message(AccountCopy.signOutFailed))
        case .unconfirmed: onDone(.retryable(AccountCopy.signOutUnconfirmed, .signOut))
        }
    }
}

// MARK: - F8 Remove account and local data

struct RemoveDataView: View {
    @Environment(AccountModel.self) private var account
    @Environment(JournalStore.self) private var store
    let onDone: (FlowResult) -> Void
    @State private var confirmingSecond = false
    @State private var askingBackup = false
    @State private var removedPubkey: String?

    var body: some View {
        let context = store.container?.mainContext
        let repo = context.map { JournalRepository(context: $0, activeOwner: account.activeOwner) }
        // Every reflection on this iPhone is removed and nothing syncs before
        // M5b, so all of them count; unreadable counts block the action.
        let all = repo.flatMap { try? $0.allReflectionCount() }
        let other = repo.flatMap { try? $0.otherAccountDayCount() } ?? 0
        let pubkey = markerPubkey
        let hasBackup = pubkey.map { account.hasBackup(for: $0) == true } ?? false
        ScrollView {
            VStack(alignment: .leading, spacing: GDSpacing.medium) {
                Text(AccountCopy.removeHeading).font(.title2.weight(.semibold))
                Text(AccountCopy.removeBody)
                if let all, all > 0 { Text(AccountCopy.removeUnsynced(all)) }
                if other > 0 { Text(AccountCopy.removeIncludesOther(other)) }
                if !hasBackup { Text(AccountCopy.removeNoBackup) }
                Button(AccountCopy.removeButton, role: .destructive) { confirmingSecond = true }
                    .disabled(all == nil)
                    .accessibilityIdentifier("remove.step1")
                Button(AccountCopy.cancel) { onDone(.closed) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(GDSpacing.medium)
        }
        .confirmationDialog(all.map(AccountCopy.removeSecond) ?? AccountCopy.removeNothingDone, isPresented: $confirmingSecond, titleVisibility: .visible) {
            // Never "0 reflections" when the count can't be read (Audit M5a L2).
            if all != nil {
                Button(AccountCopy.delete, role: .destructive) { remove(hasBackup: hasBackup, pubkey: pubkey) }
                    .accessibilityIdentifier("remove.step2")
            }
            Button(AccountCopy.cancel, role: .cancel) {}
        }
        .confirmationDialog(AccountCopy.deleteBackupHeading, isPresented: $askingBackup, titleVisibility: .visible) {
            Button(AccountCopy.keepBackup, role: .cancel) { onDone(.closed) }
            Button(AccountCopy.deleteBackup, role: .destructive) {
                if let removedPubkey { _ = account.deleteBackups(for: removedPubkey) }
                onDone(.closed)
            }
        } message: {
            Text(AccountCopy.deleteBackupBody)
        }
    }

    private var markerPubkey: String? {
        switch account.state {
        case .connected(let p), .signedOut(let p), .keyMissing(let p): return p
        case .mismatch(_, let marker): return marker
        default: return nil
        }
    }

    private func remove(hasBackup: Bool, pubkey: String?) {
        guard let context = store.container?.mainContext else { onDone(.message(AccountCopy.removeNothingDone)); return }
        switch account.removeAccountAndData(context: context, store: store) {
        case .removed:
            if hasBackup, let pubkey {
                removedPubkey = pubkey
                askingBackup = true
            } else {
                onDone(.closed)
            }
        case .keyDeleteFailed, .blocked:
            onDone(.message(AccountCopy.removeNothingDone))
        case .keyDeleteUnconfirmed:
            onDone(.retryable(AccountCopy.removeUnconfirmed, .remove))
        case .journalNotRemoved:
            onDone(.message(AccountCopy.removeKeyOnly))
        }
    }
}
