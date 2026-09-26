import SwiftUI
import TrustCore
import UIKit

/// Add by exact public handle or complete phone number. The phone is used only for
/// this lookup and is never included in an invitation.
struct AddSomeoneSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.showingAddPersonSheet = true
            } label: {
                Label(TrustCopy.addSomeone, systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TrustFilledButtonStyle())
            .accessibilityIdentifier("add-someone-button")

            // Old invitation links still open a direct, explicit accept card. The
            // ordinary Add sheet has no code, link, or phone paths.
            if model.linkedInviteCode != nil {
                TrustCard(fill: palette.surface) {
                    VStack(alignment: .leading, spacing: 10) {
                        TrustSectionHeading(TrustCopy.invitationToConnect)
                        Text(TrustCopy.invitationAcceptBody)
                            .trustFont(13)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            model.joinInvite()
                        } label: {
                            Text(TrustCopy.acceptInvitation)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TrustFilledButtonStyle())
                        .disabled(model.isJoining)
                        .accessibilityIdentifier("accept-invite-button")
                        Button(TrustCopy.later) { model.dismissLinkedInvite() }
                            .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            .accessibilityIdentifier("dismiss-invite-button")
                        if model.connectionRequiresPhoneVerification {
                            Button(TrustCopy.verifyNumber) { model.beginConnectionPhoneVerification() }
                                .buttonStyle(TrustOutlineButtonStyle(compact: true))
                                .accessibilityIdentifier("verify-number-for-connection")
                        }
                        if let notice = model.inviteNotice {
                            Text(notice)
                                .trustFont(13)
                                .foregroundStyle(palette.muted)
                                .accessibilityIdentifier("invite-notice")
                        }
                    }
                }
            }
        }
    }
}

