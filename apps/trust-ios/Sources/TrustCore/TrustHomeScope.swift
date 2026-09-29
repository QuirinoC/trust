import Foundation

/// Derives device-only Home keys from the authenticated Trust account identity.
public enum TrustHomeScope {
    public static func normalizedAccountID(_ accountID: String?) -> String? {
        accountID?.lowercased()
    }

    public static func requiresSwitch(from currentAccountID: String?, to nextAccountID: String?) -> Bool {
        normalizedAccountID(currentAccountID) != normalizedAccountID(nextAccountID)
    }

    public static func key(_ field: String, accountID: String?) -> String {
        let scope = normalizedAccountID(accountID).map { "account.\($0)" } ?? "signed-out"
        return "trust.home.\(scope).\(field)"
    }
}

/// Identifies an asynchronous account operation so stale work cannot commit after a switch.
public struct TrustAccountOperation: Equatable {
    public let token: String
    public let generation: UInt64

    public init(token: String, generation: UInt64) {
        self.token = token
        self.generation = generation
    }

    public func matches(token: String?, generation: UInt64) -> Bool {
        self.token == token && self.generation == generation
    }

    /// Returns the captured bearer token only while the same account operation is active.
    public func authorizationToken(currentToken: String?, generation: UInt64) -> String? {
        matches(token: currentToken, generation: generation) ? token : nil
    }

    /// Executes a synchronous response commit only while the same account operation
    /// is active. Call on the actor that owns account state and the cache.
    @discardableResult
    public func commitIfCurrent(currentOperation: TrustAccountOperation?, _ commit: () -> Void) -> Bool {
        guard currentOperation == self else { return false }
        commit()
        return true
    }
}
