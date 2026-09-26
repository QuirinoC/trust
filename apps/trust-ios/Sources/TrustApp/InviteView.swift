import SwiftUI
import TrustCore

/// The regular add flow begins with an exact public handle lookup. No private Apple
/// profile data is returned or shown before the two people connect.
struct AddSomeoneSection: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.showingAddPersonSheet = true
            } label: {
                Label(TrustCopy.addSomeone, systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(TrustOutlineButtonStyle(compact: true))
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
                VStack(alignment: .leading, spacing: 18) {
                    Text(TrustCopy.addPersonExplanation)
                        .trustFont(14)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 9) {
                            TextField(TrustCopy.theirHandle, text: Binding(
                                get: { model.connectionHandleDraft },
                                set: { model.setConnectionHandleDraft($0) }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                        .submitLabel(.search)
                        .focused($handleFocused)
                        .onSubmit {
                            handleFocused = false
                            model.lookupConnectionHandle()
                        }
                        .accessibilityIdentifier("connection-handle")
                            Button {
                                handleFocused = false
                                model.lookupConnectionHandle()
                            } label: {
                                if model.isLookingUpConnection {
                                    ProgressView().tint(palette.accentOn)
                                } else {
                                    Text(TrustCopy.search)
                                }
                            }
                            .buttonStyle(TrustFilledButtonStyle(expand: false))
                            .disabled(model.isLookingUpConnection || model.connectionHandleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("lookup-connection-handle")
                        }
                        .padding(12)
                        .frame(minHeight: 54)
                        .background(palette.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
                        Text(TrustCopy.handleLookupHelper)
                            .trustFont(12)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
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
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.top, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: TrustTheme.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(TrustCopy.cancel) { model.showingAddPersonSheet = false }
                        .accessibilityIdentifier("cancel-add-person")
                }
                ToolbarItem(placement: .principal) {
                    Text(TrustCopy.addSomeone)
                        .trustFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
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
    }

    @ViewBuilder
    private func lookupResult(_ result: PersonLookupPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HandleInitials(handle: result.handle, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("@\(result.handle)")
                        .trustFont(16, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .accessibilityIdentifier("connection-lookup-handle")
                    Text(TrustCopy.connectionLookupCaption)
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 4)
            }
            action(for: result)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous))
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
