import SwiftUI
import TrustCore

/// Automatic server completion after phone verification. This route never asks a
/// person to choose a handle and never returns a verified account to OTP entry.
struct PhoneOnboardingCompletionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAccountHelp = false
    @State private var showingDeleteAccount = false
    @State private var showingSignOutOptions = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TrustWordmark()
                        .padding(.top, 24)
                    Image(systemName: model.isCompletingPhoneOnboarding ? "checkmark.circle" : "person.crop.circle.badge.checkmark")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(palette.positive)
                        .frame(width: 64, height: 64)
                        .background(palette.positive.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)
                    Text(TrustCopy.phoneSetupFinishingTitle)
                        .font(TrustTheme.display(30))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("phone-onboarding-finishing")
                    Text(TrustCopy.phoneSetupFinishingBody)
                        .trustFont(16)
                        .lineSpacing(3)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.isCompletingPhoneOnboarding {
                        HStack(spacing: 12) {
                            ProgressView().tint(palette.accent)
                            Text(TrustCopy.phoneSetupFinishingTitle)
                                .trustFont(14, weight: .medium)
                                .foregroundStyle(palette.muted)
                        }
                        .frame(minHeight: 48, alignment: .leading)
                        .accessibilityIdentifier("phone-onboarding-progress")
                    } else {
                        if let notice = model.onboardingNotice, !notice.isEmpty {
                            Text(notice)
                                .trustFont(14)
                                .foregroundStyle(palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("phone-onboarding-error")
                        }
                        Button(TrustCopy.retry) { model.retryVerifiedPhoneOnboarding() }
                            .buttonStyle(TrustFilledButtonStyle())
                            .disabled(model.isCompletingPhoneOnboarding)
                            .accessibilityIdentifier("phone-onboarding-retry")
                    }

                    Button(TrustCopy.accountHelp) { showingAccountHelp = true }
                        .buttonStyle(TrustOutlineButtonStyle(compact: true))
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("phone-account-help")
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.bottom, 24)
                .trustReadableWidth()
            }
            legalLinks
        }
        .background(palette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let toast = model.toast {
                TrustToastView(toast: toast) { model.toast = nil }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(palette.canvas)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.toast?.id)
        .sheet(isPresented: $showingAccountHelp) {
            AccountHelpSheet(onSignOut: {
                if model.outboundActiveCount > 0 { showingSignOutOptions = true }
                else { model.signOut() }
            }, onDelete: { showingDeleteAccount = true })
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(TrustCopy.deleteAccountConfirm, isPresented: $showingDeleteAccount) {
            Button(TrustCopy.deleteAccount, role: .destructive) { Task { await model.deleteAccount() } }
            Button(TrustCopy.cancel, role: .cancel) {}
        } message: {
            Text(TrustCopy.accountHelpBody)
        }
        .confirmationDialog(TrustCopy.signOut, isPresented: $showingSignOutOptions, titleVisibility: .visible) {
            if model.canStopAllBeforeSignOut {
                Button(TrustCopy.stopAllAndSignOut, role: .destructive) { Task { await model.stopAllAndSignOut() } }
            }
            Button(TrustCopy.signOut) { model.signOut() }
            Button(TrustCopy.cancel, role: .cancel) {}
        } message: {
            Text(TrustCopy.signOutSharingWarning)
        }
        .task {
            if model.phase == .handle, !model.isCompletingPhoneOnboarding {
                model.retryVerifiedPhoneOnboarding()
            }
        }
    }

    private var legalLinks: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("·")
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("·")
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                        .frame(minHeight: 44)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(spacing: 0) {
                    Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .font(TrustTheme.ui(12))
            .foregroundStyle(palette.muted)
            .tint(palette.muted)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.bottom, 8)
        .trustReadableWidth()
        .background(palette.paper)
    }
}
