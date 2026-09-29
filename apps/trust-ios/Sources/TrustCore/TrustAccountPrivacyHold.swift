import Foundation

/// Local account gate is immediate and device-local. The server status becomes
/// acknowledged only after the matching account operation receives a success response.
public struct TrustAccountPrivacyHoldState: Equatable {
    public enum Submission: Equatable {
        case none
        case submitting
        case retryRequired
        case acknowledged
    }

    public private(set) var isLocallyRestricted = false
    public private(set) var submission: Submission = .none
    public private(set) var operation: TrustAccountOperation?

    public init() {}

    public static func isCurrentAccountHoldResponse(
        apiCode: String?,
        requestToken: String?,
        activeToken: String?
    ) -> Bool {
        apiCode == "account_privacy_hold"
            && requestToken != nil
            && requestToken == activeToken
    }

    public mutating func restrictLocally() {
        isLocallyRestricted = true
        submission = .none
        operation = nil
    }

    public mutating func beginSubmission(for operation: TrustAccountOperation) {
        isLocallyRestricted = true
        self.operation = operation
        submission = .submitting
    }

    @discardableResult
    public mutating func acknowledge(
        operation: TrustAccountOperation,
        currentToken: String?,
        generation: UInt64
    ) -> Bool {
        guard self.operation == operation,
              operation.matches(token: currentToken, generation: generation) else { return false }
        submission = .acknowledged
        return true
    }

    @discardableResult
    public mutating func failSubmission(
        operation: TrustAccountOperation,
        currentToken: String?,
        generation: UInt64
    ) -> Bool {
        guard self.operation == operation,
              operation.matches(token: currentToken, generation: generation) else { return false }
        isLocallyRestricted = true
        submission = .retryRequired
        return true
    }
}
