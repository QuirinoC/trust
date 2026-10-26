import SwiftUI
import TrustCore

/// Sharing — compact Name / Off / Sealed / Always rows, with Pause and Remove in the secondary menu.
struct SharingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeConfirmation: SharingConfirmation?
    @State private var showingHomeStatus = false
    @State private var pausePresentationDetent: PresentationDetent = .height(420)

    private enum SharingConfirmation: Equatable {
        case stopSharing(personID: UUID, name: String)
        case removePerson(personID: UUID, name: String)
        case stopAll
    }

    private var confirmationTitle: String {
        switch activeConfirmation {
        case .some(.stopSharing(_, let name)): return TrustCopy.stopSharingConfirm(name: name)
        case .some(.removePerson(_, let name)): return TrustCopy.removePersonConfirm(name: name)
        case .some(.stopAll): return TrustCopy.stopAllConfirm
        case .none: return ""
        }
    }

    private var confirmationMessage: String {
        switch activeConfirmation {
        case .some(.stopSharing(_, _)): return TrustCopy.stopSharingConfirmBody
        case .some(.removePerson(_, _)): return TrustCopy.removePersonConfirmBody
        case .some(.stopAll): return TrustCopy.stopAllConfirmBody
        case .none: return ""
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 760
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TrustPageTitle(text: TrustCopy.sharing)
                        .padding(.top, 20)

                    Text(TrustCopy.sharingIntro)
                        .trustFont(14)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .accessibilityIdentifier("sharing-intro")

                    AddSomeoneSection()
                        .padding(.top, 16)

                    if !model.connectionRequests.incoming.isEmpty
                        || !model.connectionRequests.sent.isEmpty
                        || model.isLoadingConnectionRequests
                        || model.connectionRequestsNotice != nil
                        || model.connectionRequiresPhoneVerification {
                        ConnectionRequestsSection()
                            .padding(.top, 18)
                            .transition(.opacity)
                    }

                    if !model.circle.isEmpty {
                        TrustSectionHeading(TrustCopy.people)
                            .padding(.top, 22)
                            .padding(.bottom, 4)
                        ForEach(model.circle) { member in
                            VStack(spacing: 0) {
                                OutboundRow(
                                    member: member,
                                    seed: seed(member),
                                    compact: geometry.size.width < 430,
                                    onPause: {
                                        model.tracePausePresentation("menu callback")
                                        pausePresentationDetent = dynamicTypeSize.isAccessibilitySize ? .large : .height(420)
                                        model.pauseSheetPersonID = member.id
                                    },
                                    onStopSharing: { activeConfirmation = .stopSharing(personID: member.id, name: member.firstName) },
                                    onRemove: { activeConfirmation = .removePerson(personID: member.id, name: member.firstName) }
                                )
                                TrustRowDivider()
                            }
                            .transition(.opacity)
                        }

                    }

                    presenceSection
                        .padding(.top, 22)

                    if model.outboundActiveCount > 0 {
                        Button(TrustCopy.stopAll) { activeConfirmation = .stopAll }
                            .buttonStyle(TrustTextButtonStyle(color: palette.danger))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 22)
                            .accessibilityIdentifier("stop-all-sharing")
                    }
                }
                .padding(.horizontal, TrustTheme.gutter)
                .padding(.bottom, 28)
                // Keep the sharing controls in a readable column, centered in the
                // full open-Duo canvas instead of anchoring them to the right edge.
                .frame(maxWidth: isWide ? 760 : TrustTheme.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                // Keep the short, empty Sharing state scrollable enough for the native
                // pull-to-refresh gesture to work before anyone has been added.
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .accessibilityIdentifier("sharing-scroll")
            .refreshable {
                await model.refresh()
            }
            // Keep oversized Dynamic Type content inside the scroll viewport instead
            // of drawing underneath the status bar while the page is scrolled.
            // The background added after this clip still extends through the top inset.
            .clipShape(Rectangle())
            .background(palette.paper.ignoresSafeArea())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.connectionRequests.incoming.map(\.id))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.connectionRequests.sent.map(\.id))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.circle.map(\.id))
            .sheet(isPresented: Binding(
                get: { model.pauseSheetPersonID != nil },
                set: {
                    if !$0 {
                        model.tracePausePresentation("sheet binding dismissed")
                        model.pauseSheetPersonID = nil
                    }
                }
            )) {
                if let personID = model.pauseSheetPersonID {
                    PauseSharingSheet(personID: personID) {
                        model.pauseSheetPersonID = nil
                    }
                    .environmentObject(model)
                    .environment(\.trustPalette, palette)
                    .presentationDetents([.height(420), .large], selection: $pausePresentationDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackground(palette.paper)
                    .onAppear {
                        model.tracePausePresentation("sheet appeared")
                    }
                }
            }
        .alert(
            confirmationTitle,
            isPresented: Binding(
                get: { activeConfirmation != nil },
                set: { if !$0 { activeConfirmation = nil } }
            )
        ) {
            switch activeConfirmation {
            case .some(.stopSharing(let personID, _)):
                Button(TrustCopy.stopSharing, role: .destructive) { model.stopSharing(personID: personID) }
                    .accessibilityIdentifier("stop-sharing-confirm")
                Button(TrustCopy.cancel, role: .cancel) {}
            case .some(.removePerson(let personID, _)):
                Button(TrustCopy.removePerson, role: .destructive) { model.removePerson(personID: personID) }
                    .accessibilityIdentifier("remove-person-confirm")
                Button(TrustCopy.cancel, role: .cancel) {}
            case .some(.stopAll):
                Button(TrustCopy.stopAll, role: .destructive) { model.stopAll() }
                    .accessibilityIdentifier("stop-all-sharing-confirm")
                Button(TrustCopy.cancel, role: .cancel) {}
            case .none:
                Button(TrustCopy.cancel, role: .cancel) {}
            }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(TrustCopy.homeStatus, isPresented: $showingHomeStatus, titleVisibility: .visible) {
            ForEach(HomePresenceKind.triad, id: \.rawValue) { kind in
                Button(kind.label) { model.setPresence(kind) }
                    .accessibilityIdentifier("set-home-status-\(kind.rawValue)")
            }
            Button(TrustCopy.cancel, role: .cancel) {}
        } message: {
            Text(TrustCopy.sharingPresenceExplanation)
        }
        }
    }

    private func seed(_ member: TrustedPerson) -> Int {
        model.circle.firstIndex { $0.id == member.id } ?? 0
    }

    private var presenceSection: some View {
        Button {
            showingHomeStatus = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "house")
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
                Text(TrustCopy.homeStatus)
                    .trustFont(14, weight: .medium)
                    .foregroundStyle(palette.ink)
                Spacer()
                Text(model.myPresence.label)
                    .trustFont(13)
                    .foregroundStyle(palette.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous).fill(palette.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-status-control")
    }
}

