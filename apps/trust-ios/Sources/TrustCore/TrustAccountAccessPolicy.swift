import Foundation

/// Keeps account features behind authentication and any server-authoritative privacy hold.
public enum TrustAccountAccessPolicy {
    public static func canAccessAccountData(
        accountAuthenticated: Bool,
        privacyHeld: Bool = false,
        localFixture: Bool = false
    ) -> Bool {
        guard !privacyHeld else { return false }
        return accountAuthenticated || localFixture
    }
}
