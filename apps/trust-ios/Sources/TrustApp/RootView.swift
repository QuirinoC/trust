import SwiftUI
import TrustCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(TrustAppearance.storageKey) private var appearance = TrustAppearance.system.rawValue
    @AppStorage(TrustAppLanguage.storageKey) private var appLanguage = TrustAppLanguage.system.rawValue
    private let palette = TrustPalette.paper

    var body: some View {
        ZStack {
            palette.canvas.ignoresSafeArea()
            switch model.phase {
            case .ageChecking, .ageGate, .ageCheckUnavailable, .ageRangeSharingDeclined, .ageRangeBlocked, .ageWaitingForParent, .ageBlocked, .ageConsentRevoked, .agePrivacyHoldPending, .agePrivacyHeld, .appTransactionChecking, .appTransactionUnavailable:
                AgeGateView()
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
        .environment(\.locale, (TrustAppLanguage(rawValue: appLanguage) ?? .system).resolvedLocale)
        .tint(palette.accent)
        .preferredColorScheme((TrustAppearance(rawValue: appearance) ?? .system).colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.ageUpdateSceneDidEnterBackground()
            } else if phase == .active {
                model.ageUpdateSceneDidBecomeActive()
            }
            model.setSceneActive(phase == .active)
            if phase == .active, model.phase == .home {
                Task { await model.refreshIfStale() }
            }
        }
    }
}
