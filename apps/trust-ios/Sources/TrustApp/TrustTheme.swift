import SwiftUI
import TrustCore
import UIKit

/// Shared Trust colors. `paper` remains the public palette entry point and adapts
/// to the system appearance so maps, sheets, and forms stay in one visual system.
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
    var positive: Color
    var danger: Color
    var chrome: Color
    var chromeInk: Color
    var chromeMuted: Color
    var pinLive: Color
    var pinLook: Color
    var sheet: Color

    static let paper = TrustPalette(
        paper: adaptive(0xF6F8FC, 0x101A2B),
        canvas: adaptive(0xEEF2F8, 0x0B1423),
        ink: adaptive(0x14233B, 0xF1F5FC),
        muted: adaptive(0x617089, 0xA9B7CE),
        line: adaptive(0xDCE3EF, 0x2A3850),
        surface: adaptive(0xFFFFFF, 0x19263A),
        accent: adaptive(0x245CE7, 0x6F95FF),
        accentSoft: adaptive(0xE8EFFF, 0x22375F),
        accentOn: adaptive(0xFFFFFF, 0x101A2B),
        sage: adaptive(0xDDF3EC, 0x193D3A),
        positive: adaptive(0x168879, 0x51C8B3),
        danger: adaptive(0xB42318, 0xFF8F85),
        chrome: adaptive(0xFFFFFF, 0x19263A),
        chromeInk: adaptive(0x14233B, 0xF1F5FC),
        chromeMuted: adaptive(0x52627C, 0xA9B7CE),
        pinLive: adaptive(0x168879, 0x51C8B3),
        pinLook: adaptive(0x245CE7, 0x6F95FF),
        sheet: adaptive(0xF6F8FC, 0x101A2B)
    )
}

private func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    })
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
    static let radius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let gutter: CGFloat = 22
    static let readableWidth: CGFloat = 640

    static func chrome(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Rounded system display typography keeps the brand native and accessible.
    static func display(_ size: CGFloat) -> Font {
        .system(textStyle(for: size), design: .rounded).weight(.semibold)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(textStyle(for: size), design: .default).weight(weight)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(textStyle(for: size), design: .rounded).weight(.semibold)
    }

    static func folio(_ size: CGFloat) -> Font {
        .system(textStyle(for: size), design: .default).weight(.semibold)
    }

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
    func trustFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(TrustScaledFont(size: size, weight: weight))
    }
}

struct TrustEyebrow: View {
    let text: String
    var color: Color? = nil
    var size: CGFloat = 11
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(text.uppercased())
            .trustFont(size, weight: .semibold)
            .tracking(0.7)
            .foregroundStyle(color ?? palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

typealias TrustFolio = TrustEyebrow

struct TrustPageTitle: View {
    let text: String
    var size: CGFloat = 30
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(text)
            .font(TrustTheme.display(size))
            .tracking(-0.5)
            .foregroundStyle(palette.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TrustWordmarkTitle: View {
    var size: CGFloat = 30
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(TrustCopy.mastheadName)
            .font(TrustTheme.display(size))
            .tracking(-0.8)
            .foregroundStyle(palette.ink)
            .accessibilityLabel(TrustCopy.appName)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TrustRule: View {
    var width: CGFloat = 44
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Capsule().fill(palette.accent).frame(width: width, height: 3).accessibilityHidden(true)
    }
}

struct TrustHairline: View {
    @Environment(\.trustPalette) private var palette
    var body: some View { palette.line.frame(height: 1) }
}

struct TrustWordmark: View {
    @Environment(\.trustPalette) private var palette

    var body: some View {
        Text(TrustCopy.mastheadName)
            .font(TrustTheme.display(22))
            .tracking(-0.5)
            .foregroundStyle(palette.ink)
            .accessibilityElement()
            .accessibilityLabel(TrustCopy.appName)
    }
}

struct TrustFilledButtonStyle: ButtonStyle {
    var expand = true
    @Environment(\.trustPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(16, weight: .semibold)
            .foregroundStyle(palette.accentOn.opacity(configuration.isPressed ? 0.76 : 1))
            .padding(.horizontal, 20)
            .frame(maxWidth: expand ? .infinity : nil, minHeight: 52)
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
            .foregroundStyle(palette.ink.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 50)
            .background(palette.surface)
            .overlay(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous).stroke(palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: TrustTheme.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct TrustTextButtonStyle: ButtonStyle {
    var color: Color? = nil
    @Environment(\.trustPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(14, weight: .medium)
            .foregroundStyle((color ?? palette.muted).opacity(configuration.isPressed ? 0.55 : 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct TrustLinkButtonStyle: ButtonStyle {
    @Environment(\.trustPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.label
            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
        }
        .trustFont(14, weight: .semibold)
        .foregroundStyle(palette.accent.opacity(configuration.isPressed ? 0.55 : 1))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct TrustPillButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.trustPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .trustFont(13, weight: .semibold)
            .foregroundStyle((prominent ? palette.accent : palette.muted).opacity(configuration.isPressed ? 0.55 : 1))
            .padding(.horizontal, 16)
            .frame(minWidth: 72, minHeight: 40)
            .background(prominent ? palette.accentSoft : palette.surface, in: Capsule())
            .contentShape(Capsule())
    }
}

struct TrustAppleButtonStyle: ButtonStyle {
    @Environment(\.trustPalette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.75 : 1))
            .background(Color.black.opacity(configuration.isPressed ? 0.86 : 1))
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
                TrustEyebrow(text: title, size: 11)
                if let hint {
                    Spacer()
                    TrustEyebrow(text: hint, color: palette.positive, size: 11)
                }
            }
            content
        }
    }
}

struct TrustCard<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color? = nil
    @ViewBuilder var content: Content
    @Environment(\.trustPalette) private var palette

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? palette.surface)
            .overlay(RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous).stroke(fill == nil ? palette.line : .clear, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: TrustTheme.radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, x: 0, y: 5)
    }
}

struct TrustTextFieldStyle: TextFieldStyle {
    @Environment(\.trustPalette) private var palette

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(TrustTheme.ui(16, weight: .medium))
            .foregroundStyle(palette.ink)
            .padding(14)
            .background(palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.line, lineWidth: 1))
    }
}

extension String {
    var trustInitials: String {
        var trimmed = trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("@") { trimmed = String(trimmed.dropFirst()) }
        let parts = trimmed.split(separator: " ").prefix(2)
        if parts.count >= 2 { return parts.map { String($0.prefix(1)).uppercased() }.joined() }
        return String(trimmed.prefix(2)).uppercased()
    }
}

extension View {
    func trustReadableWidth() -> some View {
        frame(maxWidth: TrustTheme.readableWidth).frame(maxWidth: .infinity)
    }

    func trustFormSheet() -> some View {
        presentationSizing(.form)
    }
}
