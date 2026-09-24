import SwiftUI
import TrustCore

/// Visual tokens for Trust home (map + sheet). Brand red `#E10600` stays the only
/// chromatic accent — not Life360 purple. Map chrome is high-contrast white/ink.
struct TrustPalette: Equatable {
    var paper: Color
    var canvas: Color
    var ink: Color
    var muted: Color
    var line: Color
    var surface: Color
    var accent: Color
    var accentSoft: Color
    var accentOn: Color
    var sage: Color
    /// Floating map controls / group pill fill.
    var chrome: Color
    var chromeInk: Color
    var chromeMuted: Color
    /// Available (live) map pin.
    var pinLive: Color
    /// Look snapshot pin.
    var pinLook: Color
    var sheet: Color

    /// Hex tokens (SoT): paper `#FFFEFA`, ink `#141613`, accent `#E10600`,
    /// pinLive `#1F3D34`, chrome `#FFFFFF`, sheet `#FFFEFA`, muted `#5E605A`.
    static let paper = TrustPalette(
        paper: Color(hex: 0xFFFEFA),
        canvas: Color(hex: 0xEEEDE8),
        ink: Color(hex: 0x141613),
        muted: Color(hex: 0x5E605A),
        line: Color(hex: 0xE0DFD8),
        surface: Color(hex: 0xF5F4EF),
        accent: Color(hex: 0xE10600),
        accentSoft: Color(hex: 0xFFE8E2),
        accentOn: .white,
        sage: Color(hex: 0xDCE5D6),
        chrome: .white,
        chromeInk: Color(hex: 0x141613),
        chromeMuted: Color(hex: 0x4A4C46),
        pinLive: Color(hex: 0x1F3D34),
        pinLook: Color(hex: 0x141613),
        sheet: Color(hex: 0xFFFEFA)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct TrustPaletteKey: EnvironmentKey {
    static let defaultValue = TrustPalette.paper
}

extension EnvironmentValues {
    var trustPalette: TrustPalette {
        get { self[TrustPaletteKey.self] }
        set { self[TrustPaletteKey.self] = newValue }
    }
}

enum TrustTheme {
    static let accent = TrustPalette.paper.accent
    /// Card / control radius from the mock (13–15 pt).
    static let radius: CGFloat = 14
    static let controlRadius: CGFloat = 13
    /// Page gutter.
    static let gutter: CGFloat = 22
    /// iPad: list columns stay readable; Map is full-bleed (M3).
    static let readableWidth: CGFloat = 640

    /// Rounded system UI for map chrome (pill) — denser, more readable over MapKit.
    static func chrome(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Serif display — wordmark, page titles, names on View.
    static func display(_ size: CGFloat) -> Font {
        .custom("Didot", size: size, relativeTo: .title)
    }

    /// Space Grotesk — Collapse Technologies wordmark only.
    static func sans(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.custom("Space Grotesk", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat) -> Font {
        Font.custom("IBM Plex Mono", size: size, relativeTo: textStyle(for: size)).weight(.medium)
    }

    /// Fixed-size system font. Prefer `View.trustFont(_:weight:)`, which follows Dynamic Type;
    /// this stays for the few places that need a `Font` value.
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), design: .default).weight(weight)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(textStyle(for: size), design: .default).weight(.semibold)
    }

    static func folio(_ size: CGFloat) -> Font {
        .system(textStyle(for: size), design: .default).weight(.semibold)
    }

    /// The text style whose Dynamic Type curve a mock point size should follow. Small labels
    /// track `caption2` / `footnote` so they grow, but not as fast as body copy and titles.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<16: return .subheadline
        case ..<17: return .callout
        case ..<19: return .body
        case ..<22: return .title3
        case ..<28: return .title2
        case ..<34: return .title
        default: return .largeTitle
        }
    }
}

/// System UI font at a mock point size that scales with the user's Dynamic Type setting.
/// `@ScaledMetric` re-renders live when the size changes in Settings or Control Center.
private struct TrustScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: TrustTheme.textStyle(for: size))
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .default))
    }
}

extension View {
    /// Dynamic Type–aware replacement for `.font(TrustTheme.ui(size, weight:))`. Works on
    /// `Text`, `Label`, and SF Symbol `Image`s alike, so glyphs scale with the text beside them.
    func trustFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(TrustScaledFont(size: size, weight: weight))
    }
}

