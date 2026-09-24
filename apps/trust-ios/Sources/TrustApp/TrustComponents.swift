import SwiftUI
import TrustCore

/// Paper-toned initials disc (`.avatar`). Fill is stable per person.
struct TrustAvatar: View {
    let name: String
    var seed: Int = 0
    var size: CGFloat = 44
    @Environment(\.trustPalette) private var palette

    private static let fills: [Color] = [
        Color(hex: 0xE4E9DC), Color(hex: 0xE4E9E9), Color(hex: 0xEFE3D7), Color(hex: 0xE5E3ED),
        Color(hex: 0xE8E3D5), Color(hex: 0xDFE8E1), Color(hex: 0xE8E0D9), Color(hex: 0xEADFDC), Color(hex: 0xE0E5E9)
    ]

    var body: some View {
        Text(name.trustInitials)
            .font(TrustTheme.display(size * 0.42))
            .tracking(-0.7)
            .foregroundStyle(Color(hex: 0x50554B))
            .frame(width: size, height: size)
            .background(Self.fills[abs(seed) % Self.fills.count])
            .clipShape(Circle())
            .overlay(Circle().stroke(palette.ink.opacity(0.03), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// `.presence-dot` — green Home, muted Away.
struct TrustPresenceDot: View {
    let presence: HomePresenceKind

    var body: some View {
        Circle()
            .fill(presence == .home ? Color(hex: 0x829071) : Color(hex: 0xB0B3A8))
            .frame(width: 6, height: 6)
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
        .foregroundStyle(Color(hex: 0x73796A))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().stroke(Color(hex: 0xDDDCD3), lineWidth: 1))
    }
}

/// `.section-heading` — eyebrow left, optional red text link right.
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
        .foregroundStyle(Color(hex: 0x83857A))
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .foregroundStyle(selected ? Color(hex: 0x272C24) : (item.locked ? palette.accent : Color(hex: 0x7B7E71)))
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected ? palette.paper : .clear)
                            .shadow(color: selected ? palette.ink.opacity(0.08) : .clear, radius: 2, y: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.locked ? "\(item.label). \(TrustCopy.plus)" : item.label)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: 0xF0F0E9))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color(hex: 0xE8E8DF), lineWidth: 1))
        )
    }
}

/// `.toast` — ink plate, bottom of the shell, ~4 s.
struct TrustToastView: View {
    let toast: TrustToast
    let dismiss: () -> Void

    var body: some View {
        Text(toast.message)
            .trustFont(13, weight: .medium)
            .lineSpacing(2)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x262D23))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .frame(minHeight: 32)
        }
        .foregroundStyle(palette.muted)
        .padding(.horizontal, TrustTheme.gutter)
        .padding(.vertical, 6)
        .background(palette.surface)
        .accessibilityElement(children: .combine)
    }
}

/// Rows in lists share one hairline and one rhythm (`.person-row`).
struct TrustRowDivider: View {
    var body: some View {
        TrustHairline()
    }
}
