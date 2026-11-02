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
            // Add sheet handles exact handle/phone lookup and eligible no-match links.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var handleFocused: Bool
    @State private var addScrollViewportHeight: CGFloat = 0
    @State private var showingCountryPicker = false
    @State private var countrySearch = ""
    private let addFieldScrollAnchor = "add-person-field-scroll-anchor"
    private let addLookupRecoveryScrollAnchor = "add-person-recovery-scroll-anchor"
    private let addLookupResultScrollAnchor = "add-person-result-scroll-anchor"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(TrustCopy.findYourPerson)
                            .trustFont(28, weight: .semibold)
                            .foregroundStyle(palette.ink)
                            .accessibilityIdentifier("add-person-heading")
                        Text(TrustCopy.addPersonExplanation)
                            .trustFont(15)
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("add-person-explanation")
                    }

                    Button { model.prepareShareInviteLink() } label: {
                        HStack(spacing: 8) {
                            if model.isPreparingConnectionInvite { ProgressView().tint(palette.accent) }
                            Text(TrustCopy.shareInviteLink)
                            Spacer(minLength: 0)
                            Image(systemName: "square.and.arrow.up").accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(TrustOutlineButtonStyle(compact: true))
                    .disabled(model.isPreparingConnectionInvite)
                    .accessibilityIdentifier("share-invite-link")

                    VStack(alignment: .leading, spacing: 8) {
                        if isPhoneDraft {
                            Button { showingCountryPicker = true } label: {
                                HStack(spacing: 8) {
                                    Text(model.connectionPhoneCountry.name)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Text(model.connectionPhoneCountry.displayCallingCode)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .semibold))
                                        .accessibilityHidden(true)
                                }
                                .trustFont(14, weight: .semibold)
                                .foregroundStyle(palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(TrustCopy.phoneCountryAccessibilityLabel(model.connectionPhoneCountry.name, callingCode: model.connectionPhoneCountry.displayCallingCode))
                            .accessibilityIdentifier("connection-phone-country")
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
                                        scrollFocusedFieldToBottom(using: scrollProxy)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(palette.muted)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(TrustCopy.clearField)
                                    .accessibilityIdentifier("clear-connection-lookup")
                                }
                            }
                            .padding(.horizontal, 18)
                            .frame(minHeight: 56)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.line, lineWidth: 1))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("connection-lookup-field")
                            if let hint = model.connectionLookupHint {
                                Text(hint)
                                    .trustFont(13)
                                    .foregroundStyle(palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 4)
                                    .accessibilityIdentifier("connection-lookup-hint")
                            }
                            if let phonePreview {
                                Text(phonePreview)
                                    .trustFont(12)
                                    .foregroundStyle(palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 4)
                                    .accessibilityIdentifier("connection-phone-preview")
                            }
                        }
                        Color.clear
                            // The measured scroll-to-bottom inset settles about 4pt short of
                            // the anchor on Duo, so reserve extra space to preserve the
                            // required 8pt visible clearance below the bordered field.
                            .frame(height: dynamicTypeSize.isAccessibilitySize ? 16 : 8)
                            .accessibilityHidden(true)
                    }
                    .id(addFieldScrollAnchor)

                    if let notice = model.connectionLookupNotice {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(notice)
                                .trustFont(13)
                                .foregroundStyle(palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("connection-lookup-notice")
                            if model.connectionLookupCanRetry {
                                Button { model.retryConnectionLookup() } label: {
                                    Text(TrustCopy.retry)
                                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                    .buttonStyle(TrustTextButtonStyle(color: palette.accent))
                                    .accessibilityIdentifier("retry-connection-lookup")
                            }
                        }
                        .id(addLookupRecoveryScrollAnchor)
                    }

                    if model.connectionRequiresPhoneVerification {
                        Button(TrustCopy.verifyNumber) { model.beginConnectionPhoneVerification() }
                            .buttonStyle(TrustOutlineButtonStyle(compact: true))
                            .accessibilityIdentifier("verify-number-for-connection")
                    }

                    if let result = model.connectionLookup {
                        lookupResult(result)
                            .id(addLookupResultScrollAnchor)
                            .transition(.opacity)
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
                                        Text(TrustCopy.shareInviteLink)
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
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: TrustTheme.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.connectionLookup?.relationship)
                    }
                    .accessibilityIdentifier("add-person-scroll")
                    .background(palette.paper)
                    .clipShape(Rectangle())
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        let previousHeight = addScrollViewportHeight
                        addScrollViewportHeight = height
                        if dynamicTypeSize.isAccessibilitySize,
                           handleFocused,
                           previousHeight > 0,
                           height < previousHeight - 1 {
                            scrollFocusedFieldToBottom(using: scrollProxy)
                        }
                    }
                    .onChange(of: model.connectionLookupNotice) { _, notice in
                        guard notice != nil else { return }
                        revealLookupFeedback(using: scrollProxy)
                    }
                    .onChange(of: model.connectionLookup?.relationship) { _, relationship in
                        guard relationship == "sent" else { return }
                        scrollToLookupResult(using: scrollProxy)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    HStack {
                        Spacer(minLength: 0)
                        cancelButton
                    }
                    .padding(.horizontal, TrustTheme.gutter)
                    .frame(maxWidth: .infinity)
                    // Keep at least 8pt between the focused lookup field and
                    // the 44pt Close target after Duo resizes the keyboard viewport.
                    .frame(height: 60)
                    .background(palette.paper)
                }
            }
            .background(palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !dynamicTypeSize.isAccessibilitySize {
                    ToolbarItem(placement: .cancellationAction) {
                        cancelButton
                    }
                }
            }
        }
        .task {
            guard !model.isScreenshotLaunch else { return }
            model.setConnectionHandleDraft("")
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
        .sheet(isPresented: $showingCountryPicker) { countryPicker }
    }

    private var isPhoneDraft: Bool {
        let value = model.connectionHandleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || value.first?.isNumber == true || value.first == "+"
    }

    private var phonePreview: String? {
        let raw = model.connectionHandleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.first?.isNumber == true || raw.first == "+",
              let query = PersonLookupQuery.parse(raw, region: model.connectionPhoneCountry.code),
              case .phone(let phone, _) = query else { return nil }
        if phone.hasPrefix("+") { return phone }
        return "\(model.connectionPhoneCountry.displayCallingCode) \(phone.filter(\.isNumber))"
    }

    private var countryPicker: some View {
        NavigationStack {
            List(TrustPhoneCountry.all
                .filter { TrustPhoneCountry.matches($0, query: countrySearch) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { country in
                    Button {
                        model.setConnectionPhoneCountry(country)
                        showingCountryPicker = false
                    } label: {
                        HStack {
                            Text(country.name)
                            Spacer()
                            Text(country.displayCallingCode).foregroundStyle(palette.muted)
                            if country == model.connectionPhoneCountry {
                                Image(systemName: "checkmark").foregroundStyle(palette.accent)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $countrySearch, prompt: TrustCopy.phoneCountrySearch)
                .navigationTitle(TrustCopy.phoneCountryCodeTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(TrustCopy.done) { showingCountryPicker = false }
                    }
                }
        }
    }

    private func scrollFocusedFieldToBottom(using proxy: ScrollViewProxy) {
        guard dynamicTypeSize.isAccessibilitySize else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard handleFocused else { return }
            proxy.scrollTo(addFieldScrollAnchor, anchor: .bottom)
        }
    }

    private func revealLookupFeedback(using proxy: ScrollViewProxy) {
        if model.connectionLookup?.relationship == "sent" {
            scrollToLookupResult(using: proxy)
            return
        }
        // Keep the error and its Retry target above the keyboard after SwiftUI
        // finishes both the keyboard resize and the pending lookup transition.
        // The later passes are scroll-only and leave the lookup field focused.
        for delay in [0.18, 0.45, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard model.showingAddPersonSheet,
                      model.connectionLookupNotice != nil else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo(addLookupRecoveryScrollAnchor, anchor: .bottom)
                }
            }
        }
    }

    private func scrollToLookupResult(using proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard model.showingAddPersonSheet else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                proxy.scrollTo(addLookupResultScrollAnchor, anchor: .bottom)
            }
        }
    }

    private var cancelButton: some View {
        Button {
            handleFocused = false
            model.showingAddPersonSheet = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 36, height: 36)
                .background(palette.surface, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(TrustCopy.cancel)
        .accessibilityIdentifier("cancel-add-person")
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
                .id(result.relationship)
                .transition(.opacity)
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
            Button {
                guard let id = result.requestId else { return }
                model.acceptConnectionRequest(id: id)
            } label: {
                HStack(spacing: 8) {
                    Text(TrustCopy.acceptRequest)
                    if let id = result.requestId, model.actingOnConnectionRequestIDs.contains(id) {
                        ProgressView().tint(palette.accentOn)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(TrustFilledButtonStyle())
            .disabled(result.requestId == nil || (result.requestId.map { model.actingOnConnectionRequestIDs.contains($0) } ?? false))
            .accessibilityIdentifier("accept-looked-up-request")
        default:
            Button {
                model.sendConnectionRequest()
            } label: {
                HStack(spacing: 8) {
                    Text(TrustCopy.sendRequest)
                    if model.isSendingConnectionRequest {
                        ProgressView().tint(palette.accentOn)
                            .accessibilityHidden(true)
                    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    Button { Task { await model.refreshConnectionRequests() } } label: {
                        Text(TrustCopy.retry)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(TrustTextButtonStyle(color: palette.accent))
                        .accessibilityIdentifier("retry-connection-requests")
                }
                .padding(.vertical, 10)
                .accessibilityIdentifier("connection-requests-error")
            }

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

            if model.connectionRequests.incoming.isEmpty && model.connectionRequests.sent.isEmpty
                && !model.isLoadingConnectionRequests && model.connectionRequestsNotice == nil {
                Text(TrustCopy.noConnectionRequests)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                    .frame(minHeight: 42, alignment: .leading)
                    .accessibilityIdentifier("no-connection-requests")
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.connectionRequests.incoming.map(\.id))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.connectionRequests.sent.map(\.id))
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
                if model.actingOnConnectionRequestIDs.contains(request.id) {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityHidden(true)
                    Text(TrustCopy.pending)
                        .trustFont(12, weight: .medium)
                        .foregroundStyle(palette.muted)
                } else if !incoming {
                    Text(TrustCopy.pending)
                        .trustFont(12, weight: .medium)
                        .foregroundStyle(palette.muted)
                }
            }

            HStack(spacing: 10) {
                if incoming {
                    Button(TrustCopy.acceptRequest) { model.acceptConnectionRequest(request) }
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

            if let error = model.connectionRequestActionErrors[request.id] {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error)
                        .trustFont(12)
                        .foregroundStyle(palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("connection-request-error-\(request.otherParty.handle)")
                    Button { model.retryConnectionRequestAction(id: request.id) } label: {
                        Text(TrustCopy.retry)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(TrustTextButtonStyle(color: palette.accent))
                        .accessibilityIdentifier("retry-connection-request-\(request.otherParty.handle)")
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-request-\(incoming ? "incoming" : "sent")-\(request.otherParty.handle)")
        .transition(.opacity)
    }
}