/// Connected-person sharing row. Pause is timed; Stop sharing confirms before setting Off.
struct OutboundRow: View {
    let member: TrustedPerson
    var seed: Int = 0
    var compact = false
    let onPause: () -> Void
    let onStopSharing: () -> Void
    let onRemove: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionNamespace
    @State private var showingPresenceGrantDetails = false

    private enum Mode: Hashable { case off, sealed, always }

    private var presentation: SharePresentation {
        model.shareState(for: member.id).presentation(at: Date())
    }

    private var selection: Mode? {
        switch presentation {
        case .off: return .off
        case .untilTheyLook: return .sealed
        case .always: return .always
        case .paused: return nil
        }
    }

    private var summary: String {
        switch presentation {
        case .off: return TrustCopy.notSharing
        case .untilTheyLook: return TrustCopy.sealed
        case .always: return TrustCopy.always
        case .paused(let ends, let restores):
            let time = TrustCopy.pauseEndDateTime(ends)
            let mode = restores == .always ? TrustCopy.always : TrustCopy.sealed
            return TrustCopy.pauseUntil(time: time, mode: mode)
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize >= .xxxLarge {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        personLabel
                        Spacer(minLength: 4)
                        actionsMenu
                    }
                    modeControl
                }
            } else {
                HStack(spacing: compact ? 3 : 8) {
                    personLabel
                        .frame(minWidth: compact ? 60 : 88, maxWidth: .infinity, alignment: .leading)
                    modeControl
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: compact ? 176 : 190)
                        .layoutPriority(1)
                    actionsMenu
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 15 : 9)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sharing-mode-group-\(member.firstName.lowercased())")
        .alert(TrustCopy.presenceGrantDetails, isPresented: $showingPresenceGrantDetails) {
            Button(TrustCopy.close, role: .cancel) {}
                .accessibilityIdentifier("presence-grant-details-close")
        } message: {
            Text(TrustCopy.presenceGrantExplanation)
        }
    }

    private var personLabel: some View {
        HStack(spacing: 9) {
            if !compact {
                TrustAvatar(name: member.person.displayName, seed: seed, size: 40, avatar: member.person.avatar, personID: member.id)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(member.person.displayName)
                        .trustFont(14, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(dynamicTypeSize >= .xxLarge ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isUpdatingShare(personID: member.id) {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityHidden(true)
                    }
                }
                if model.isUpdatingShare(personID: member.id) {
                    Text(TrustCopy.pending)
                        .trustFont(11)
                        .foregroundStyle(palette.muted)
                        .accessibilityIdentifier("sharing-pending-\(member.firstName.lowercased())")
                }
                if presentation.isPaused {
                    Text(summary)
                        .trustFont(11)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("sharing-summary-\(member.firstName.lowercased())")
                }
            }
        }
    }

    private var modeControl: some View {
        Group {
            if dynamicTypeSize >= .xxxLarge {
                VStack(spacing: 3) {
                    modeButton(.off, label: TrustCopy.off, fillWidth: true)
                    modeButton(.sealed, label: TrustCopy.sealed, fillWidth: true)
                    modeButton(.always, label: TrustCopy.always, locked: !model.coverage.canShareAvailable, fillWidth: true)
                }
            } else {
                HStack(spacing: 0) {
                    modeButton(.off, label: TrustCopy.off)
                    Spacer(minLength: 4)
                    modeButton(.sealed, label: TrustCopy.sealed)
                    Spacer(minLength: 4)
                    modeButton(.always, label: TrustCopy.always, locked: !model.coverage.canShareAvailable)
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selection)
    }

    private var actionsMenu: some View {
        Menu {
            Section {
                if case .paused = presentation {
                    let mode = model.restoreMode(for: member.id)
                    Button {
                        model.setResting(mode, for: member.id)
                    } label: {
                        Label(
                            TrustCopy.resumePaused(mode: mode == .always ? TrustCopy.always : TrustCopy.sealed),
                            systemImage: "play.fill"
                        )
                    }
                    .disabled(model.isUpdatingShare(personID: member.id))
                    .accessibilityIdentifier("resume-sharing-\(member.firstName.lowercased())")
                }
                Button(TrustCopy.pause, action: onPause)
                    .disabled(presentation.isOff || model.isUpdatingShare(personID: member.id))
                    .accessibilityIdentifier("pause-sharing-\(member.firstName.lowercased())")
            }
            Section {
                Button {
                    model.togglePresenceGrant(personID: member.id)
                } label: {
                    Label(
                        TrustCopy.presenceGrantLabel(member.firstName),
                        systemImage: member.outboundPresenceGranted ? "checkmark.circle.fill" : "circle"
                    )
                }
                .disabled(model.isDemoMode || model.isUpdatingPresenceGrant(personID: member.id))
                .accessibilityIdentifier("presence-grant-\(member.firstName.lowercased())")
                .accessibilityAddTraits(member.outboundPresenceGranted ? [.isSelected] : [])
                Button(TrustCopy.presenceGrantDetails) {
                    showingPresenceGrantDetails = true
                }
                .accessibilityIdentifier("presence-grant-details-\(member.firstName.lowercased())")
            }
            Button(TrustCopy.removePerson, role: .destructive, action: onRemove)
                .accessibilityIdentifier("remove-person-action-\(member.firstName.lowercased())")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(TrustCopy.moreSharingActions(member.firstName))
        .accessibilityIdentifier("sharing-actions-\(member.firstName.lowercased())")
    }

    private func modeButton(_ mode: Mode, label: String, locked: Bool = false, fillWidth: Bool = false) -> some View {
        let selected = selection == mode
        return Button {
            if selected {
                if mode == .off, model.isUpdatingShare(personID: member.id) {
                    onStopSharing()
                }
                return
            }
            if locked { model.showingPaywall = true; return }
            switch mode {
            case .off:
                onStopSharing()
            case .sealed: model.setResting(.untilTheyLook, for: member.id)
            case .always: model.setResting(.always, for: member.id)
            }
        } label: {
            Text(label)
                .lineLimit(1)
                .fixedSize(horizontal: !fillWidth, vertical: false)
                .trustFont(12, weight: selected ? .semibold : .medium)
                .foregroundStyle(selected ? palette.ink : palette.muted)
                .padding(.horizontal, 4)
                .frame(minWidth: 44, maxWidth: fillWidth ? .infinity : nil, minHeight: 44, alignment: .center)
                .contentShape(Rectangle())
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.ink.opacity(0.09))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(palette.ink.opacity(0.24), lineWidth: 1)
                            }
                            .matchedGeometryEffect(id: "confirmed-mode-highlight-\(member.id)", in: selectionNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "\(label). \(TrustCopy.plus)" : label)
        .accessibilityIdentifier("sharing-mode-\(mode)-\(member.firstName.lowercased())")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .disabled(mode != .off && model.isUpdatingShare(personID: member.id))
    }

}

/// Timed pause restores Sealed or Always. Stop sharing is permanent Off.
struct PauseSharingSheet: View {
    let personID: UUID
    let dismiss: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Choice: Identifiable {
        let id: TimeInterval
        let label: String
    }

    private var choices: [Choice] {
        PauseDuration.allCases.map { duration in
            Choice(id: duration.seconds, label: TrustCopy.pauseDurationLabel(duration))
        }
    }

    private var returnsTo: String {
        model.restoreMode(for: personID) == .always ? TrustCopy.always : TrustCopy.sealed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(TrustCopy.pauseTitle(name: model.member(personID)?.firstName ?? TrustCopy.them))
                    .font(TrustTheme.display(28))
                    .tracking(-0.6)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(TrustCopy.pauseReturns(mode: returnsTo))
                    .font(TrustTheme.ui(15))
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        ForEach(choices) { choice in
                            durationButton(choice)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(choices) { choice in
                            durationButton(choice)
                        }
                    }
                }

                Button(TrustCopy.cancel, action: dismiss)
                    .buttonStyle(TrustTextButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("pause-sharing-cancel")
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .trustReadableWidth()
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("pause-sharing-scroll")
        .background(palette.paper)
    }

    private func durationButton(_ choice: Choice) -> some View {
        Button {
            model.pauseSharing(personID: personID, duration: PauseDuration.matching(seconds: choice.id))
            dismiss()
        } label: {
            Text(choice.label)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 8)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .font(TrustTheme.ui(15, weight: .semibold))
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Capsule().fill(palette.surface))
        .accessibilityIdentifier("pause-duration-\(Int(choice.id))")
    }
}

/// First non-Off share → explain Always before the system prompt.
struct AlwaysExplainerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrustEyebrow(text: TrustCopy.location, size: 10)
                .padding(.bottom, 10)
            Text(TrustCopy.alwaysTitle)
                .font(TrustTheme.display(28))
                .tracking(-0.8)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
                .accessibilityAddTraits(.isHeader)
            Text(model.location.needsSystemSettings ? TrustCopy.keptWhileUsing : TrustCopy.alwaysBody)
                .font(TrustTheme.ui(15))
                .lineSpacing(4)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 20)

            Button(model.location.needsSystemSettings ? TrustCopy.openSettings : TrustCopy.allowAlways) {
                model.allowAlwaysFromExplainer()
            }
            .buttonStyle(TrustFilledButtonStyle())
            .accessibilityIdentifier("always-explainer-allow")

            Button(TrustCopy.later) {
                model.showingAlwaysExplainer = false
            }
            .buttonStyle(TrustTextButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("always-explainer-later")
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .trustReadableWidth()
        .background(palette.paper.ignoresSafeArea())
    }
}
