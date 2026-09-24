import Foundation

public enum TrustHandle {
    public static let minLength = 3
    public static let maxLength = 20

    public enum Status: Equatable {
        case valid(String)
        case invalid
        case reserved
    }

    private static let reserved: Set<String> = [
        "about", "account", "admin", "administrator", "api", "apple",
        "bot", "circle", "collapse", "collapsetechnologies",
        "everyone", "google", "help", "here", "invite", "look",
        "login", "me", "mod", "moderator", "null", "official", "owner",
        "privacy", "root", "settings", "signin", "signout", "signup",
        "staff", "status", "support", "system", "terms", "trust",
        "trustcircle", "www", "you"
    ]

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")

    public static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") {
            value = String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.lowercased()
    }

    public static func sanitizeDraft(_ raw: String) -> String {
        let normalized = normalize(raw)
        return String(normalized.unicodeScalars.filter { allowed.contains($0) }.prefix(maxLength))
    }

    public static func status(of raw: String) -> Status {
        let normalized = normalize(raw)
        guard normalized.count >= minLength, normalized.count <= maxLength else { return .invalid }
        guard let first = normalized.first, first.isLetter else { return .invalid }
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return .invalid }
        if reserved.contains(normalized) { return .reserved }
        return .valid(normalized)
    }

    public static func suggest(from displayName: String) -> String? {
        let stripped = displayName.lowercased().filter { $0.isLetter || $0.isNumber }
        guard let first = stripped.first(where: { $0.isLetter }) else { return nil }
        let fromLetter = stripped.drop { $0 != first }
        let candidate = String(fromLetter.prefix(maxLength))
        if case .valid(let handle) = status(of: candidate) {
            return handle
        }
        return nil
    }
}
