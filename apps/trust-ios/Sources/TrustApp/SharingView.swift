import SwiftUI
import TrustCore

/// Sharing — name left, mode right. Sealed, Always (Plus), Pause. Add someone lives here.
struct SharingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TrustPageTitle(text: TrustCopy.sharing)
                    .padding(.top, 4)

                Text(TrustCopy.sharingIntro)
                    .trustFont(14)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityIdentifier("sharing-intro")

                AddSomeoneSection()
                    .padding(.top, 14)

                if !model.circle.isEmpty {
                    ForEach(model.circle) { member in
                    OutboundRow(member: member, seed: seed(member)) {
                        model.pauseSheetPersonID = member.id
                    }
                        TrustRowDivider()
                    }

                    if model.outboundActiveCount > 0 {
                        Button(TrustCopy.stopAll) { model.stopAllRequested = true }
                            .buttonStyle(TrustTextButtonStyle(color: palette.accent))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 18)
                            .accessibilityIdentifier("stop-all-sharing")
                    }
                }
            }
            .padding(.horizontal, TrustTheme.gutter)
            .padding(.bottom, 28)
            .trustReadableWidth()
        }
        .background(palette.paper.ignoresSafeArea())
        .refreshable { await model.refresh() }
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
        .confirmationDialog(TrustCopy.stopAllConfirm, isPresented: $model.stopAllRequested, titleVisibility: .visible) {
            Button(TrustCopy.stopAll, role: .destructive) { model.stopAll() }
                .accessibilityIdentifier("stop-all-sharing-confirm")
            Button(TrustCopy.cancel, role: .cancel) {}
        }
    }

    private func seed(_ member: TrustedPerson) -> Int {
        model.circle.firstIndex { $0.id == member.id } ?? 0
    }
}

/// Name left. Sealed / Always / Pause right. Pause confirms before setting Off.
struct OutboundRow: View {
    let member: TrustedPerson
    var seed: Int = 0
    let onPause: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var confirmOff = false
    @State private var confirmRemove = false

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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TrustAvatar(name: member.person.displayName, seed: seed, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.person.displayName)
                        .trustFont(15, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(summary)
                        .trustFont(12)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .accessibilityIdentifier("sharing-summary-\(member.firstName.lowercased())")
                }
                Spacer(minLength: 2)
                Button(action: onPause) {
                    Text(TrustCopy.pause)
                        .trustFont(13, weight: .semibold)
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Capsule().stroke(palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause sharing with \(member.firstName)")
                .accessibilityIdentifier("pause-sharing-\(member.firstName.lowercased())")
                .disabled(presentation.isOff)
            }

            HStack(spacing: 4) {
                modeButton(.off, label: "Off")
                modeButton(.sealed, label: TrustCopy.sealed)
                modeButton(.always, label: TrustCopy.always, locked: !model.coverage.canShareAvailable)
                Spacer(minLength: 4)
                Menu {
                    Button(TrustCopy.removePerson, role: .destructive) { confirmRemove = true }
                        .accessibilityIdentifier("remove-person-action-\(member.firstName.lowercased())")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More sharing actions for \(member.firstName)")
                .accessibilityIdentifier("sharing-actions-\(member.firstName.lowercased())")
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.surface))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sharing-mode-group-\(member.firstName.lowercased())")
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .confirmationDialog("Stop sharing with \(member.firstName)?", isPresented: $confirmOff, titleVisibility: .visible) {
            Button(TrustCopy.stopSharing, role: .destructive) { model.stopSharing(personID: member.id) }
                .accessibilityIdentifier("stop-sharing-confirm")
            Button(TrustCopy.cancel, role: .cancel) {}
        }
        .confirmationDialog(TrustCopy.removePersonConfirm(name: member.firstName), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(TrustCopy.removePerson, role: .destructive) { model.removePerson(personID: member.id) }
                .accessibilityIdentifier("remove-person-confirm")
            Button(TrustCopy.cancel, role: .cancel) {}
        }
    }

    private func modeButton(_ mode: Mode, label: String, locked: Bool = false) -> some View {
        let selected = selection == mode
        return Button {
            if selected { return }
            if locked { model.showingPaywall = true; return }
            switch mode {
            case .off: confirmOff = true
            case .sealed: model.setResting(.untilTheyLook, for: member.id)
            case .always: model.setResting(.always, for: member.id)
            }
        } label: {
            HStack(spacing: 4) {
                Text(label).lineLimit(1)
                if locked { Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold)).accessibilityHidden(true) }
            }
            .trustFont(12, weight: selected ? .semibold : .medium)
            .foregroundStyle(selected ? palette.ink : (locked ? palette.accent : palette.muted))
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
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
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .trustReadableWidth()
        .background(palette.paper.ignoresSafeArea())
    }
}
