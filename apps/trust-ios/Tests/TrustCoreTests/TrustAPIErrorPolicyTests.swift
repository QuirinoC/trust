import TrustCore
import XCTest

final class TrustAPIErrorPolicyTests: XCTestCase {
    func testStructuredGatewayErrorsAreDecodedBeforeGenericGatewayFallback() {
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 503,
                apiErrorCode: "apple_unavailable",
                hasRetryMetadata: false
            ),
            .structuredUnavailable
        )
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 502,
                apiErrorCode: "otp_cooldown",
                hasRetryMetadata: true
            ),
            .structuredPayload
        )
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 504,
                apiErrorCode: nil,
                hasRetryMetadata: false
            ),
            .gatewayUnavailable
        )
    }

    func testStructuredGatewayFailureKeepsOfflineClassificationUnlessItCarriesRetryMetadata() {
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 503,
                apiErrorCode: "proxy_offline",
                hasRetryMetadata: false
            ),
            .structuredUnavailable
        )
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 503,
                apiErrorCode: "otp_cooldown",
                hasRetryMetadata: true
            ),
            .structuredPayload
        )
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 503,
                apiErrorCode: "pro_required",
                hasRetryMetadata: false
            ),
            .structuredUnavailable
        )
        XCTAssertEqual(
            TrustAPIErrorPolicy.disposition(
                statusCode: 400,
                apiErrorCode: "pro_required",
                hasRetryMetadata: false
            ),
            .structuredPayload
        )
    }

    func testAppleSessionRetryIsLimitedToOneEligibleTransientFailureClass() {
        XCTAssertTrue(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 503, apiErrorCode: nil))
        XCTAssertTrue(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 503, apiErrorCode: "apple_unavailable"))
        XCTAssertTrue(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 504, apiErrorCode: nil))

        XCTAssertFalse(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 401, apiErrorCode: "invalid_apple_token"))
        XCTAssertFalse(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 503, apiErrorCode: "invalid_apple_token"))
        XCTAssertFalse(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 503, apiErrorCode: "otp_cooldown", hasRetryMetadata: true))
        XCTAssertFalse(TrustAPIErrorPolicy.shouldRetryAppleSession(statusCode: 500, apiErrorCode: nil))
    }

    func testAppleSessionRetryDelayIsBounded() {
        XCTAssertEqual(TrustAPIErrorPolicy.appleSessionRetryDelayNanoseconds, 500_000_000)
    }
}
