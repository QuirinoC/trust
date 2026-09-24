import SwiftUI
import TrustCore

/// Pick a public handle after Sign in with Apple.
struct HandleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var handleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustWordmark().padding(.bottom, 30)
                TrustEyebrow(text: "Your profile", color: palette.accent)
                    .padding(.bottom, 8)
                Text(TrustCopy.yourHandle)
                    .font(TrustTheme.display(32))
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(TrustCopy.handleIntro)
                    .trustFont(16)
                    .lineSpacing(3)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 22)

                TrustCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 16) {
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
                            .frame(minHeight: 52)
                            .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                        }

                        Text(TrustCopy.handleRules)
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task { await model.completeOnboarding() }
                        } label: {
                            HStack(spacing: 8) {
                                if model.isOnboardingBusy { ProgressView().tint(palette.accentOn) }
                                Text(TrustCopy.continueAction)
                            }
                        }
                        .buttonStyle(TrustFilledButtonStyle())
                        .disabled(model.isOnboardingBusy || !model.onboardingHandleIsValid || model.handleAvailability == false)

                        if let notice = model.onboardingNotice, !notice.isEmpty {
                            Text(notice)
                                .trustFont(13)
                                .foregroundStyle(palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
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
        .onAppear { handleFocused = true }
    }

    private var handleBinding: Binding<String> {
        Binding(get: { model.onboardingHandle }, set: { model.setOnboardingHandle($0) })
    }

    private var handleHint: String? {
        switch TrustHandle.status(of: model.onboardingHandle) {
        case .reserved: return TrustCopy.handleReserved
        case .invalid: return nil
        case .valid:
            if model.handleAvailability == true { return TrustCopy.handleAvailable }
            if model.handleAvailability == false { return TrustCopy.handleTaken }
            return nil
        }
    }
}
