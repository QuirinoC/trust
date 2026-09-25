import SwiftUI
import TrustCore

/// Sign in with Apple is the primary entry. The preview route remains available in DEBUG.
struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        TrustLineMark()
                            .frame(width: 30, height: 30)
                        Text(TrustCopy.appName)
                            .font(TrustTheme.display(24))
                            .tracking(-0.6)
                            .foregroundStyle(palette.ink)
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.top, 24)

                    Spacer(minLength: 32)

                    TogetherLinesArtwork()
                        .frame(height: min(190, max(142, geometry.size.height * 0.25)))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    Spacer(minLength: 32)

                    Text(TrustCopy.signInTitle)
                        .font(TrustTheme.display(34))
                        .tracking(-0.8)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(TrustCopy.loginPromise)
                        .trustFont(16)
                        .lineSpacing(4)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .padding(.bottom, 28)

                    signInActions

                    Spacer(minLength: 26)

                    HStack(spacing: 18) {
                        Link(TrustCopy.termsOfService, destination: AppConfiguration.termsURL)
                        Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                    }
                    .trustFont(12, weight: .medium)
                    .foregroundStyle(palette.muted)
                    .tint(palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, TrustTheme.gutter)
                .frame(maxWidth: TrustTheme.readableWidth)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.canvas.ignoresSafeArea())
        .task { await model.prepareLogin() }
    }

    private var signInActions: some View {
        VStack(spacing: 12) {
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

            if let notice = visibleAuthNotice, !notice.isEmpty {
                Text(notice)
                    .trustFont(13)
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("login-notice")
            }
        }
    }

    private var visibleAuthNotice: String? {
        guard let notice = model.authNotice else { return nil }
        if model.isScreenshotLaunch, notice == model.client.reachabilityNotice { return nil }
        return notice
    }
}

/// Three open paths form a companion motif without the closed-loop icon silhouette.
private struct TrustLineMark: View {
    @Environment(\.trustPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            Path { path in
                path.move(to: CGPoint(x: width * 0.08, y: height * 0.74))
                path.addCurve(to: CGPoint(x: width * 0.70, y: height * 0.17),
                              control1: CGPoint(x: width * 0.30, y: height * 0.61),
                              control2: CGPoint(x: width * 0.40, y: height * 0.24))
            }
            .stroke(palette.ink, style: StrokeStyle(lineWidth: 4.2, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: width * 0.32, y: height * 0.88))
                path.addCurve(to: CGPoint(x: width * 0.93, y: height * 0.33),
                              control1: CGPoint(x: width * 0.49, y: height * 0.72),
                              control2: CGPoint(x: width * 0.67, y: height * 0.39))
            }
            .stroke(palette.accent, style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct TogetherLinesArtwork: View {
    @Environment(\.trustPalette) private var palette

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, 320.0)
            let height = geometry.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.10, y: height * 0.77))
                    path.addCurve(to: CGPoint(x: width * 0.70, y: height * 0.13),
                                  control1: CGPoint(x: width * 0.24, y: height * 0.49),
                                  control2: CGPoint(x: width * 0.49, y: height * 0.20))
                }
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 13, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.27, y: height * 0.87))
                    path.addCurve(to: CGPoint(x: width * 0.88, y: height * 0.30),
                                  control1: CGPoint(x: width * 0.40, y: height * 0.62),
                                  control2: CGPoint(x: width * 0.63, y: height * 0.40))
                }
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 13, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.53, y: height * 0.86))
                    path.addQuadCurve(to: CGPoint(x: width * 0.84, y: height * 0.61),
                                      control: CGPoint(x: width * 0.67, y: height * 0.63))
                }
                .stroke(palette.positive, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity)
        }
    }
}
