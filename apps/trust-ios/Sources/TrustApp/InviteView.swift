import SwiftUI
import TrustCore

/// Add someone from Sharing: create a link to send or accept a code explicitly.
struct AddSomeoneSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var phoneFocused: Bool
    @FocusState private var codeFocused: Bool
    @State private var expanded = false

    private var formVisible: Bool {
        expanded
            || model.pendingInviteCode != nil
            || model.phoneInviteCode != nil
            || !model.inviteCodeDraft.trimmingCharacters(in: .whitespaces).isEmpty
            || model.inviteNotice != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expanded.toggle()
            } label: {
                Label(TrustCopy.addSomeone, systemImage: "plus")
            }
            .buttonStyle(TrustOutlineButtonStyle(compact: true))
            .accessibilityIdentifier("add-someone-button")

            if formVisible {
                TrustCard(fill: palette.surface) {
                    VStack(alignment: .leading, spacing: 11) {
                        TrustSectionHeading("Send an invite")
                        Text("Create a link for them to accept. They join before either of you shares.")
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            TextField(TrustCopy.phonePlaceholder, text: $model.addPhoneDraft)
                                .textFieldStyle(TrustTextFieldStyle())
                                .focused($phoneFocused)
                                .textContentType(.telephoneNumber)
                                .keyboardType(.phonePad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .onSubmit { model.addPersonByPhone() }
                                .accessibilityLabel(TrustCopy.phoneNumber)
                                .accessibilityIdentifier("add-phone")
                                .simultaneousGesture(TapGesture().onEnded { phoneFocused = true })
                            Button {
                                phoneFocused = false
                                model.addPersonByPhone()
                            } label: {
                                if model.isAddingByPhone {
                                    ProgressView().tint(palette.accentOn)
                                } else {
                                    Text("Create invite")
                                }
                            }
                            .buttonStyle(TrustFilledButtonStyle(expand: false))
                            .disabled(model.addPhoneDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAddingByPhone)
                            .accessibilityIdentifier("add-phone-button")
                        }

                        if let code = model.phoneInviteCode ?? model.pendingInviteCode {
                            inviteLink(code)
                        } else {
                            Button {
                                model.createInvite()
                            } label: {
                                Label("Create invite link", systemImage: "link")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            .accessibilityIdentifier("create-invite-button")
                        }

                        if let notice = model.inviteNotice {
                            Text(notice)
                                .trustFont(13)
                                .foregroundStyle(palette.muted)
                                .accessibilityIdentifier("invite-notice")
                        }
                    }
                }

                TrustCard(fill: palette.surface) {
                    VStack(alignment: .leading, spacing: 11) {
                        TrustSectionHeading("Have an invite code?")
                        Text("Review the code, then tap Join to accept the invitation.")
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            TextField(TrustCopy.codePlaceholder, text: $model.inviteCodeDraft)
                                .textFieldStyle(TrustTextFieldStyle())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .submitLabel(.join)
                                .focused($codeFocused)
                                .onSubmit { model.joinInvite() }
                                .accessibilityLabel(TrustCopy.enterACode)
                                .accessibilityIdentifier("invite-code")
                                .simultaneousGesture(TapGesture().onEnded { codeFocused = true })
                            Button {
                                codeFocused = false
                                model.joinInvite()
                            } label: {
                                if model.isJoining {
                                    ProgressView().tint(palette.accentOn)
                                } else {
                                    Text(TrustCopy.join)
                                }
                            }
                            .buttonStyle(TrustFilledButtonStyle(expand: false))
                            .disabled(model.inviteCodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isJoining)
                            .accessibilityIdentifier("join-invite-button")
                        }
                    }
                }
            }
        }
    }

    private func inviteLink(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(code)
                .font(TrustTheme.mono(20))
                .tracking(3)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .accessibilityIdentifier("invite-code-value")
            ShareLink(item: TrustCopy.inviteMessage(code: code)) {
                Label(TrustCopy.shareInviteLink, systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrustFilledButtonStyle())
            .accessibilityIdentifier("share-invite-link")
        }
    }
}
