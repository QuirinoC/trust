import Foundation

/// Keeps authenticated account features closed until the age decision and the
/// revocation-registration prerequisite have both succeeded. An unauthenticated
/// person may still reach sign-in after age requirements permit it.
public enum TrustAccountAccessPolicy {
    public static func canAccessAccountData(
        ageAssurancePassed: Bool,
        accountAuthenticated: Bool,
        appTransactionLinked: Bool,
        localFixture: Bool = false
    ) -> Bool {
        guard ageAssurancePassed else { return false }
        guard accountAuthenticated, !localFixture else { return true }
        return appTransactionLinked
    }
}
