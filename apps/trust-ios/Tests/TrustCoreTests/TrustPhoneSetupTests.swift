import Foundation
import XCTest
@testable import TrustCore

final class TrustPhoneSetupTests: XCTestCase {
    func testCountryPhoneNormalizationAndPastedInternationalNumber() {
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("4155550100", countryCode: "US"), "+14155550100")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("+44 20 7031 3000", countryCode: "US"), "+442070313000")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("1 (201) 555-5555", countryCode: "US"), "+12015555555")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("02111961234567", countryCode: "BR"), "+5511961234567")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("011 15 2345 6789", countryCode: "AR"), "+5491123456789")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("06 20 123 4567", countryCode: "HU"), "+36201234567")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("8 916 195 55 58", countryCode: "RU"), "+79161955558")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("02 3661 8300", countryCode: "IT"), "+390236618300")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("491713369876", countryCode: "DE"), "+49491713369876")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("00442070313000", countryCode: "US"), "+442070313000")
        XCTAssertEqual(TrustPhoneCountry.canonicalNumber("415", countryCode: "US"), "+1415")
    }

    func testCountriesSharingCallingCodeRemainSelectableAndSearchable() {
        let northAmerica = TrustPhoneCountry.all.filter { $0.callingCode == "1" }
        XCTAssertTrue(northAmerica.contains(TrustPhoneCountry.unitedStates))
        XCTAssertTrue(northAmerica.contains { $0.code == "CA" })
        XCTAssertTrue(TrustPhoneCountry.matches(TrustPhoneCountry.unitedStates, query: "+1"))
        XCTAssertFalse(TrustPhoneCountry.matches(TrustPhoneCountry.unitedStates, query: "999"))
        XCTAssertEqual(TrustPhoneCountry.country(code: "gb")?.callingCode, "44")
        XCTAssertEqual(TrustPhoneCountry.regionSeed(responseCode: "CA", manualSelection: true, hasDraft: false), nil)
        XCTAssertEqual(TrustPhoneCountry.regionSeed(responseCode: "CA", manualSelection: false, hasDraft: true), nil)
        XCTAssertEqual(TrustPhoneCountry.regionSeed(responseCode: "CA", manualSelection: false, hasDraft: false)?.code, "CA")
        XCTAssertEqual(TrustPhoneCountry.split("+14155550100", preferredCountry: TrustPhoneCountry.country(code: "CA")).country?.code, "CA")
    }
    func testVerifiedPhoneAndHandleAreBothMandatory() {
        XCTAssertEqual(TrustPhoneSetupRoute.route(handle: nil, phoneVerified: false), .handle)
        XCTAssertEqual(TrustPhoneSetupRoute.route(handle: nil, phoneVerified: true), .handle)
        XCTAssertEqual(TrustPhoneSetupRoute.route(handle: "sam", phoneVerified: false), .phone)
        XCTAssertEqual(TrustPhoneSetupRoute.route(handle: "sam", phoneVerified: true), .home)
    }

    func testThreeNumbersEditRevisitAndRelaunchPreserveServerDeadlines() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = TrustPhoneRetryState()
        state.apply(phone: "+12025550101", serverTime: now, resendAt: now.addingTimeInterval(45), correctionAt: now, remaining: 2, accepted: true, now: now)
        XCTAssertEqual(state.secondsRemaining(for: "(202) 555-0101", now: now), 45)
        XCTAssertEqual(state.secondsRemaining(for: "2025550102", now: now), 0)
        state.apply(phone: "2025550102", serverTime: now, resendAt: now.addingTimeInterval(90), correctionAt: now, remaining: 1, accepted: true, now: now)
        XCTAssertEqual(state.secondsRemaining(for: "+1 (202) 555-0101", now: now), 90)
        state.apply(phone: "2025550103", serverTime: now, resendAt: now.addingTimeInterval(180), correctionAt: now.addingTimeInterval(180), remaining: 0, accepted: true, now: now)
        state = try JSONDecoder().decode(TrustPhoneRetryState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.secondsRemaining(for: "2025550104", now: now), 180)
        XCTAssertEqual(state.secondsRemaining(for: "2025550104", now: now.addingTimeInterval(179.1)), 1)
        XCTAssertEqual(state.secondsRemaining(for: "2025550104", now: now.addingTimeInterval(180)), 0)
    }

    func testClockSkewProviderFailureAndMiddlewareWaitPreserveAllowance() {
        let server = Date(timeIntervalSince1970: 1_000), device = Date(timeIntervalSince1970: 10_000)
        var state = TrustPhoneRetryState()
        state.apply(phone: "2025550101", serverTime: server, resendAt: server.addingTimeInterval(35), correctionAt: server, remaining: 2, retryAt: server.addingTimeInterval(35), accepted: true, now: device)
        XCTAssertEqual(state.secondsRemaining(for: "2025550101", now: device), 35)
        XCTAssertEqual(state.secondsRemaining(for: "2025550102", now: device), 0)
        state.globalDeadline = device.addingTimeInterval(60)
        XCTAssertEqual(state.secondsRemaining(for: "2025550102", now: device), 60)
        XCTAssertEqual(state.immediateNumbersRemaining, 2)
    }

    func testDestinationCapDoesNotBlockOtherNumbersAndLateResponsesKeepHistory() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = TrustPhoneRetryState()
        // B's second reservation returns before A's first response.
        state.apply(phone: "2025550102", serverTime: now, resendAt: now.addingTimeInterval(90), correctionAt: now,
            remaining: 1, accepted: true, now: now, accountAt: now.addingTimeInterval(90), accountWindow: now, accountCount: 2)
        state.apply(phone: "2025550101", serverTime: now.addingTimeInterval(10), resendAt: now.addingTimeInterval(45), correctionAt: now,
            remaining: 2, accepted: true, now: now.addingTimeInterval(10), accountAt: now.addingTimeInterval(45), accountWindow: now, accountCount: 1)
        XCTAssertEqual(state.immediateNumbersRemaining, 1)
        XCTAssertEqual(state.secondsRemaining(for: "2025550101", now: now.addingTimeInterval(45)), 45)
        // A destination blocked by another account must not poison A's account-level wait.
        state.apply(phone: "2025550103", serverTime: now, resendAt: now.addingTimeInterval(3600), correctionAt: now,
            remaining: 1, retryAt: now.addingTimeInterval(3600), accepted: false, now: now,
            accountAt: now.addingTimeInterval(90), accountWindow: now, accountCount: 2)
        XCTAssertEqual(state.secondsRemaining(for: "2025550101", now: now), 90)
        XCTAssertEqual(state.secondsRemaining(for: "2025550103", now: now), 3600)
    }

    func testRolloverWithUnchangedAllowanceClearsAccountHistoryButKeepsDestinationWait() {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = TrustPhoneRetryState()
        state.apply(phone: "2025550101", serverTime: now, resendAt: now.addingTimeInterval(45), correctionAt: now,
            remaining: 2, accepted: true, now: now, accountAt: now.addingTimeInterval(1), accountWindow: now.addingTimeInterval(-3599), accountCount: 1)
        let later = now.addingTimeInterval(1)
        state.apply(phone: "2025550102", serverTime: later, resendAt: later.addingTimeInterval(45), correctionAt: later,
            remaining: 2, accepted: true, now: later, accountAt: later.addingTimeInterval(45), accountWindow: later, accountCount: 1)
        XCTAssertEqual(state.attemptedNumbers, ["+12025550102"])
        XCTAssertEqual(state.secondsRemaining(for: "2025550101", now: later), 44)
        XCTAssertEqual(state.secondsRemaining(for: "2025550103", now: later), 0)
    }

    func testNewServerWindowResetsKnownHistoryAndNoCodeIsPersisted() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var state = TrustPhoneRetryState()
        state.immediateNumbersRemaining = 0
        state.attemptedNumbers = ["+12025550101", "+12025550102", "+12025550103"]
        state.apply(phone: "2025550101", serverTime: now, resendAt: now.addingTimeInterval(45), correctionAt: now, remaining: 2, accepted: true, now: now)
        XCTAssertEqual(state.attemptedNumbers, ["+12025550101"])
        XCTAssertEqual(state.secondsRemaining(for: "2025550102", now: now), 0)
        let json = String(data: try JSONEncoder().encode(state), encoding: .utf8)!
        XCTAssertFalse(json.contains("phoneCodeDraft"))
    }
}
