import SwiftUI
import TrustCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TrustAppearance.storageKey) private var appearance = TrustAppearance.system.rawValue
    private let palette = TrustPalette.paper

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()
            switch model.phase {
            case .login:
                LoginView()
            case .handle:
                HandleView()
            case .phone:
                PhoneView()
            case .home:
                MainShellView()
            }
        }
        .environment(\.trustPalette, palette)
        .tint(palette.accent)
        .preferredColorScheme((TrustAppearance(rawValue: appearance) ?? .system).colorScheme)
        .onChange(of: scenePhase) { _, phase in
            model.location.setAppActive(phase == .active)
            if phase == .active, model.phase == .home {
                Task { await model.refreshIfStale() }
            }
        }
    }
}
