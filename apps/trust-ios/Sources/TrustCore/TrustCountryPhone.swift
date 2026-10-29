import Foundation
import PhoneNumberKit

public struct TrustPhoneCountry: Identifiable, Equatable, Sendable {
    public let code: String
    public let callingCode: String
    public var id: String { code }

    public var name: String {
        TrustAppLanguage.currentLocale.localizedString(forRegionCode: code) ?? code
    }

    public var displayCallingCode: String { "+\(callingCode)" }

    private static let utility = PhoneNumberUtility(metadataCallback: {
        guard let data = try PhoneNumberUtility.defaultMetadataCallback(),
              var document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var metadata = document["phoneNumberMetadata"] as? [String: Any],
              var container = metadata["territories"] as? [String: Any],
              var territories = container["territory"] as? [[String: Any]] else { return nil }
        // Version 5.0.13 doubles backslashes while decoding prefix expressions. An
        // equivalent digit class preserves its official carrier/trunk transformations.
        // Remove this workaround when upstream fixes decoding; BR/AR tests cover it.
        for index in territories.indices {
            if let prefix = territories[index]["nationalPrefixForParsing"] as? String {
                territories[index]["nationalPrefixForParsing"] = prefix.replacingOccurrences(of: #"\d"#, with: "[0-9]")
            }
        }
        container["territory"] = territories
        metadata["territories"] = container
        document["phoneNumberMetadata"] = metadata
        return try JSONSerialization.data(withJSONObject: document)
    })
    private static let metadata: [(code: String, callingCode: String)] = utility.allCountries()
        .filter { $0.count == 2 }
        .compactMap { code in
            guard let dial = utility.countryCode(for: code) else { return nil }
            return (code: code, callingCode: String(dial))
        }

    public static let all: [TrustPhoneCountry] = metadata
        .map { TrustPhoneCountry(code: $0.code, callingCode: $0.callingCode) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    public static let unitedStates = TrustPhoneCountry(code: "US", callingCode: "1")

    public static func country(code: String?) -> TrustPhoneCountry? {
        guard let code else { return nil }
        return all.first { $0.code == code.uppercased() }
    }

    /// Converts a complete number to E.164 with libphonenumber metadata. If the input is
    /// incomplete while the person is editing, retain its digits and selected prefix so
    /// the editor never destroys partial input. The API remains responsible for validation.
    public static func canonicalNumber(_ input: String, countryCode: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let isInternational = trimmed.hasPrefix("+") || trimmed.hasPrefix("00")
        let dialCode = utility.countryCode(for: countryCode.uppercased()).map { String($0) } ?? ""
        let international: String
        if trimmed.hasPrefix("+") {
            international = trimmed
        } else if trimmed.hasPrefix("00") {
            international = "+" + String(trimmed.dropFirst(2))
        } else {
            // Adding the selected calling code makes the selected region authoritative;
            // PhoneNumberKit then applies that region's trunk/carrier-prefix metadata.
            international = dialCode.isEmpty ? trimmed : "+\(dialCode)\(trimmed)"
        }
        let parserRegion = isInternational ? "US" : countryCode.uppercased()
        if let parsed = try? utility.parse(international, withRegion: parserRegion, ignoreType: true) {
            return utility.format(parsed, toType: .e164)
        }
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }
        if trimmed.hasPrefix("+") { return "+\(digits)" }
        if trimmed.hasPrefix("00") { return "+\(digits.dropFirst(2))" }
        let dial = utility.countryCode(for: countryCode.uppercased()).map { String($0) } ?? ""
        return dial.isEmpty ? digits : "+\(dial)\(digits)"
    }

    /// Splits only explicit international input. National input is never guessed from its prefix.
    public static func split(_ input: String, preferredCountry: TrustPhoneCountry? = nil) -> (country: TrustPhoneCountry?, nationalNumber: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlus = trimmed.hasPrefix("+")
        let isIDD = trimmed.hasPrefix("00")
        guard isPlus || isIDD else { return (nil, input) }
        let digits = trimmed.filter(\.isNumber)
        let internationalDigits = isIDD ? String(digits.dropFirst(2)) : digits
        let matches = all.filter { internationalDigits.hasPrefix($0.callingCode) }
        guard let longestCallingCodeLength = matches.map({ $0.callingCode.count }).max() else { return (nil, input) }
        let longestMatches = matches.filter { $0.callingCode.count == longestCallingCodeLength }
        let preferred = preferredCountry.flatMap { selected in longestMatches.first { $0.code == selected.code } }
        let metadataDefault = longestMatches.first { $0.code == utility.mainCountry(forCode: UInt64($0.callingCode) ?? 0) }
        guard let selected = preferred ?? metadataDefault ?? longestMatches.sorted(by: { $0.code < $1.code }).first else {
            return (nil, input)
        }
        return (selected, String(internationalDigits.dropFirst(selected.callingCode.count)))
    }

    public static func matches(_ country: TrustPhoneCountry, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = q.filter(\.isNumber)
        return q.isEmpty
            || country.name.localizedCaseInsensitiveContains(q)
            || country.code.localizedCaseInsensitiveContains(q)
            || (!digits.isEmpty && country.callingCode.contains(digits))
    }

    public static func regionSeed(responseCode: String?, manualSelection: Bool, hasDraft: Bool) -> TrustPhoneCountry? {
        guard !manualSelection, !hasDraft else { return nil }
        return country(code: responseCode)
    }
}
