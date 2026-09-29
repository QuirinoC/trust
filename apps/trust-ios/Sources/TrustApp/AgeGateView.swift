import SwiftUI
import TrustCore
import PermissionKit
import _PermissionKit_SwiftUI
import UIKit

struct AgeGateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var birthMonth = ""
    @State private var birthDay = ""
    @State private var birthYear = ""
    @State private var didSubmitBirthDate = false
    @State private var showingDeleteAccount = false
    @FocusState private var focusedField: BirthDateField?

    private enum BirthDateField: Hashable {
        case month
        case day
        case year
    }

    private var birthDateEligibility: TrustAgePolicy.BirthDateEligibility {
        TrustAgePolicy.birthDateEligibility(monthText: birthMonth, dayText: birthDay, yearText: birthYear)
    }

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

                    Spacer(minLength: 36)

                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(width: 62, height: 62)
                        .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityHidden(true)
                        .padding(.bottom, 24)

                    Text(title)
                        .font(TrustTheme.display(32))
                        .tracking(-0.7)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("age-gate-title")

                    Text(bodyText)
                        .trustFont(16)
                        .lineSpacing(4)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .accessibilityIdentifier("age-gate-body")

                    Spacer(minLength: 28)

                    controls

                    Spacer(minLength: 22)

                    HStack(spacing: 18) {
                        Link(TrustCopy.termsOfService, destination: AppConfiguration.termsURL)
                        Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        if model.phase == .ageBlocked || model.phase == .ageCheckUnavailable || model.phase == .ageRangeBlocked || model.phase == .ageConsentRevoked || model.phase == .agePrivacyHoldPending || model.phase == .agePrivacyHeld {
                            Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                                .accessibilityIdentifier("age-gate-support")
                        }
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
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.canvas.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                TrustToastView(toast: toast) { model.toast = nil }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.toast?.id)
        .alert(TrustCopy.deleteAccountConfirm, isPresented: $showingDeleteAccount) {
            Button(TrustCopy.deleteAccount, role: .destructive) {
                Task { await model.deleteAccount() }
            }
            .accessibilityIdentifier("age-privacy-hold-delete-confirm")
            Button(TrustCopy.cancel, role: .cancel) {}
                .accessibilityIdentifier("age-privacy-hold-delete-cancel")
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .ageGate:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    birthDateField(label: TrustCopy.ageBirthMonth, placeholder: TrustCopy.ageBirthMonthPlaceholder, text: $birthMonth, id: "age-birth-month", maxDigits: 2, field: .month)
                    birthDateField(label: TrustCopy.ageBirthDay, placeholder: TrustCopy.ageBirthDayPlaceholder, text: $birthDay, id: "age-birth-day", maxDigits: 2, field: .day)
                    birthDateField(label: TrustCopy.ageBirthYear, placeholder: TrustCopy.ageBirthYearPlaceholder, text: $birthYear, id: "age-birth-year", maxDigits: 4, field: .year)
                }

                if didSubmitBirthDate, birthDateEligibility == .invalid {
                    Text(TrustCopy.ageBirthDateInvalid)
                        .trustFont(13)
                        .foregroundStyle(palette.danger)
                        .accessibilityIdentifier("age-birth-date-error")
                }

                Button {
                    didSubmitBirthDate = true
                    switch birthDateEligibility {
                    case .eligible:
                        clearBirthDateDraft()
                        model.confirmBirthDate(isEligible: true)
                    case .underMinimum:
                        clearBirthDateDraft()
                        model.confirmBirthDate(isEligible: false)
                    case .incomplete, .invalid:
                        break
                    }
                } label: {
                    Text(TrustCopy.ageGateContinue)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .disabled(birthDateEligibility == .incomplete)
                .accessibilityIdentifier("age-gate-continue")
            }
        case .ageChecking:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(palette.accent)
                Text(TrustCopy.ageGateChecking)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 52)
        case .ageCheckUnavailable:
            VStack(spacing: 8) {
                Button {
                    model.retryAgeCheck()
                } label: {
                    Text(TrustCopy.ageGateRetry)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .accessibilityIdentifier("age-gate-retry")
            }
        case .ageRangeBlocked:
            VStack(spacing: 12) {
                if #available(iOS 26, *), model.canTryAppleAgeRangeAfterUnderage {
                    Button {
                        model.retryAppleAgeRangeAfterUnderage()
                    } label: {
                        Text(TrustCopy.ageGateTryAppleRange)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                    .accessibilityIdentifier("age-gate-apple-range")
                }
                Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("age-gate-support-action")
            }
        case .agePrivacyHoldPending:
            VStack(spacing: 12) {
                if model.canRetryPrivacyHoldSubmission {
                    Button {
                        model.retryPrivacyHoldSubmission()
                    } label: {
                        Text(TrustCopy.agePrivacyHoldRetry)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                    .accessibilityIdentifier("age-privacy-hold-retry")
                } else {
                    ProgressView()
                        .tint(palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                deleteHeldAccountButton
                Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("age-privacy-hold-support-action")
            }
        case .agePrivacyHeld:
            VStack(spacing: 8) {
                deleteHeldAccountButton
                Link(TrustCopy.support, destination: AppConfiguration.supportURL)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("age-privacy-hold-support-action")
            }
        case .ageWaitingForParent:
            if #available(iOS 26.2, *),
               let question = model.ageUpdateQuestion as? PermissionQuestion<SignificantAppUpdateTopic> {
                VStack(spacing: 12) {
                    PermissionButton(question: question) {
                        Label(TrustCopy.ageParentAction, systemImage: "person.badge.shield.checkmark")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .accessibilityIdentifier("age-parent-approval")

                    Text(TrustCopy.ageParentWaiting)
                        .trustFont(13)
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView(TrustCopy.ageParentWaiting)
                    .tint(palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        case .ageBlocked:
            if model.ageGateBlockedByParent {
                Button {
                    model.retryParentApproval()
                } label: {
                    Text(TrustCopy.ageGateRetry)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .accessibilityIdentifier("age-parent-retry")
            } else if #available(iOS 26, *), model.canTryAppleAgeRangeAfterUnderage {
                Button {
                    model.retryAppleAgeRangeAfterUnderage()
                } label: {
                    Text(TrustCopy.ageGateTryAppleRange)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(TrustFilledButtonStyle())
                .accessibilityIdentifier("age-gate-apple-range")
            } else {
                EmptyView()
            }
        case .ageConsentRevoked, .login, .handle, .phone, .home:
            EmptyView()
        }
    }

    private var deleteHeldAccountButton: some View {
        Button(TrustCopy.deleteAccount, role: .destructive) {
            showingDeleteAccount = true
        }
        .buttonStyle(TrustTextButtonStyle(color: palette.danger))
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityIdentifier("age-privacy-hold-delete-account")
    }

    private func birthDateField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        id: String,
        maxDigits: Int,
        field: BirthDateField
    ) -> some View {
        TrustFieldLabel(title: label, hint: nil) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(TrustTextFieldStyle())
                .textContentType(.none)
                .focused($focusedField, equals: field)
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
                .onChange(of: text.wrappedValue) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(maxDigits))
                    if digits != newValue { text.wrappedValue = digits }
                    if digits.count == maxDigits {
                        switch field {
                        case .month: focusedField = .day
                        case .day: focusedField = .year
                        case .year: focusedField = nil
                        }
                    }
                }
        }
    }

    private func clearBirthDateDraft() {
        focusedField = nil
        birthMonth = ""
        birthDay = ""
        birthYear = ""
    }

    private var title: String {
        switch model.phase {
        case .ageGate: TrustCopy.ageGateTitle
        case .ageChecking: TrustCopy.ageGateTitle
        case .ageCheckUnavailable: TrustCopy.ageGateUnavailableTitle
        case .ageRangeBlocked: TrustCopy.ageRangeBlockedTitle
        case .agePrivacyHoldPending: TrustCopy.agePrivacyHoldPendingTitle
        case .agePrivacyHeld: TrustCopy.agePrivacyHeldTitle
        case .ageWaitingForParent: TrustCopy.ageParentTitle
        case .ageBlocked: TrustCopy.ageGateBlockedTitle
        case .ageConsentRevoked: TrustCopy.ageConsentRevokedTitle
        case .login, .handle, .phone, .home: TrustCopy.ageGateTitle
        }
    }

    private var bodyText: String {
        switch model.phase {
        case .ageGate: TrustCopy.ageGateBody
        case .ageChecking: TrustCopy.ageGateChecking
        case .ageCheckUnavailable: TrustCopy.ageGateUnavailableBody
        case .ageRangeBlocked: TrustCopy.ageRangeBlockedBody
        case .agePrivacyHoldPending: TrustCopy.agePrivacyHoldPendingBody
        case .agePrivacyHeld: TrustCopy.agePrivacyHeldBody
        case .ageWaitingForParent: TrustCopy.ageParentBody
        case .ageBlocked: model.ageGateBlockedByParent ? TrustCopy.ageParentDeclined : TrustCopy.ageGateBlockedBody
        case .ageConsentRevoked: TrustCopy.ageConsentRevokedBody
        case .login, .handle, .phone, .home: TrustCopy.ageGateBody
        }
    }

    private var icon: String {
        switch model.phase {
        case .ageGate, .ageChecking, .ageCheckUnavailable: "person.crop.circle.badge.checkmark"
        case .ageRangeBlocked: "hand.raised.fill"
        case .agePrivacyHoldPending, .agePrivacyHeld: "hand.raised.fill"
        case .ageWaitingForParent: "person.badge.shield.checkmark"
        case .ageBlocked: "hand.raised.fill"
        case .ageConsentRevoked: "hand.raised.fill"
        case .login, .handle, .phone, .home: "person.crop.circle.badge.checkmark"
        }
    }
}
