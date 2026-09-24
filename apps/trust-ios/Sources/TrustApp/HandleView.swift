import SwiftUI
import TrustCore

/// A2 Handle — `@handle` once after the first Sign in with Apple (`PUT /me/handle`).
struct HandleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var handleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustWordmark()
                    .padding(.bottom, 28)

                Text(TrustCopy.yourHandle)
                    .font(TrustTheme.display(38))
                    .tracking(-1)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                TrustRule()
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                Text(TrustCopy.handleIntro)
                    .trustFont(15)
                    .lineSpacing(3)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 18) {
                    TrustFieldLabel(title: TrustCopy.handle, hint: handleHint) {
                        HStack(spacing: 8) {
                            Text("@")
                                .font(TrustTheme.ui(17, weight: .medium))
                                .foregroundStyle(palette.muted)
                            TextField("jordan", text: handleBinding)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .submitLabel(.continue)
                                .font(TrustTheme.ui(17))
                                .foregroundStyle(palette.ink)
                                .focused($handleFocused)
                                .onSubmit { Task { await model.completeOnboarding() } }
                        }
                        .padding(14)
                        .background(palette.paper)
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color(hex: 0xDEDFD5), lineWidth: 1))
                    }

                    Text(TrustCopy.handleRules)
                        .font(TrustTheme.ui(13))
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(TrustCopy.continueAction) {
                        Task { await model.completeOnboarding() }
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                    .disabled(model.isOnboardingBusy || !model.onboardingHandleIsValid || model.handleAvailability == false)

                    if let notice = model.onboardingNotice, !notice.isEmpty {
                        Text(notice)
                            .font(TrustTheme.ui(13))
                            .foregroundStyle(palette.accent)
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
        .onAppear { handleFocused = true }
    }

    private var handleBinding: Binding<String> {
        Binding(
            get: { model.onboardingHandle },
            set: { model.setOnboardingHandle($0) }
        )
    }

    private var handleHint: String? {
        switch TrustHandle.status(of: model.onboardingHandle) {
        case .reserved:
            return TrustCopy.handleReserved
        case .invalid:
            return nil
        case .valid:
            if model.handleAvailability == true { return TrustCopy.handleAvailable }
            if model.handleAvailability == false { return TrustCopy.handleTaken }
            return nil
        }
    }
}
