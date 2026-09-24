import SwiftUI
import TrustCore

/// Add someone, on Sharing. Link or a code. No essay.
struct AddSomeoneSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var codeFocused: Bool
    @State private var expanded = false

    private var formVisible: Bool {
        expanded
            || model.pendingInviteCode != nil
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

            if formVisible {
                HStack(spacing: 10) {
                    TextField(TrustCopy.phonePlaceholder, text: $model.addPhoneDraft)
                        .textFieldStyle(TrustTextFieldStyle())
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { model.addPersonByPhone() }
                        .accessibilityLabel(TrustCopy.phoneNumber)
                        .accessibilityIdentifier("add-phone")
                    Button {
                        model.addPersonByPhone()
                    } label: {
                        if model.isAddingByPhone {
                            ProgressView().tint(palette.accentOn)
                        } else {
                            Text(TrustCopy.add)
                        }
                    }
                    .buttonStyle(TrustFilledButtonStyle(expand: false))
                    .disabled(model.addPhoneDraft.trimmingCharacters(in: .whitespaces).isEmpty || model.isAddingByPhone)
                    .accessibilityIdentifier("add-phone-button")
                }

                if let code = model.pendingInviteCode {
                    Text(code)
                        .font(TrustTheme.mono(22))
                        .tracking(3)
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                    ShareLink(item: TrustCopy.inviteMessage(code: code)) {
                        Label(TrustCopy.shareInviteLink, systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                } else {
                    Button {
                        model.createInvite()
                    } label: {
                        Label(TrustCopy.createInvite, systemImage: "link")
                    }
                    .buttonStyle(TrustFilledButtonStyle())
                }

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
                    .disabled(model.inviteCodeDraft.trimmingCharacters(in: .whitespaces).isEmpty || model.isJoining)
                }

                if let notice = model.inviteNotice {
                    Text(notice)
                        .font(TrustTheme.ui(13))
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("invite-notice")
                }
            }
        }
    }
}
