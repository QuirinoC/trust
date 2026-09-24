import SwiftUI
import TrustCore

/// A1 Login — `Trust.`, one-line promise, Sign in with Apple, Terms · Privacy · Support.
/// Paper only. DEBUG “See the app” enters the offline fixture for screenshots.
struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrustWordmark()

            Spacer(minLength: 24)

            VStack(alignment: .leading, spacing: 16) {
                TrustWordmarkTitle(size: 64)
                TrustRule()
                Text(TrustCopy.loginPromise)
                    .trustFont(16)
                    .lineSpacing(3)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                #if DEBUG
                Button {
                    Task { await model.signInWithLocalAPI() }
                } label: {
                    Text(model.isSigningIn ? TrustCopy.signingIn : "Local API")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TrustOutlineButtonStyle())
                .disabled(model.isSigningIn)
                .accessibilityIdentifier("local-api-sign-in")
                .accessibilityHint("Signs in to the local API. Not the offline fixture.")

                Button {
                    model.enterDemo()
                } label: {
                    Text(TrustCopy.seeTheApp)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(TrustOutlineButtonStyle())
                .disabled(model.isSigningIn)
                .accessibilityIdentifier("see-the-app")
                .accessibilityHint(TrustCopy.demoBannerBody)
                #endif

                // SF Symbol apple.logo is Apple's mark — not a custom logo.
                Button {
                    Task { await model.signIn(with: .apple) }
                } label: {
                    HStack(spacing: 10) {
                        if model.isSigningIn {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(palette.paper)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18, weight: .medium))
                                .accessibilityHidden(true)
                        }
                        Text(model.isSigningIn ? TrustCopy.signingIn : TrustCopy.signInWithApple)
                            .trustFont(17, weight: .medium)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(TrustAppleButtonStyle())
                .disabled(model.isSigningIn)
                .accessibilityLabel(TrustCopy.signInWithApple)
                .accessibilityValue(model.isSigningIn ? TrustCopy.signingInShort : "")

                HStack(spacing: 14) {
                    Link(TrustCopy.termsOfService, destination: AppConfiguration.termsURL)
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                }
                .font(TrustTheme.folio(10))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(palette.muted)
                .tint(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            if let notice = model.authNotice, !notice.isEmpty {
                Text(notice)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                    .padding(.top, 12)
                    .accessibilityIdentifier("login-notice")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .trustReadableWidth()
        .background(palette.paper.ignoresSafeArea())
        .task { await model.prepareLogin() }
    }
}
