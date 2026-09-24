import SwiftUI
import TrustCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    /// Light only — Trust paper / ink / `#E10600` (map chrome tokens on TrustPalette).
    private let palette = TrustPalette.paper

    var body: some View {
        ZStack {
            palette.paper.ignoresSafeArea()
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
        .preferredColorScheme(.light)
        .tint(palette.accent)
        .onChange(of: scenePhase) { _, phase in
            model.location.setAppActive(phase == .active)
            if phase == .active, model.phase == .home {
                Task { await model.refresh() }
            }
        }
    }
}
