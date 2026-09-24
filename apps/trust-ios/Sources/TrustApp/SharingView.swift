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

                AddSomeoneSection()
                    .padding(.top, 16)

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

    private enum Mode: Hashable { case sealed, always, pause }

    private var presentation: SharePresentation {
        model.shareState(for: member.id).presentation(at: Date())
    }

    private var selection: Mode? {
        switch presentation {
        case .off: return nil
        case .untilTheyLook: return .sealed
        case .always: return .always
        case .paused: return .pause
        }
    }

    private var alwaysLocked: Bool { !model.coverage.canShareAvailable }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TrustAvatar(name: member.person.displayName, seed: seed, size: 36)
            Text(member.person.displayName)
                .trustFont(15, weight: .semibold)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            modeControl
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    private var modeControl: some View {
        HStack(spacing: 2) {
            modeButton(.sealed, label: TrustCopy.sealed, locked: false)
            modeButton(.always, label: TrustCopy.always, locked: alwaysLocked)
            modeButton(.pause, label: TrustCopy.pause, locked: false)
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: 0xF0F0E9))
        )
        .accessibilityLabel(TrustCopy.sharingModeLabel(name: member.firstName))
    }

    private func modeButton(_ mode: Mode, label: String, locked: Bool) -> some View {
        let selected = selection == mode
        return Button {
            switch mode {
            case .sealed:
                model.setResting(.untilTheyLook, for: member.id)
            case .always:
                model.setResting(.always, for: member.id)
            case .pause:
                guard presentation.acceptsLocation || presentation.isPaused else { return }
                onPause()
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .lineLimit(1)
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .trustFont(12, weight: selected ? .semibold : .medium)
            .foregroundStyle(selected ? Color(hex: 0x272C24) : (locked ? palette.accent : Color(hex: 0x7B7E71)))
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? palette.paper : .clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "\(label). \(TrustCopy.plus)" : label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Timed pause restores Sealed or Always. Stop sharing is permanent Off.
struct PauseSharingSheet: View {
    let personID: UUID
    let dismiss: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var confirmRemove = false

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
            Text(TrustCopy.pauseSharing)
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
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(palette.surface))
                }
            }

            Text(TrustCopy.stopSharingWarning)
                .font(TrustTheme.ui(14))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Button(TrustCopy.stopSharing) {
                model.stopSharing(personID: personID)
                dismiss()
            }
            .buttonStyle(TrustFilledButtonStyle())

            Button(TrustCopy.removePerson) {
                confirmRemove = true
            }
            .buttonStyle(TrustTextButtonStyle(color: palette.accent))
            .frame(maxWidth: .infinity)

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
        .confirmationDialog(
            TrustCopy.removePersonConfirm(name: model.member(personID)?.firstName ?? TrustCopy.them),
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button(TrustCopy.removePerson, role: .destructive) {
                model.removePerson(personID: personID)
                dismiss()
            }
            Button(TrustCopy.cancel, role: .cancel) {}
        }
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
