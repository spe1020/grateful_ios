import SwiftUI
import UIKit

/// Grateful Day for iPhone. The journal is stored on this iPhone; the journal
/// key, when there is one, is in the Keychain. Nothing here touches the
/// network (publishing is M5b).
@main
struct GratefulDayApp: App {
    @State private var store = JournalStore()
    @State private var reminder = ReminderModel()
    @State private var account = AccountModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(reminder)
                .environment(account)
                // The account state depends on the journal marker, so it's
                // recomputed whenever the store opens, closes or is replaced.
                .onChange(of: store.container.map(ObjectIdentifier.init), initial: true) { _, _ in
                    account.refresh(context: store.container?.mainContext)
                }
                // Never at App.init: open only once the scene is active and
                // protected data is available (storage recommendation §1, S2).
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { openStore() }
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
    }
}
