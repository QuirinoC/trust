import Foundation

/// An exact, explicitly entered public identifier for the Add Person lookup.
public enum PersonLookupQuery: Equatable, Encodable, Sendable {
    case handle(String)
    case phone(String, region: String?)

    private enum CodingKeys: String, CodingKey {
        case handle
        case phone
        case region
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .handle(let handle):
            try container.encode(handle, forKey: .handle)
        case .phone(let phone, let region):
            try container.encode(phone, forKey: .phone)
            try container.encodeIfPresent(region, forKey: .region)
        }
    }

    /// Returns a query only when the draft is complete enough to send. A phone number
    /// is normalized to digits; `region` is omitted for international `+` numbers.
    public static func parse(_ raw: String, region: String? = Locale.current.region?.identifier) -> Self? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .valid(let handle) = TrustHandle.status(of: value) {
            return .handle(handle)
        }

        guard !value.isEmpty else { return nil }
        let international = value.hasPrefix("+")
        let formatting = Set("+-(). /".unicodeScalars)
        guard value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || formatting.contains($0) }) else { return nil }
        let digits = String(value.filter { $0 >= "0" && $0 <= "9" })
        guard (7...15).contains(digits.count),
              !digits.isEmpty,
              !value.dropFirst().contains("+") else { return nil }
        let normalizedRegion = region?.uppercased()
        return .phone(international ? "+\(digits)" : digits, region: international ? nil : normalizedRegion)
    }
}
