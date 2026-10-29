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
#if TRUST_STAGING
        .overlay(alignment: .topTrailing) {
            Text("STAGING")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(palette.surface.opacity(0.94), in: Capsule())
                .overlay(Capsule().stroke(palette.line, lineWidth: 1))
                .padding(.top, 7)
                .padding(.trailing, 12)
                .accessibilityLabel("Staging build")
        }
#endif
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
