import Foundation

/// Safe in-app destinations for the server's push kinds. Push payloads carry no
/// coordinates or private profile data; the destination screen reloads current data.
public enum TrustPushDestination: Equatable, Sendable {
    case activity
    case people

    public init?(userInfo: [AnyHashable: Any]) {
        guard let trust = userInfo["trust"] as? [String: Any],
              let kind = trust["kind"] as? String else { return nil }
        switch kind {
        case "look": self = .activity
        case "home_arrival": self = .people
        default: return nil
        }
    }
}
