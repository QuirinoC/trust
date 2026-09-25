import SwiftUI
import TrustCore

/// Phone verification. Consent begins unchecked and must be chosen before a text is sent.
struct PhoneView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var focused: Field?

    private enum Field { case phone, code }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustWordmark().padding(.bottom, 30)
                TrustEyebrow(text: "One more step", color: palette.accent)
                    .padding(.bottom, 8)
                Text(TrustCopy.yourPhone)
                    .font(TrustTheme.display(32))
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(TrustCopy.phoneIntro)
                    .trustFont(16)
                    .lineSpacing(3)
                    .foregroundStyle(palette.muted)
                    .padding(.top, 8)
                    .padding(.bottom, 22)

                TrustCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        TrustFieldLabel(title: TrustCopy.phoneNumber, hint: nil) {
                            TextField(TrustCopy.phonePlaceholder, text: $model.phoneDraft)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.send)
                                .trustFont(17)
                                .foregroundStyle(palette.ink)
                                .focused($focused, equals: .phone)
                                .onSubmit { Task { await model.sendPhoneCode() } }
                                .padding(14)
                                .frame(minHeight: 52)
                                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                                .accessibilityLabel(TrustCopy.phoneNumber)
                                .accessibilityIdentifier("phone-number")
                        }

                        Toggle(isOn: $model.phoneConsentChecked) {
                            Text(TrustCopy.phoneConsent)
                                .trustFont(14)
                                .foregroundStyle(palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .tint(palette.accent)
                        .accessibilityIdentifier("phone-consent")

                        HStack(spacing: 18) {
                            Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
                            Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                        }
                        .trustFont(14, weight: .medium)
                        .tint(palette.accent)

                        Button {
                            focused = model.phoneCodeSent ? .code : .phone
                            Task { await model.sendPhoneCode() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isSendingPhone { ProgressView().tint(palette.accentOn) }
                                Text(model.phoneCodeSent ? TrustCopy.resendCode : TrustCopy.sendCode)
                            }
                        }
                        .buttonStyle(TrustFilledButtonStyle())
                        .disabled(!model.phoneConsentChecked || model.isSendingPhone || model.phoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("send-phone-code")

                        if model.phoneCodeSent {
                            Label(TrustCopy.codeSent, systemImage: "checkmark.circle.fill")
                                .trustFont(14, weight: .medium)
                                .foregroundStyle(palette.positive)
                                .fixedSize(horizontal: false, vertical: true)

                            TrustFieldLabel(title: TrustCopy.verificationCode, hint: nil) {
                                TextField(TrustCopy.codePlaceholderShort, text: $model.phoneCodeDraft)
                                    .textContentType(.oneTimeCode)
                                    .keyboardType(.numberPad)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .trustFont(17)
                                    .foregroundStyle(palette.ink)
                                    .focused($focused, equals: .code)
                                    .onSubmit { Task { await model.verifyPhoneCode() } }
                                    .padding(14)
                                    .frame(minHeight: 52)
                                    .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                                    .accessibilityIdentifier("phone-code")
                            }

                            Button {
                                focused = nil
                                Task { await model.verifyPhoneCode() }
                            } label: {
                                HStack(spacing: 8) {
                                    if model.isSendingPhone { ProgressView().tint(palette.accentOn) }
                                    Text(TrustCopy.verify)
                                }
                            }
                            .buttonStyle(TrustFilledButtonStyle())
                            .disabled(model.isSendingPhone || model.phoneCodeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("verify-phone-code")
                        }

                        if let notice = model.phoneNotice, !notice.isEmpty {
                            Text(notice)
                                .trustFont(13)
                                .foregroundStyle(palette.accent)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("phone-notice")
                        }
                    }
                }

                Button(TrustCopy.signOut) { model.signOut() }
                    .buttonStyle(TrustTextButtonStyle())
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .trustReadableWidth()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.canvas.ignoresSafeArea())
        .onAppear { focused = model.phoneCodeSent ? .code : .phone }
    }
}
