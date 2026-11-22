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
    @State private var sync = SyncService()
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

    private func openStore() {
        guard UIApplication.shared.applicationState != .background else { return }
        store.openIfPossible(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        account.refresh(context: store.container?.mainContext)
        readFromRelays()
    }

    /// M5b-1: read the connected account's journal (never publishes).
    private func readFromRelays() {
        guard let context = store.container?.mainContext, let key = account.connectedKey() else { return }
        sync.start(owner: key.pubkey, secret: key.secret, context: context)
    }
}
