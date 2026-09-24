import SwiftUI
import TrustCore

/// Phone number and one SMS code, after Sign in with Apple.
struct PhoneView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var focused: Field?

    private enum Field {
        case phone
        case code
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustWordmark()
                    .padding(.bottom, 28)

                Text(TrustCopy.yourPhone)
                    .font(TrustTheme.display(38))
                    .tracking(-1)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                TrustRule()
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                Text(TrustCopy.phoneIntro)
                    .trustFont(15)
                    .lineSpacing(3)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 18) {
                    TrustFieldLabel(title: TrustCopy.phoneNumber, hint: nil) {
                        TextField(TrustCopy.phonePlaceholder, text: $model.phoneDraft)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .font(TrustTheme.ui(17))
                            .foregroundStyle(palette.ink)
                            .focused($focused, equals: .phone)
                            .onSubmit { Task { await model.sendPhoneCode() } }
                            .padding(14)
                            .background(palette.paper)
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color(hex: 0xDEDFD5), lineWidth: 1))
                            .accessibilityIdentifier("phone-number")
                    }

                    Toggle(isOn: $model.phoneConsentChecked) {
                        Text(TrustCopy.phoneConsent)
                            .trustFont(15)
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(palette.accent)
                    .accessibilityIdentifier("phone-consent")

                    HStack(spacing: 16) {
                        Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                        Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                    }
                    .trustFont(15)

                    Button(model.phoneCodeSent ? TrustCopy.resendCode : TrustCopy.sendCode) {
                        focused = .code
                        Task { await model.sendPhoneCode() }
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                    .disabled(
                        !model.phoneConsentChecked
                            || model.isSendingPhone
                            || model.phoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("send-phone-code")

                    if model.phoneCodeSent {
                        TrustFieldLabel(title: TrustCopy.phoneCode, hint: nil) {
                            TextField(TrustCopy.codePlaceholderShort, text: $model.phoneCodeDraft)
                                .textContentType(.oneTimeCode)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .font(TrustTheme.ui(17))
                                .foregroundStyle(palette.ink)
                                .focused($focused, equals: .code)
                                .onSubmit { Task { await model.verifyPhoneCode() } }
                                .padding(14)
                                .background(palette.paper)
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color(hex: 0xDEDFD5), lineWidth: 1))
                                .accessibilityIdentifier("phone-code")
                        }

                        Button(TrustCopy.verify) {
                            focused = nil
                            Task { await model.verifyPhoneCode() }
                        }
                        .buttonStyle(TrustFilledButtonStyle())
                        .disabled(model.isSendingPhone || model.phoneCodeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("verify-phone-code")
                    }

                    if let notice = model.phoneNotice, !notice.isEmpty {
                        Text(notice)
                            .font(TrustTheme.ui(13))
                            .foregroundStyle(palette.accent)
                            .accessibilityIdentifier("phone-notice")
                    }
                }
                .padding(.top, 28)

                Spacer(minLength: 32)

                Button(TrustCopy.signOut) {
                    model.signOut()
                }
                .buttonStyle(TrustTextButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .trustReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.paper.ignoresSafeArea())
        .onAppear { focused = model.phoneCodeSent ? .code : .phone }
    }
}
