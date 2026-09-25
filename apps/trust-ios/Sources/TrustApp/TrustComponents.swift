import SwiftUI
import TrustCore
import UIKit

enum ProfileAvatarArtwork {
    static func assetName(for preset: String) -> String {
        switch preset {
        case "fern": "AvatarFern"
        case "ember": "AvatarEmber"
        case "sky": "AvatarSky"
        case "ocean": "AvatarOcean"
        case "sunrise": "AvatarSunrise"
        case "lavender": "AvatarLavender"
        case "moon": "AvatarMoon"
        case "star": "AvatarStar"
        case "cloud": "AvatarCloud"
        case "raindrop": "AvatarRaindrop"
        case "rainbow": "AvatarRainbow"
        case "mountain": "AvatarMountain"
        case "river": "AvatarRiver"
        case "meadow": "AvatarMeadow"
        case "clover": "AvatarClover"
        case "bloom": "AvatarBloom"
        case "cherry": "AvatarCherry"
        case "lotus": "AvatarLotus"
        case "mushroom": "AvatarMushroom"
        case "seashell": "AvatarSeashell"
        case "coral": "AvatarCoral"
        case "butterfly": "AvatarButterfly"
        case "hummingbird": "AvatarHummingbird"
        case "fox": "AvatarFox"
        case "whale": "AvatarWhale"
        case "koi": "AvatarKoi"
        default: "AvatarFern"
        }
    }

    static func title(for preset: String) -> String {
        preset.prefix(1).uppercased() + preset.dropFirst()
    }
}

/// Profile picture disc with initials fallback (`.avatar`). Fill is stable per person.
struct TrustAvatar: View {
    let name: String
    var seed: Int = 0
    var size: CGFloat = 44
    var avatar: AvatarDescriptor? = nil
    var personID: UUID? = nil
    @EnvironmentObject private var model: AppModel
    @Environment(\.trustPalette) private var palette
    @State private var photo: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(avatarFill)
            if let preset = avatar?.knownPresetID {
                presetGlyph(preset)
            } else if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                initials
            }
        }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(palette.ink.opacity(0.03), lineWidth: 1))
            .accessibilityHidden(true)
            .task(id: photoTaskKey) {
                photo = nil
                guard avatar?.photoVersion != nil else { return }
                photo = try? await model.client.avatarImage(personID: resolvedPersonID, descriptor: avatar)
            }
    }

    private var initials: some View {
        Text(name.trustInitials)
            // Initials are decorative; full names remain available to VoiceOver nearby.
            .font(.system(size: size * 0.40, weight: .semibold, design: .rounded))
            .tracking(-0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .foregroundStyle(palette.ink)
            .frame(width: size * 0.78, height: size * 0.78)
    }

    private var resolvedPersonID: UUID { personID ?? model.you.id }

    private var photoTaskKey: String {
        "\(resolvedPersonID.uuidString)-\(avatar?.version ?? "")"
    }

    private func presetGlyph(_ preset: String) -> some View {
        return Image(ProfileAvatarArtwork.assetName(for: preset))
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
    }

    private var avatarFill: Color {
        switch abs(seed) % 4 {
        case 0: return palette.accentSoft
        case 1: return palette.sage
        case 2: return palette.surface
        default: return palette.canvas
        }
    }
}

/// Home status uses the positive accent; other presence stays quiet.
struct TrustPresenceDot: View {
    let presence: HomePresenceKind
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Circle()
            .fill(presence == .home ? palette.positive : palette.muted.opacity(0.6))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// Status line under a name: optional dot or glyph + text.
struct TrustStatusLine: View {
    var presence: HomePresenceKind? = nil
    var glyph: String? = nil
    let text: String
    var color: Color? = nil
    @Environment(\.trustPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            if let presence {
                TrustPresenceDot(presence: presence)
            } else if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(2)
        }
        .trustFont(13)
        .foregroundStyle(color ?? palette.muted)
    }
}

/// `.badge` — pill with glyph: "Home", "Presence hidden".
struct TrustBadge: View {
    let glyph: String
    let text: String
    @Environment(\.trustPalette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
                .font(.system(size: 10, weight: .medium))
                .accessibilityHidden(true)
            Text(text)
        }
        .trustFont(11, weight: .medium)
        .foregroundStyle(palette.muted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(palette.accentSoft))
    }
}

/// Section heading with an optional trailing action.
struct TrustSectionHeading<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    init(_ text: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center) {
            TrustEyebrow(text: text, size: 10)
            Spacer(minLength: 8)
            trailing
        }
        .frame(minHeight: 28)
    }
}

/// `.footnote` — small muted note with a leading glyph.
struct TrustFootnote: View {
    var glyph: String = "checkmark.shield"
    let text: String
    @Environment(\.trustPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .trustFont(12)
        .lineSpacing(3)
        .foregroundStyle(palette.muted)
    }
}

/// `.info-strip` — muted plate with glyph + body.
struct TrustInfoStrip: View {
    let glyph: String
    let text: String
    @Environment(\.trustPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.muted)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(text)
                .trustFont(13)
                .lineSpacing(3)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// `.mode-control` — three-way plate. Locked options render a Plus mark and still fire
/// (intent-triggered paywall placement); the server answers `pro_required`.
struct TrustModeControl<Option: Hashable>: View {
    struct Item: Identifiable {
        let id: Option
        let label: String
        var locked = false
    }

    let items: [Item]
    let selection: Option?
    let onSelect: (Option) -> Void
    @Environment(\.trustPalette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let selected = selection == item.id
                Button {
                    onSelect(item.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(item.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        if item.locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .bold))
                                .accessibilityHidden(true)
                        }
                    }
                    .trustFont(13, weight: selected ? .semibold : .medium)
                    .foregroundStyle(selected ? palette.ink : (item.locked ? palette.accent : palette.muted))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(selected ? palette.surface : .clear)
                            .shadow(color: selected ? palette.ink.opacity(0.08) : .clear, radius: 2, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.locked ? "\(item.label). \(TrustCopy.plus)" : item.label)
                .accessibilityIdentifier("mode-option-\(String(describing: item.id))")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.canvas)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
        )
    }
}

/// `.toast` — ink plate, bottom of the shell, ~4 s.
struct TrustToastView: View {
    let toast: TrustToast
    let dismiss: () -> Void
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(toast.message)
            .trustFont(13, weight: .medium)
            .lineSpacing(2)
            .foregroundStyle(palette.paper)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 5)
            .onTapGesture(perform: dismiss)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(toast.message)
    }
}

/// `.empty-map` — centered title, body, optional action.
struct TrustEmptyState: View {
    var glyph: String? = nil
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(spacing: 14) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(TrustTheme.display(26))
                .tracking(-0.6)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .trustFont(14)
                .lineSpacing(3)
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(TrustFilledButtonStyle())
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
    }
}

/// Offline strip under the masthead — a state, not a screen.
struct TrustOfflineBanner: View {
    let since: Date
    let retry: () -> Void
    @Environment(\.trustPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(TrustCopy.offlineBanner(since: since.formatted(date: .omitted, time: .shortened)))
                .trustFont(12, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(TrustCopy.retry, action: retry)
                .font(TrustTheme.ui(12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(minHeight: 44)
        }
        .foregroundStyle(palette.muted)
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.vertical, 6)
        .background(palette.surface)
    }
}

/// Rows in lists share one hairline and one rhythm (`.person-row`).
struct TrustRowDivider: View {
    var body: some View {
        TrustHairline()
    }
}