struct AddPersonSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @FocusState private var handleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(TrustCopy.findYourPerson)
                            .trustFont(27, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .accessibilityIdentifier("add-person-heading")
                        Text(TrustCopy.addPersonExplanation)
                            .trustFont(15)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("add-person-explanation")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .accessibilityHidden(true)
                            TextField(TrustCopy.addPersonLookupPlaceholder, text: Binding(
                                get: { model.connectionHandleDraft },
                                set: { model.setConnectionHandleDraft($0) }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.default)
                            .submitLabel(.done)
                            .onSubmit {
                                model.submitConnectionLookup()
                                handleFocused = false
                            }
                            .focused($handleFocused)
                            .accessibilityIdentifier("connection-handle")
                            if model.isLookingUpConnection {
                                ProgressView()
                                    .tint(palette.accent)
                                    .accessibilityHidden(true)
                            }
                            if !model.connectionHandleDraft.isEmpty {
                                Button {
                                    model.setConnectionHandleDraft("")
                                    handleFocused = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(palette.muted)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(TrustCopy.clearField)
                                .accessibilityIdentifier("clear-connection-lookup")
                            }
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 56)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.line, lineWidth: 1))
                        if let hint = model.connectionLookupHint {
                            Text(hint)
                                .trustFont(13)
                                .foregroundStyle(palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                                .accessibilityIdentifier("connection-lookup-hint")
                        }
                    }

                    if let notice = model.connectionLookupNotice {
                        Text(notice)
                            .trustFont(13)
                            .foregroundStyle(palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("connection-lookup-notice")
                    }

                    if model.connectionRequiresPhoneVerification {
                        Button(TrustCopy.verifyNumber) { model.beginConnectionPhoneVerification() }
                            .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            .accessibilityIdentifier("verify-number-for-connection")
                    }

                    if let result = model.connectionLookup {
                        lookupResult(result)
                    }
                    if model.connectionLookupIsNoMatch {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.system(size: 19, weight: .regular))
                                    .foregroundStyle(palette.muted)
                                    .accessibilityHidden(true)
                                Text(TrustCopy.lookupNoMatch)
                                    .trustFont(17, weight: .semibold)
                                    .foregroundStyle(palette.ink)
                                    .accessibilityIdentifier("connection-lookup-no-match")
                            }
                            if model.connectionLookupCanInvite {
                                Button {
                                    model.prepareConnectionInvite()
                                } label: {
                                    HStack(spacing: 8) {
                                        if model.isPreparingConnectionInvite {
                                            ProgressView().tint(palette.accentOn)
                                        }
                                        Text(TrustCopy.inviteToTrust)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(TrustFilledButtonStyle())
                                .accessibilityIdentifier("invite-to-trust")
                                .disabled(model.isPreparingConnectionInvite)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: TrustTheme.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.showingAddPersonSheet = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .frame(width: 36, height: 36)
                            .background(palette.surface, in: Circle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityLabel(TrustCopy.cancel)
                        .accessibilityIdentifier("cancel-add-person")
                }
            }
        }
        .task {
            model.setConnectionHandleDraft("")
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            handleFocused = true
            Task { await model.refreshConnectionRequests() }
        }
        .sheet(isPresented: Binding(
            get: { model.inviteShareText != nil },
            set: { if !$0 { model.dismissConnectionInviteShare() } }
        )) {
            if let text = model.inviteShareText {
                ActivityShareSheet(items: [text]) {
                    model.dismissConnectionInviteShare()
                }
            }
        }
    }

    @ViewBuilder
    private func lookupResult(_ result: PersonLookupPayload) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                LookupAvatar(result: result, size: 52)
                Text("@\(result.handle)")
                    .trustFont(19, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .accessibilityIdentifier("connection-lookup-handle")
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 4)

            TrustHairline()

            action(for: result)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-lookup-result")
    }

    @ViewBuilder
    private func action(for result: PersonLookupPayload) -> some View {
        switch result.relationship {
        case "connected":
            Text(TrustCopy.connected)
                .trustFont(13, weight: .medium)
                .foregroundStyle(palette.muted)
                .accessibilityIdentifier("connection-lookup-connected")
        case "sent":
            Text(TrustCopy.requestSent)
                .trustFont(13, weight: .medium)
                .foregroundStyle(palette.muted)
                .accessibilityIdentifier("connection-lookup-sent")
        case "incoming":
            Button(TrustCopy.acceptRequest) {
                guard let id = result.requestId else { return }
                model.acceptConnectionRequest(id: id)
            }
            .buttonStyle(TrustFilledButtonStyle())
            .disabled(result.requestId == nil || (result.requestId.map { model.actingOnConnectionRequestIDs.contains($0) } ?? false))
            .accessibilityIdentifier("accept-looked-up-request")
        default:
            Button {
                model.sendConnectionRequest()
            } label: {
                if model.isSendingConnectionRequest {
                    ProgressView().tint(palette.accentOn)
                } else {
                    Text(TrustCopy.sendRequest)
                }
            }
            .buttonStyle(TrustFilledButtonStyle())
            .disabled(model.isSendingConnectionRequest)
            .accessibilityIdentifier("send-connection-request")
        }
    }
}

private struct LookupAvatar: View {
    let result: PersonLookupPayload
    let size: CGFloat
    @Environment(\.trustPalette) private var palette

