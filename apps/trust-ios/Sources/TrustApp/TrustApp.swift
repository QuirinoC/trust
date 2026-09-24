import SwiftUI

@main
struct TrustApp: App {
    @UIApplicationDelegateAdaptor(TrustAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(TrustTheme.accent)
                .task { await model.start() }
                .onOpenURL { model.handleIncomingURL($0) }
        }
    }
}
