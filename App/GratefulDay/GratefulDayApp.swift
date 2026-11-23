import SwiftUI
import UIKit

/// Grateful Day for iPhone. The journal is stored on this iPhone; the journal
/// key, when there is one, is in the Keychain. While an account is connected
/// it reads the journal from relays in the foreground (M5b-1, read only).
@main
struct GratefulDayApp: App {
    @State private var store = JournalStore()
    @State private var reminder = ReminderModel()
    @State private var account = AccountModel()
    /// UI tests choose their relays by launch argument (Debug builds only).
    @State private var sync = SyncService(transport: UITestRelays.transport(arguments: ProcessInfo.processInfo.arguments))
    /// Spec A sheet: shown when a pass is waiting on it. Not now hides it
    /// until the next launch; it publishes nothing and loses nothing.
    @State private var disclosureCount: Int?
    @State private var disclosureDeclined = false
    /// An Account sheet is open: the spec A sheet waits until it closes.
    @State private var accountFlowOpen = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(reminder)
                .environment(account)
                .environment(sync)
                // The account state depends on the journal marker, so it's
                // recomputed whenever the store opens, closes or is replaced.
                .onChange(of: store.container.map(ObjectIdentifier.init), initial: true) { _, _ in
                    account.refresh(context: store.container?.mainContext)
                }
                // A read pass belongs to one store and one account (Audit M3).
                .onChange(of: store.container.map(ObjectIdentifier.init)) { _, _ in sync.reset() }
                .onChange(of: account.activeOwner) { _, _ in
                    sync.reset()
                    disclosureDeclined = false
                    // An account connected while the app is open (a new key,
                    // an import, a restore) is read now, not at the next
                    // return to the foreground: that pass is what brings up
                    // the spec A sheet. Does nothing when signed out.
                    readFromRelays()
                }
                .onChange(of: sync.publishDeferral) { _, deferral in
                    guard deferral == .notAllowedYet, !disclosureDeclined,
                          let context = store.container?.mainContext, let owner = account.activeOwner else { return }
                    disclosureCount = (try? PublishDisclosure(context: context, owner: owner).pendingCount()) ?? 0
                }
                .onPreferenceChange(AccountFlowOpenKey.self) { accountFlowOpen = $0 }
                .sheet(isPresented: Binding(get: { disclosureCount != nil && !accountFlowOpen },
                                            set: { if !$0, !accountFlowOpen { disclosureCount = nil } })) {
                    PublishDisclosureSheet(count: disclosureCount ?? 0, onContinue: acceptDisclosure) {
                        disclosureDeclined = true
                        disclosureCount = nil
                    }
                }
                // Never at App.init: open only once the scene is active and
                // protected data is available (storage recommendation §1, S2).
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { openStore() }
                    // No relay connection outlives the foreground (Chief P26).
                    if phase == .background { sync.stop() }
                }
                .onReceive(NotificationCenter.default
                    .publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)
                    .receive(on: RunLoop.main)) { _ in
                    openStore()
                }
                .onReceive(NotificationCenter.default
                    .publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
                    .receive(on: RunLoop.main)) { _ in
                    store.saveBeforeLock()
                }
        }
    }

    private func installRunner() {
        sync.runner = { [self] in readFromRelays() }
    }

    private func openStore() {
        installRunner()
        guard UIApplication.shared.applicationState != .background else { return }
        store.openIfPossible(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        account.refresh(context: store.container?.mainContext)
        readFromRelays()
    }

    private func acceptDisclosure() {
        disclosureCount = nil
        guard let context = store.container?.mainContext, let owner = account.activeOwner else { return }
        do {
            try PublishDisclosure(context: context, owner: owner).accept()
        } catch {
            StorageLog.error("Saving the privacy choice failed", error: error)
            return
        }
        // Fetch first again, then publish (spec B).
        readFromRelays()
    }

    /// Read the connected account's journal, then publish once spec A was
    /// accepted (M5b).
    private func readFromRelays() {
        guard let context = store.container?.mainContext, let key = account.connectedKey() else { return }
        let store = store, account = account, owner = key.pubkey
        sync.start(owner: owner, secret: key.secret, context: context) {
            store.container?.mainContext === context && account.activeOwner == owner
        }
    }
}
