import SwiftUI
import TrustCore

/// Pick a public handle after Sign in with Apple.
struct HandleView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var handleFocused: Bool
    @State private var showingAvatarPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustWordmark().padding(.bottom, 30)
                TrustEyebrow(text: TrustCopy.yourProfile, color: palette.accent)
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

                Button { showingAvatarPicker = true } label: {
                    HStack(spacing: 13) {
                        TrustAvatar(name: model.you.displayName, seed: 0, size: 52, avatar: model.you.avatar, personID: model.you.id)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 17, weight: .semibold))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, palette.accent)
                                    .background(Circle().fill(palette.canvas).padding(-2))
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.you.avatar == nil ? TrustCopy.addProfilePicture : TrustCopy.changeProfilePicture)
                                .trustFont(14, weight: .semibold)
                                .foregroundStyle(palette.ink)
                            Text(TrustCopy.optionalAvatarIntro)
                                .trustFont(12)
                                .foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(14)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding-add-picture")
                .padding(.bottom, 18)

                TrustCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        TrustFieldLabel(title: TrustCopy.handle, hint: handleHint, hintColor: handleHintColor) {
                            HStack(spacing: 8) {
                                Text("@")
                                    .font(TrustTheme.ui(17, weight: .medium))
                                    .foregroundStyle(palette.muted)
                                TextField(TrustCopy.handlePlaceholder, text: handleBinding)
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
        .sheet(isPresented: $showingAvatarPicker) {
            ProfileAvatarPicker(onboarding: true)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
        }
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

    private var handleHintColor: Color {
        model.handleAvailability == false ? palette.danger : palette.positive
    }
}