    private var photo: UIImage? {
        guard let encoded = result.photoThumbnailBase64,
              let data = Data(base64Encoded: encoded),
              data.count <= 20 * 1024 else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        Group {
            if let photo {
                ZStack {
                    Circle().fill(palette.paper)
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipped()
                }
            } else if let avatar = result.avatar, avatar.knownPresetID != nil {
                TrustAvatar(name: result.handle, size: size, avatar: avatar, personID: result.accountId)
            } else {
                ZStack {
                    Circle().fill(palette.accent)
                    HandleInitials(handle: result.handle, size: size)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(TrustCopy.profilePicture)
        .accessibilityIdentifier("connection-lookup-avatar")
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onDismiss: () -> Void

    final class Coordinator {
        var onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { [weak coordinator = context.coordinator] _, _, _, _ in
            Task { @MainActor in coordinator?.onDismiss() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }
}

/// Initials are derived only from a public handle, never from the private Apple name.
struct HandleInitials: View {
    let handle: String
    var size: CGFloat = 40
    @Environment(\.trustPalette) private var palette

    private var initials: String {
        let pieces = handle.split(whereSeparator: { $0 == "_" || $0 == "." || $0 == "-" })
        if pieces.count > 1 {
            return pieces.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(handle.prefix(2)).uppercased()
    }

    var body: some View {
        Text(initials)
            .trustFont(14, weight: .semibold)
            .foregroundStyle(palette.accentOn)
            .frame(width: size, height: size)
            .background(Circle().fill(palette.accent))
            .accessibilityLabel(TrustCopy.handleInitialsAccessibility(handle))
    }
}


struct ConnectionRequestsSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrustSectionHeading(TrustCopy.connectionRequests)
                .padding(.bottom, 4)

            if model.isLoadingConnectionRequests && model.connectionRequests.incoming.isEmpty && model.connectionRequests.sent.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().tint(palette.accent)
                    Text(TrustCopy.loadingRequests)
                        .trustFont(13)
                        .foregroundStyle(palette.muted)
                }
                .frame(minHeight: 48, alignment: .leading)
                .accessibilityIdentifier("connection-requests-loading")
            }

            if let notice = model.connectionRequestsNotice {
                VStack(alignment: .leading, spacing: 8) {
                    Text(notice)
                        .trustFont(13)
                        .foregroundStyle(palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(TrustCopy.retry) { Task { await model.refreshConnectionRequests() } }
                        .buttonStyle(TrustTextButtonStyle(color: palette.accent))
                        .accessibilityIdentifier("retry-connection-requests")
                }
                .padding(.vertical, 10)
                .accessibilityIdentifier("connection-requests-error")
            } else {
                if !model.connectionRequests.incoming.isEmpty {
                    Text(TrustCopy.incomingRequests)
                        .trustFont(12, weight: .semibold)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(model.connectionRequests.incoming) { request in
                        requestRow(request, incoming: true)
                        TrustRowDivider()
                    }
                }

                if !model.connectionRequests.sent.isEmpty {
                    Text(TrustCopy.sentRequests)
                        .trustFont(12, weight: .semibold)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(model.connectionRequests.sent) { request in
                        requestRow(request, incoming: false)
                        TrustRowDivider()
                    }
                }

                if model.connectionRequests.incoming.isEmpty && model.connectionRequests.sent.isEmpty && !model.isLoadingConnectionRequests {
                    Text(TrustCopy.noConnectionRequests)
                        .trustFont(13)
                        .foregroundStyle(palette.muted)
                        .frame(minHeight: 42, alignment: .leading)
                        .accessibilityIdentifier("no-connection-requests")
                }
            }

            if model.connectionRequiresPhoneVerification {
                Button(TrustCopy.verifyNumber) { model.beginConnectionPhoneVerification() }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .padding(.top, 6)
                    .accessibilityIdentifier("verify-number-for-connection")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-requests-section")
    }

    private func requestRow(_ request: ConnectionRequestDTO, incoming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HandleInitials(handle: request.otherParty.handle, size: 38)
                Text("@\(request.otherParty.handle)")
                    .trustFont(14, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .accessibilityIdentifier("connection-request-handle-\(request.otherParty.handle)")
                Spacer(minLength: 4)
                if !incoming {
                    Text(TrustCopy.pending)
                        .trustFont(12, weight: .medium)
                        .foregroundStyle(palette.muted)
                }
            }

            HStack(spacing: 10) {
                if incoming {
                    Button {
                        model.acceptConnectionRequest(request)
                    } label: {
                        if model.actingOnConnectionRequestIDs.contains(request.id) {
                            ProgressView().tint(palette.accentOn)
                        } else {
                            Text(TrustCopy.acceptRequest)
                        }
                    }
                        .buttonStyle(TrustFilledButtonStyle(expand: false))
                        .disabled(model.actingOnConnectionRequestIDs.contains(request.id))
                        .accessibilityIdentifier("accept-connection-request-\(request.otherParty.handle)")
                    Button(TrustCopy.declineRequest) { model.declineConnectionRequest(request) }
                        .buttonStyle(TrustOutlineButtonStyle(compact: true))
                        .disabled(model.actingOnConnectionRequestIDs.contains(request.id))
                        .accessibilityIdentifier("decline-connection-request-\(request.otherParty.handle)")
                } else {
                    Button(TrustCopy.cancelRequest) { model.cancelConnectionRequest(request) }
                        .buttonStyle(TrustTextButtonStyle(color: palette.muted))
                        .disabled(model.actingOnConnectionRequestIDs.contains(request.id))
                        .accessibilityIdentifier("cancel-connection-request-\(request.otherParty.handle)")
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-request-\(incoming ? "incoming" : "sent")-\(request.otherParty.handle)")
    }
}
