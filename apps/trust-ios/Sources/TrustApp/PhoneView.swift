import SwiftUI
import TrustCore

/// Phone verification. The disclosed Send code action requests one verification text.
struct PhoneView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var focused: Field?

    private enum Field { case phone, code }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrustWordmark().padding(.bottom, model.phoneCodeSent ? 14 : 30)

                    if model.phoneCodeSent {
                        codeEntry(now: now)
                    } else {
                        phoneEntry(now: now)
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

    private func phoneEntry(now: Date) -> some View {
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
                        Task { await model.sendPhoneCode(action: .sendCode) }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isSendingPhone {
                                ProgressView()
                                    .tint(palette.accentOn)
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                            Text(model.isSendingPhone ? TrustCopy.sendingCode : sendLabel(now: now, resend: false))
                        }
                    }
                    .buttonStyle(PhoneSendButtonStyle(coolingDown: model.phoneRetrySeconds(at: now) > 0, isBusy: model.isSendingPhone))
                    .disabled(model.isSendingPhone || model.phoneRetrySeconds(at: now) > 0 || model.phoneDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("send-phone-code")

                    Text(TrustCopy.phoneConsentDetails)
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    retryNotice(now: now)
                    phoneNotice
                }
            }
        }
    }

    private func codeEntry(now: Date) -> some View {
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
                        Text(model.challengedPhone)
                            .trustFont(15, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityIdentifier("phone-number-summary")
                        Spacer(minLength: 0)
                        Button(TrustCopy.editPhone) { editPhoneNumber() }
                            .font(TrustTheme.ui(13, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("edit-phone-number")
                    }

                    TrustFieldLabel(title: TrustCopy.verificationCode, hint: nil) {
                        TextField("", text: $model.phoneCodeDraft, prompt: Text(TrustCopy.codePlaceholderShort).foregroundStyle(palette.muted))
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
                            if model.isSendingPhone {
                                ProgressView()
                                    .tint(palette.accentOn)
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                            Text(model.isSendingPhone ? TrustCopy.phoneRequestPending : TrustCopy.verify)
                        }
                    }
                    .buttonStyle(TrustFilledButtonStyle(isBusy: model.isSendingPhone))
                    .disabled(model.isSendingPhone || model.phoneCodeDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("verify-phone-code")

                    HStack {
                        Spacer(minLength: 0)
                        Button(sendLabel(now: now, resend: true)) {
                            focused = nil
                            Task { await model.sendPhoneCode(action: .resendCode) }
                        }
                        .buttonStyle(PhoneSendButtonStyle(coolingDown: model.phoneRetrySeconds(at: now) > 0, isBusy: model.isSendingPhone))
                        .disabled(model.isSendingPhone || model.phoneRetrySeconds(at: now) > 0)
                        .accessibilityIdentifier("send-phone-code")
                    }

                    retryNotice(now: now)
                    phoneNotice
                }
            }
        }
    }

    private func sendLabel(now: Date, resend: Bool) -> String {
        let seconds = model.phoneRetrySeconds(at: now)
        guard seconds > 0 else { return resend ? TrustCopy.resendCode : TrustCopy.sendCode }
        let duration = String(format: "%d:%02d", seconds / 60, seconds % 60)
        return TrustCopy.phoneRetryButton(duration, resend: resend)
    }

    @ViewBuilder
    private func retryNotice(now: Date) -> some View {
        if model.phoneRetrySeconds(at: now) > 0, let deadline = model.phoneRetryDeadline {
            Text(TrustCopy.phoneRetryExplanation(deadline.formatted(date: Calendar.current.isDateInToday(deadline) ? .omitted : .abbreviated, time: .standard)))
                .trustFont(13)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("phone-retry-notice")
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
                .accessibilityIdentifier("privacy-link")
            Link(TrustCopy.terms, destination: AppConfiguration.termsURL)
                .accessibilityIdentifier("terms-link")
        }
        .trustFont(13, weight: .medium)
        .tint(palette.accent)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(palette.paper)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
    }

    private func editPhoneNumber() {
        model.editPhoneNumber()
        focused = .phone
    }
}

/// The wait state uses an adaptive neutral fill and full-contrast text.
private struct PhoneSendButtonStyle: ButtonStyle {
    let coolingDown: Bool
    let isBusy: Bool
    @Environment(\.trustPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(16, weight: .semibold)
            .foregroundStyle(coolingDown ? palette.ink : palette.accentOn)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(coolingDown ? palette.line : palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous))
            .opacity(coolingDown || isEnabled || isBusy ? 1 : 0.45)
    }
}
