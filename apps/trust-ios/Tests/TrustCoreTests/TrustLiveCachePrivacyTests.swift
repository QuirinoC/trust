import Foundation
import XCTest
@testable import TrustCore

final class TrustLiveCachePrivacyTests: XCTestCase {
    private let accountID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testExpiredLiveBytesAreRemovedWithoutChangingAuthorizedDataOrLookReceipts() throws {
        let receipt = ["kind": "look", "id": "retained-receipt"]
        let data = try payload(members: [member(expiry: date(-1)), member(expiry: date(60))], receipts: [receipt])
        let result = try scrub(data)
        let members = try XCTUnwrap(result["members"] as? [[String: Any]])
        XCTAssertTrue(members[0]["live"] is NSNull)
        XCTAssertTrue(members[0]["trail"] is NSNull)
        XCTAssertTrue(members[0]["locationHistory"] is NSNull)
        XCTAssertNotNil(members[1]["live"] as? [String: Any])
        XCTAssertEqual(result["lookLog"] as? [[String: String]], [receipt])
    }

    func testRevokedReceiveAccessClearsRawCoordinatesButPreservesConfiguredMode() throws {
        let data = try payload(members: [member(authorized: false, expiry: date(60))])
        let result = try scrub(data)
        let members = try XCTUnwrap(result["members"] as? [[String: Any]])
        XCTAssertTrue(members[0]["live"] is NSNull)
        XCTAssertEqual((members[0]["inboundShare"] as? [String: String])?["resting"], "always")
    }

    func testAnotherAccountsCacheCannotBeRewritten() throws {
        let data = try payload(members: [member(expiry: date(-1))])
        XCTAssertNil(TrustCircleCacheMutation.scrubbingUnauthorizedLiveData(in: data, accountID: UUID(), now: now))
    }

    func testMalformedExplicitExpiryCannotBecomeAnUnlimitedGrant() throws {
        let result = try scrub(payload(members: [member(expiry: "invalid-expiry")]))
        let members = try XCTUnwrap(result["members"] as? [[String: Any]])
        XCTAssertTrue(members[0]["live"] is NSNull)
        XCTAssertTrue(members[0]["trail"] is NSNull)
    }

    func testAuthorizedGrantWithoutFiniteExpiryRemainsUsable() throws {
        let result = try scrub(payload(members: [member()]))
        let members = try XCTUnwrap(result["members"] as? [[String: Any]])
        XCTAssertNotNil(members[0]["live"] as? [String: Any])
    }

    private func member(authorized: Bool = true, expiry: String? = nil) -> [String: Any] {
        let point: [String: Any] = ["latitude": 37.1234, "longitude": -122.1234, "timestamp": date(0)]
        var value: [String: Any] = [
            "person": ["id": UUID().uuidString], "inboundLive": authorized,
            "receiveAuthorizationVersion": 1, "inboundShare": ["resting": "always"],
            "live": point, "trail": [point], "locationHistory": [point]
        ]
        if let expiry { value["liveAccessExpiresAt"] = expiry }
        return value
    }

    private func payload(members: [[String: Any]], receipts: [[String: String]] = []) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["you": ["id": accountID.uuidString], "members": members, "lookLog": receipts])
    }

    private func scrub(_ data: Data) throws -> [String: Any] {
        let sanitized = try XCTUnwrap(TrustCircleCacheMutation.scrubbingUnauthorizedLiveData(in: data, accountID: accountID, now: now))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: sanitized) as? [String: Any])
    }

    private func date(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
    }
}
