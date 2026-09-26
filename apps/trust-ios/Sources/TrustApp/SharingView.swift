import SwiftUI
import TrustCore

/// Sharing — name left, mode right. Sealed, Always (Plus), Pause. Add someone lives here.
struct SharingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var activeConfirmation: SharingConfirmation?
    @State private var showingHomeStatus = false

    private enum SharingConfirmation: Equatable {
        case stopSharing(personID: UUID, name: String)
        case removePerson(personID: UUID, name: String)
        case stopAll
    }

    private var confirmationTitle: String {
        switch activeConfirmation {
        case .some(.stopSharing(_, let name)): return "Stop sharing with \(name)?"
        case .some(.removePerson(_, let name)): return TrustCopy.removePersonConfirm(name: name)
        case .some(.stopAll): return TrustCopy.stopAllConfirm
        case .none: return ""
        }
    }

    private var confirmationMessage: String {
        switch activeConfirmation {
        case .some(.stopSharing(_, _)): return "They will not see your location or Home/Away status until you choose a sharing mode again."
        case .some(.removePerson(_, _)): return "They leave your People list and both sharing directions stop."
        case .some(.stopAll): return "No one will see your location or Home/Away status until you choose sharing modes again."
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
                        .padding(.top, 20)

                    if !model.connectionRequests.incoming.isEmpty
                        || !model.connectionRequests.sent.isEmpty
                        || model.isLoadingConnectionRequests
                        || model.connectionRequestsNotice != nil
                        || model.connectionRequiresPhoneVerification {
                        ConnectionRequestsSection()
                            .padding(.top, 24)
                    }

                    if !model.circle.isEmpty {
                        TrustSectionHeading(TrustCopy.people)
                            .padding(.top, 30)
                            .padding(.bottom, 4)
                        ForEach(model.circle) { member in
                            OutboundRow(
                                member: member,
                                seed: seed(member),
                                compact: geometry.size.width < 430,
                                stackModes: geometry.size.width < 380,
                                onPause: { model.pauseSheetPersonID = member.id },
                                onStopSharing: { activeConfirmation = .stopSharing(personID: member.id, name: member.firstName) },
                                onRemove: { activeConfirmation = .removePerson(personID: member.id, name: member.firstName) }
                            )
                            TrustRowDivider()
                        }

                    }

                    presenceSection
                        .padding(.top, 26)

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
            }
            .background(palette.paper.ignoresSafeArea())
            .refreshable {
                await model.refresh()
                await model.refreshConnectionRequests()
            }
            .sheet(isPresented: Binding(
                get: { model.pauseSheetPersonID != nil },
                set: { if !$0 { model.pauseSheetPersonID = nil } }
            )) {
                if let personID = model.pauseSheetPersonID {
                    PauseSharingSheet(personID: personID) {
                        model.pauseSheetPersonID = nil
                    }
                    .environmentObject(model)
                    .environment(\.trustPalette, palette)
                    .presentationDetents([.height(420)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(palette.paper)
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

/// Name left. Sealed / Always / Pause right. Pause confirms before setting Off.
struct OutboundRow: View {
    let member: TrustedPerson
    var seed: Int = 0
    var compact = false
    var stackModes = false
    let onPause: () -> Void
    let onStopSharing: () -> Void
    let onRemove: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        case .off: return "Not sharing"
        case .untilTheyLook: return TrustCopy.sealed
        case .always: return TrustCopy.always
        case .paused(let ends, let restores):
            let time = ends.formatted(date: .omitted, time: .shortened)
            let mode = restores == .always ? TrustCopy.always : TrustCopy.sealed
            return "Paused until \(time) · then \(mode)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize >= .xxxLarge || stackModes || (compact && selection == nil) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        personLabel
                        Spacer(minLength: 4)
                        actionsMenu
                    }
                    modeControl
                }
            } else {
                HStack(spacing: 8) {
                    personLabel
                        .frame(minWidth: 88, maxWidth: .infinity, alignment: .leading)
                    modeControl
                        .frame(width: compact ? 176 : 190)
                    actionsMenu
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 15 : 9)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sharing-mode-group-\(member.firstName.lowercased())")
    }

    private var personLabel: some View {
        HStack(spacing: 9) {
            if !compact {
                TrustAvatar(name: member.person.displayName, seed: seed, size: 40, avatar: member.person.avatar, personID: member.id)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.person.displayName)
                    .trustFont(14, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if case .paused = presentation {
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
        HStack(spacing: 1) {
            modeButton(.off, label: TrustCopy.off)
            modeButton(.sealed, label: TrustCopy.sealed)
            modeButton(.always, label: TrustCopy.always, locked: !model.coverage.canShareAvailable)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
    }

    private var actionsMenu: some View {
        Menu {
            Button(TrustCopy.pause, action: onPause)
                .disabled(presentation.isOff)
                .accessibilityIdentifier("pause-sharing-\(member.firstName.lowercased())")
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

    private func modeButton(_ mode: Mode, label: String, locked: Bool = false) -> some View {
        let selected = selection == mode
        return Button {
            if selected { return }
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
            .trustFont(12, weight: selected ? .semibold : .medium)
            .foregroundStyle(selected ? palette.ink : (locked ? palette.accent : palette.muted))
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? palette.paper : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "Always. \(TrustCopy.plus)" : label)
        .accessibilityIdentifier("sharing-mode-\(mode)-\(member.firstName.lowercased())")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

}

/// Timed pause restores Sealed or Always. Stop sharing is permanent Off.
struct PauseSharingSheet: View {
    let personID: UUID
    let dismiss: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    private struct Choice: Identifiable {
        let id: TimeInterval
        let label: String
    }

    private var choices: [Choice] {
        [
            .init(id: 3600, label: "1 hour"),
            .init(id: 8 * 3600, label: "8 hours"),
            .init(id: 24 * 3600, label: "1 day"),
            .init(id: 2 * 24 * 3600, label: "2 days"),
            .init(id: 3 * 24 * 3600, label: "3 days")
        ]
    }

    private var returnsTo: String {
        model.restoreMode(for: personID) == .always ? TrustCopy.always : TrustCopy.sealed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(TrustCopy.pauseTitle(name: model.member(personID)?.firstName ?? TrustCopy.them))
                .font(TrustTheme.display(28))
                .tracking(-0.6)
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(TrustCopy.pauseReturns(mode: returnsTo))
                .font(TrustTheme.ui(15))
                .foregroundStyle(palette.muted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(choices) { choice in
                    Button(choice.label) {
                        model.pauseSharing(personID: personID, duration: PauseDuration.matching(seconds: choice.id))
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(TrustTheme.ui(15, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(palette.surface))
                    .accessibilityIdentifier("pause-duration-\(Int(choice.id))")
                }
            }

            Button(TrustCopy.cancel, action: dismiss)
                .buttonStyle(TrustTextButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trustReadableWidth()
        .background(palette.paper)
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
