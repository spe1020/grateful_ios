import SwiftUI
import UIKit

/// Grateful Day for iPhone. Guest journal stored on this iPhone only; nothing
/// here touches the network, keys or accounts.
@main
struct GratefulDayApp: App {
    @State private var store = JournalStore()
    @State private var reminder = ReminderModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(reminder)
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
    }
}
