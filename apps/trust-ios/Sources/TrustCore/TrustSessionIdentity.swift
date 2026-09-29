import Foundation

/// Reads the server-issued account subject from a stored JWT for local cache scoping.
/// This does not validate the token; the API remains responsible for authentication.
public enum TrustSessionIdentity {
    public static func accountID(from token: String?) -> UUID? {
        guard let token else { return nil }
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }

        let payload = pieces[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddedPayload = payload.padding(
            toLength: ((payload.count + 3) / 4) * 4,
            withPad: "=",
            startingAt: 0)
        guard let data = Data(base64Encoded: paddedPayload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = claims["sub"] as? String else { return nil }
        return UUID(uuidString: subject)
    }
}
