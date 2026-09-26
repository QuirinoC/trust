import SwiftUI
import TrustCore

/// Phone verification. The disclosed Send code action requests one verification text.
struct PhoneView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var focused: Field?

    private enum Field { case phone, code }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrustWordmark().padding(.bottom, model.phoneCodeSent ? 14 : 30)

                    if model.phoneCodeSent {
                        codeEntry
                    } else {
                        phoneEntry
                    }

                    Button(TrustCopy.signOut) { model.signOut() }
                        .buttonStyle(TrustTextButtonStyle())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 20)
                .trustReadableWidth()
            }
            .scrollDismissesKeyboard(.interactively)

            legalLinks
        }
        .background(palette.canvas.ignoresSafeArea())
        .onChange(of: model.phoneCodeSent) { _, sent in
            if sent { focused = .code }
        }
    }

    private var phoneEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                    phoneNumberField

                    Button {
                        focused = nil
                        Task { await model.sendPhoneCode() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isSendingPhone { ProgressView().tint(palette.accentOn) }
                            Text(TrustCopy.sendCode)
                        }
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                    .disabled(model.isSendingPhone || model.phoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("send-phone-code")

                    Text(TrustCopy.phoneConsentDetails)
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    phoneNotice
                }
            }
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(TrustCopy.verifyPhoneTitle)
                .font(TrustTheme.display(29))
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            Text(TrustCopy.phoneCodeIntro)
                .trustFont(14)
                .foregroundStyle(palette.muted)
                .padding(.bottom, 16)

            TrustCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "message.fill")
                            .foregroundStyle(palette.accent)
                            .accessibilityHidden(true)
                        Text(model.phoneDraft)
                            .trustFont(15, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityIdentifier("phone-number-summary")
                        Spacer(minLength: 0)
                        Button(TrustCopy.editPhone) { editPhoneNumber() }
                            .font(TrustTheme.ui(13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .disabled(model.isSendingPhone)
                            .accessibilityIdentifier("edit-phone-number")
                    }

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

                    HStack {
                        Spacer(minLength: 0)
                        Button(TrustCopy.resendCode) {
                            focused = nil
                            Task { await model.sendPhoneCode() }
                        }
                        .font(TrustTheme.ui(13, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .disabled(model.isSendingPhone)
                        .accessibilityIdentifier("send-phone-code")
                    }

                    phoneNotice
                }
            }
        }
    }

    private var phoneNumberField: some View {
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
                .onSubmit { focused = nil }
                .padding(14)
                .frame(minHeight: 52)
                .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                .accessibilityLabel(TrustCopy.phoneNumber)
                .accessibilityIdentifier("phone-number")
        }
    }

    @ViewBuilder
    private var phoneNotice: some View {
        if let notice = model.phoneNotice, !notice.isEmpty {
            Text(notice)
                .trustFont(13)
                .foregroundStyle(model.phoneNoticeIsConflict ? palette.danger : palette.accent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("phone-notice")
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 18) {
            Link(TrustCopy.privacy, destination: AppConfiguration.privacyURL)
            Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
        }
        .trustFont(13, weight: .medium)
        .tint(palette.accent)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(palette.paper)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func editPhoneNumber() {
        model.cancelPendingPhoneSend()
        model.phoneCodeSent = false
        model.phoneCodeDraft = ""
        model.phoneNotice = nil
        focused = .phone
    }
}
