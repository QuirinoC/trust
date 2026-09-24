import SwiftUI
import TrustCore

/// Sign in with Apple is the primary entry. The preview route remains available in DEBUG.
struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 44)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        TrustConnectionMark()
                        Text(TrustCopy.appName)
                            .font(TrustTheme.display(24))
                            .tracking(-0.6)
                            .foregroundStyle(palette.ink)
                    }

                    Text("Stay close. Share on your terms.")
                        .font(TrustTheme.display(32))
                        .tracking(-0.7)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(TrustCopy.loginPromise)
                        .trustFont(15)
                        .lineSpacing(3)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(palette.positive)
                            .accessibilityHidden(true)
                        Text(TrustCopy.trustUsesSignInWithApple)
                            .trustFont(14, weight: .medium)
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 10)

                Spacer(minLength: 30)

                VStack(spacing: 12) {
                    #if DEBUG
                    if !model.isScreenshotLaunch {
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
                    }
                    #endif

                    Button {
                        Task { await model.signIn(with: .apple) }
                    } label: {
                        HStack(spacing: 10) {
                            if model.isSigningIn {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                                    .accessibilityHidden(true)
                            } else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .medium))
                                    .accessibilityHidden(true)
                            }
                            Text(model.isSigningIn ? TrustCopy.signingIn : TrustCopy.signInWithApple)
                                .trustFont(17, weight: .semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(TrustAppleButtonStyle())
                    .disabled(model.isSigningIn)
                    .accessibilityLabel(TrustCopy.signInWithApple)
                    .accessibilityValue(model.isSigningIn ? TrustCopy.signingInShort : "")

                    if let notice = visibleAuthNotice, !notice.isEmpty {
                        Text(notice)
                            .trustFont(13)
                            .foregroundStyle(palette.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("login-notice")
                    }
                }

                HStack(spacing: 18) {
                    Link(TrustCopy.termsOfService, destination: AppConfiguration.termsURL)
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                }
                .trustFont(12, weight: .medium)
                .foregroundStyle(palette.muted)
                .tint(palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, TrustTheme.gutter)
            .trustReadableWidth()
        }
        .scrollIndicators(.hidden)
        .background(palette.canvas.ignoresSafeArea())
        .task { await model.prepareLogin() }
    }

    private var visibleAuthNotice: String? {
        guard let notice = model.authNotice else { return nil }
        if model.isScreenshotLaunch, notice == model.client.reachabilityNotice { return nil }
        return notice
    }
}

/// Two overlapping circles echo the Trust app icon without introducing a second wordmark.
private struct TrustConnectionMark: View {
    @Environment(\.trustPalette) private var palette

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.accent, lineWidth: 3)
                .frame(width: 22, height: 22)
                .offset(x: -7)
            Circle()
                .stroke(palette.accent, lineWidth: 3)
                .frame(width: 22, height: 22)
                .offset(x: 7)
        }
        .frame(width: 36, height: 28)
        .accessibilityHidden(true)
    }
}
