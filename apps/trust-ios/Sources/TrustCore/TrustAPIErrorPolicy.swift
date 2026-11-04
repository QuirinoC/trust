public enum TrustAPIErrorPolicy {
    public enum Disposition: Equatable {
        case structuredPayload
        /// A gateway-class status with a decoded API code. Keep the payload for
        /// user-facing copy while retaining the offline fallback semantics.
        case structuredUnavailable
        case gatewayUnavailable
        case genericServerError
    }

    public static let appleSessionRetryDelayNanoseconds: UInt64 = 500_000_000

    public static func disposition(
        statusCode: Int,
        apiErrorCode: String?,
        hasRetryMetadata: Bool
    ) -> Disposition {
        if hasRetryMetadata {
            return .structuredPayload
        }
        if [502, 503, 504].contains(statusCode) {
            if apiErrorCode?.isEmpty == false {
                return .structuredUnavailable
            }
            return .gatewayUnavailable
        }
        if apiErrorCode?.isEmpty == false {
            return .structuredPayload
        }
        return .genericServerError
    }

    public static func shouldRetryAppleSession(
        statusCode: Int,
        apiErrorCode: String?,
        hasRetryMetadata: Bool = false
    ) -> Bool {
        guard !hasRetryMetadata, [502, 503, 504].contains(statusCode) else { return false }
        guard let apiErrorCode, !apiErrorCode.isEmpty else { return true }
        return apiErrorCode == "apple_unavailable"
    }
}