/// Small caps eyebrow (`.eyebrow`): SHARED WITH YOU, STATUS, PRESENCE …
struct TrustEyebrow: View {
    let text: String
    var color: Color? = nil
    var size: CGFloat = 11
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(text.uppercased())
            .trustFont(size, weight: .semibold)
            .tracking(1.5)
            .foregroundStyle(color ?? palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Backwards-compatible alias used by older components.
typealias TrustFolio = TrustEyebrow

/// "Sharing." — serif title with the red full stop.
struct TrustPageTitle: View {
    let text: String
    var size: CGFloat = 34
    @Environment(\.trustPalette) private var palette

    var body: some View {
        (Text(text).foregroundColor(palette.ink) + Text(".").foregroundColor(palette.accent))
            .font(TrustTheme.display(size))
            .tracking(-0.8)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// "Trust." wordmark.
struct TrustWordmarkTitle: View {
    var size: CGFloat = 34
    @Environment(\.trustPalette) private var palette

    var body: some View {
        (Text(TrustCopy.mastheadName).foregroundColor(palette.ink) + Text(".").foregroundColor(palette.accent))
            .font(TrustTheme.display(size))
            .tracking(-1.6)
            .accessibilityLabel(TrustCopy.appName)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TrustRule: View {
    var width: CGFloat = 56
    @Environment(\.trustPalette) private var palette

    var body: some View {
        palette.accent
            .frame(width: width, height: 2)
            .accessibilityHidden(true)
    }
}

struct TrustHairline: View {
    @Environment(\.trustPalette) private var palette

    var body: some View {
        palette.line.frame(height: 1)
    }
}

/// Collapse Technologies mark (Space Grotesk) — Login only.
struct TrustWordmark: View {
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("COLLAPSE")
                .font(TrustTheme.sans(10.5, weight: .semibold))
                .tracking(-0.58)
            Text("TECHNOLOGIES")
                .font(TrustTheme.sans(7, weight: .semibold))
                .tracking(0.56)
        }
        .foregroundStyle(palette.ink)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Collapse Technologies")
    }
}

// MARK: Button styles (mock: `.primary`, `.secondary`, `.quiet-button`, `.look-button`)

struct TrustFilledButtonStyle: ButtonStyle {
    var expand = true
    @Environment(\.trustPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(15, weight: .semibold)
            .foregroundStyle(palette.accentOn.opacity(configuration.isPressed ? 0.75 : 1))
            .padding(.horizontal, 18)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 50)
            .background(palette.accent.opacity(configuration.isPressed ? 0.86 : 1))
            .clipShape(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct TrustOutlineButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.trustPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(compact ? 14 : 15, weight: .medium)
            .foregroundStyle(palette.ink.opacity(configuration.isPressed ? 0.55 : 1))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 48)
            .background(palette.paper)
            .overlay(
                RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous)
                    .stroke(Color(hex: 0xDEDED4), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct TrustTextButtonStyle: ButtonStyle {
    var color: Color? = nil
    @Environment(\.trustPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(14, weight: .medium)
            .foregroundStyle((color ?? palette.muted).opacity(configuration.isPressed ? 0.5 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// Red text link with a trailing arrow — "Map →", "Manage sharing →".
struct TrustLinkButtonStyle: ButtonStyle {
    @Environment(\.trustPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.label
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
        }
        .trustFont(13, weight: .medium)
        .foregroundStyle(palette.accent.opacity(configuration.isPressed ? 0.5 : 1))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Pill on Circle rows: Look (red) / View (muted).
struct TrustPillButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.trustPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(13, weight: .semibold)
            .foregroundStyle((prominent ? palette.accent : palette.muted).opacity(configuration.isPressed ? 0.5 : 1))
            .padding(.horizontal, 16)
            .frame(minWidth: 72, minHeight: 36)
            .background(
                Capsule().stroke(prominent ? Color(hex: 0xF0C8BE) : palette.line, lineWidth: 1)
            )
            .contentShape(Capsule())
    }
}

/// Black plate for Sign in with Apple. SF Symbol `apple.logo` is Apple's mark.
struct TrustAppleButtonStyle: ButtonStyle {
    @Environment(\.trustPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.paper.opacity(configuration.isPressed ? 0.7 : 1))
            .background(palette.ink.opacity(configuration.isPressed ? 0.86 : 1))
            .clipShape(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.55)
    }
}

struct TrustFieldLabel<Content: View>: View {
    let title: String
    let hint: String?
    @ViewBuilder var content: Content
    @Environment(\.trustPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TrustEyebrow(text: title, size: 10)
                if let hint {
                    Spacer()
                    TrustEyebrow(text: hint, size: 10)
                }
            }
            content
        }
    }
}

/// Rounded, hairline card (`.privacy-summary`, `.plus-card`).
struct TrustCard<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color? = nil
    @ViewBuilder var content: Content
    @Environment(\.trustPalette) private var palette

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? palette.paper)
            .overlay(
                RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous)
                    .stroke(fill == nil ? Color(hex: 0xDEDFD3) : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous))
    }
}

/// Text field plate (`.invite-form input`).
struct TrustTextFieldStyle: TextFieldStyle {
    @Environment(\.trustPalette) private var palette

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(TrustTheme.ui(16, weight: .medium))
            .foregroundStyle(palette.ink)
            .padding(14)
            .background(palette.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color(hex: 0xDEDFD5), lineWidth: 1)
            )
    }
}

extension String {
    var trustInitials: String {
        var trimmed = trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@") {
            trimmed = String(trimmed.dropFirst())
        }
        let parts = trimmed.split(separator: " ").prefix(2)
        if parts.count >= 2 {
            return parts.map { String($0.prefix(1)).uppercased() }.joined()
        }
        return String(trimmed.prefix(2)).uppercased()
    }
}

extension View {
    /// iPad / regular width: keep lists at a readable column, centered.
    func trustReadableWidth() -> some View {
        frame(maxWidth: TrustTheme.readableWidth)
            .frame(maxWidth: .infinity)
    }

    /// iPad sheets size as a form, not a full page. Compact widths keep the phone sheet.
    func trustFormSheet() -> some View {
        presentationSizing(.form)
    }
}
