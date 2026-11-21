import SwiftUI

/// Grateful Day for iPhone. M1: the app shell only. Nothing here touches the
/// network, keys or accounts; local storage arrives in M2.
@main
struct GratefulDayApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
