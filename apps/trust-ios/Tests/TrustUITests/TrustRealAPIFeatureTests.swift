import CoreLocation
import Foundation
import XCTest

/// Development-only end-to-end lane. It is deliberately pinned to loopback and creates
/// disposable identities that are deleted even when an assertion fails.
final class TrustRealAPIFeatureTests: XCTestCase {
    private let api = LocalTrustAPI()

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard api.hasSafeConfiguration else {
            throw XCTSkip("Set TRUST_UI_TEST_BASE_URL explicitly to the isolated HTTP loopback API on port 5089. Skipping before account creation or phone-send requests.")
        }
        guard api.healthIsAvailable() else {
            throw XCTSkip("The isolated local API on port 5089 is unavailable; skipping its opt-in simulator lane.")
        }
        guard api.developmentOTPWithoutSMSIsEnabled() else {
            throw XCTSkip("The local API is not Development with Twilio unconfigured. Skipping before account creation or any phone-send request.")
        }
    }

    override func tearDown() {
        if api.raceProxyState()?["holding"] as? Bool == true {
            _ = api.releaseHeldResponse()
        }
        api.resetRaceProxy()
        super.tearDown()
    }

    func testRequiredPhoneCorrectionsCooldownEditRelaunchAndReturningVerifiedAccount() throws {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let deviceID = "phone-setup-\(suffix)"
        let session = try XCTUnwrap(api.developmentSession(name: "Phone setup", deviceID: deviceID))
        defer { api.deleteAccount(token: session.token) }
        XCTAssertEqual(api.request("PUT", "/api/v1/me/handle", token: session.token, body: ["handle": "ph\(suffix)"]).status, 204)
        let numbers = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(4))
        let app = launchDevelopmentApp(deviceID: deviceID, displayName: "Phone setup", arguments: ["-appearancePreference", "light", "-trust.appLanguage", "en"])
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["phone-number"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["tab-sharing"].exists)
        XCTAssertFalse(app.buttons["return-to-app-from-phone-verification"].exists)
        var lastCode = ""
        for (index, number) in numbers.prefix(3).enumerated() {
            let field = app.textFields["phone-number"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            let current = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + "+1\(number)")
            XCTAssertFalse(app.textFields["phone-code"].exists, "Typing never sends a text.")
            let send = app.buttons["send-phone-code"]
            XCTAssertTrue(send.isEnabled, "First number and two distinct corrections must be immediately available.")
            send.tap()
            XCTAssertTrue(app.textFields["phone-code"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["phone-notice"].waitForExistence(timeout: 5))
            lastCode = app.staticTexts["phone-notice"].label.filter(\.isNumber)
            XCTAssertEqual(lastCode.count, 6)
            XCTAssertFalse(app.buttons["send-phone-code"].isEnabled)
            XCTAssertTrue(app.buttons["edit-phone-number"].isEnabled)
            XCTAssertTrue(app.buttons["edit-phone-number"].isHittable)
            XCTAssertFalse(app.buttons["tab-sharing"].exists)
            if index < 2 { app.buttons["edit-phone-number"].tap() }
        }
        let code = app.textFields["phone-code"]
        code.tap()
        code.typeText(lastCode)
        XCTAssertTrue(app.buttons["verify-phone-code"].isEnabled, "Send cooldown must not block Verify.")
        attachScreenshot(of: app, named: "Phone - Third code countdown light")
        app.terminate()
        app.launchArguments = ["-appearancePreference", "dark", "-trust.appLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.textFields["phone-code"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields["phone-code"].value as? String, "123456", "Relaunch must not persist the OTP.")
        XCTAssertTrue(app.buttons["edit-phone-number"].isEnabled)
        attachScreenshot(of: app, named: "Phone - Restored code countdown dark")
        app.buttons["edit-phone-number"].tap()
        XCTAssertTrue(app.textFields["phone-number"].waitForExistence(timeout: 5))
        let fourth = app.textFields["phone-number"]
        fourth.tap()
        fourth.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (fourth.value as? String ?? "").count) + "+1\(numbers[3])")
        XCTAssertFalse(app.buttons["send-phone-code"].isEnabled, "A fourth distinct number must wait too.")
        XCTAssertTrue(app.staticTexts["phone-retry-notice"].exists)
        attachScreenshot(of: app, named: "Phone - Edit countdown dark")
        app.terminate()
        app.launchArguments = ["-appearancePreference", "dark", "-trust.appLanguage", "en"]
        app.launch()
        XCTAssertTrue(app.textFields["phone-number"].waitForExistence(timeout: 15))
        let field = app.textFields["phone-number"]
        field.tap()
        field.typeText("+1\(numbers[3])")
        XCTAssertFalse(app.buttons["send-phone-code"].isEnabled, "The account retry deadline must survive relaunch.")
        attachScreenshot(of: app, named: "Phone - Persisted countdown dark")
        // Complete the already-sent challenge on the local Development API, then relaunch
        // the same server-verified identity to prove setup does not request another SMS.
        XCTAssertEqual(api.request("POST", "/api/v1/me/phone/verify", token: session.token,
            body: ["phone": "+1\(numbers[2])", "code": lastCode]).status, 204)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["phone-number"].exists)
        XCTAssertEqual((api.circle(token: session.token)?["you"] as? [String: Any])?["phoneVerified"] as? Bool, true)
    }

    func testLatePhoneResponsesAfterEditPreserveRetryWithoutOpeningCodeOrHome() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated loopback fault proxy.") }
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let deviceID = "phone-race-\(suffix)"
        let session = try XCTUnwrap(api.developmentSession(name: "Phone race", deviceID: deviceID))
        defer { api.deleteAccount(token: session.token) }
        XCTAssertEqual(api.request("PUT", "/api/v1/me/handle", token: session.token, body: ["handle": "pr\(suffix)"]).status, 204)
        let numbers = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let app = launchDevelopmentApp(deviceID: deviceID, displayName: "Phone race")
        defer { app.terminate() }
        let field = app.textFields["phone-number"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        func enter(_ value: String) {
            field.tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String ?? "").count) + value)
        }
        enter("+1\(numbers[0])")
        XCTAssertEqual(api.request("POST", "/__test/arm-phone-send").status, 200)
        app.buttons["send-phone-code"].tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { $0["held_resource"] as? String == "phone_send" })
        enter("+1\(numbers[1])")
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitUntil(timeout: 5) { app.buttons["send-phone-code"].isEnabled })
        XCTAssertFalse(app.textFields["phone-code"].exists)
        enter("+1\(numbers[0])")
        XCTAssertFalse(app.buttons["send-phone-code"].isEnabled, "The late accepted reservation must retain its retry deadline.")
        enter("+1\(numbers[1])")
        XCTAssertTrue(app.buttons["send-phone-code"].isEnabled)
        app.buttons["send-phone-code"].tap()
        let code = app.textFields["phone-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        let digits = app.staticTexts["phone-notice"].label.filter(\.isNumber)
        code.tap(); code.typeText(digits)
        XCTAssertEqual(api.request("POST", "/__test/arm-phone-verify").status, 200)
        app.buttons["verify-phone-code"].tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { $0["held_resource"] as? String == "phone_verify" })
        app.buttons["edit-phone-number"].tap()
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tab-sharing"].exists)
        attachScreenshot(of: app, named: "Phone - Late verification remains on edited entry")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15), "A new session fetch may use the server-verified account.")
    }

    func testManualHomeChoicesReachServerAndRetirePreviousNotice() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated loopback fault proxy.") }
        let fixture = try makeConnectedFixture(prefix: "home-notice")
        defer {
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        let control = app.buttons["home-status-control"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        api.resetRaceProxy()
        var previousNotice: String?
        for (index, state) in ["home", "away", "hidden", "home", "away", "hidden"].enumerated() {
            XCTAssertTrue(scrollUpUntilHittable(control, in: app))
            XCTAssertEqual(api.request("POST", "/__test/arm-home-presence").status, 200)
            control.tap()
            let choice = app.buttons.matching(identifier: "set-home-status-\(state)").firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            XCTAssertTrue(choice.isEnabled && choice.isHittable)
            // One native-element tap, deliberately matching the original Home attempt.
            choice.tap()
            XCTAssertTrue(waitForProxyState(timeout: 8) { $0["held_resource"] as? String == "home_presence" }, "Attempt \(index + 1) \(state): \(api.raceProxyState() ?? [:]); \(app.debugDescription)")
            if let previousNotice {
                attachScreenshot(of: app, named: "Home notice - pending \(state) attempt \(index + 1)")
                XCTAssertFalse(app.staticTexts[previousNotice].exists, "A previous status acknowledgement must retire when another choice is pending.")
            }
            XCTAssertFalse(choice.exists, "The native menu must dismiss after its single tap.")
            XCTAssertEqual(yourHomeState(token: fixture.main.token), state)
            let proxy = try XCTUnwrap(api.raceProxyState())
            XCTAssertEqual((proxy["request_counts"] as? [String: Int])?["POST /api/v1/me/home/presence"], index + 1)
            XCTAssertEqual((proxy["home_presence_responses"] as? [String: Int])?["204"], index + 1)
            let evidence = XCTAttachment(string: "Attempt \(index + 1): \(state), one tap, server state \(state), requests/responses \(proxy)")
            evidence.lifetime = .keepAlways
            add(evidence)
            XCTAssertTrue(api.releaseHeldResponse())
            let notice = state == "hidden" ? "Status hidden." : "Status set to \(state.capitalized)."
            XCTAssertTrue(app.staticTexts[notice].waitForExistence(timeout: 5), app.debugDescription)
            previousNotice = notice
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertTrue(control.label.contains("Hidden"))
        XCTAssertEqual(yourHomeState(token: fixture.main.token), "hidden")
    }

    func testAdultAgeGateAppleExchangeFailureCanRetryThroughTransactionLinkIntoOnboarding() throws {
        try requireAgeAssuranceFaultProxy()
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-age-signin-\(suffix.prefix(12))"
        let displayName = "AgeSignIn\(suffix.prefix(6))"
        api.resetRaceProxy()
        XCTAssertTrue(api.armAppTransactionFixture(retry: false))

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = displayName
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_FAKE_APPLE_AUTH"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_APPLE_EXCHANGE_FAILURE_ONCE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_APP_TRANSACTION_PROXY"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_AUTH")

        let month = app.textFields["age-birth-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 15), app.debugDescription)
        for (field, value) in [
            (month, "01"),
            (app.textFields["age-birth-day"], "01"),
            (app.textFields["age-birth-year"], "1990")
        ] {
            XCTAssertTrue(field.waitForExistence(timeout: 5), app.debugDescription)
            field.tap()
            field.typeText(value)
        }
        let continueAge = app.buttons["age-gate-continue"]
        XCTAssertTrue(waitUntil(timeout: 5) { continueAge.isEnabled })
        continueAge.tap()

        let appleSignIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Apple")).firstMatch
        XCTAssertTrue(appleSignIn.waitForExistence(timeout: 15), app.debugDescription)
        appleSignIn.tap()
        let loginNotice = app.staticTexts["login-notice"]
        XCTAssertTrue(loginNotice.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(loginNotice.label.localizedCaseInsensitiveContains("could not verify this sign-in"), loginNotice.label)
        XCTAssertTrue(appleSignIn.exists, "An Apple token exchange failure must keep the person on Login so they can retry.")
        XCTAssertFalse(app.switches["onboarding-discovery-toggle"].exists)

        appleSignIn.tap()
        XCTAssertTrue(
            app.switches["onboarding-discovery-toggle"].waitForExistence(timeout: 20),
            "After retry, the test identity must complete Apple sign-in, transaction registration, and reach real handle onboarding.\n\(app.debugDescription)"
        )
        XCTAssertFalse(loginNotice.exists)
        let state = try XCTUnwrap(api.raceProxyState())
        let counts = state["request_counts"] as? [String: Int] ?? [:]
        XCTAssertEqual(counts["POST /api/v1/session/apple"], 1, "The first Apple exchange must reach the local API and fail.")
        XCTAssertEqual(counts["POST /api/v1/session/development"], 1, "Only the explicit retry fixture may create its local Apple-provider account.")
        XCTAssertEqual(counts["PUT /api/v1/age-assurance/app-transaction"], 1)
        XCTAssertGreaterThan(counts["GET /api/v1/circle"] ?? 0, 0, "The account read must happen only after successful transaction registration.")
        XCTAssertEqual(state["app_transaction_success_count"] as? Int, 1)

        let session = try XCTUnwrap(api.developmentSession(name: displayName, deviceID: deviceID, provider: "apple"))
        defer {
            app.terminate()
            api.deleteAccount(token: session.token)
        }
        let profile = api.circle(token: session.token)?["you"] as? [String: Any]
        XCTAssertEqual(profile?["onboardingComplete"] as? Bool, false)
    }

    func testAppTransactionRetryKeepsRequestsClosedThenRecoversAcrossRelaunch() throws {
        try requireAgeAssuranceFaultProxy()
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-age-retry-\(suffix.prefix(12))"
        let displayName = "AgeRetry\(suffix.prefix(6))"
        let session = try XCTUnwrap(api.developmentSession(name: displayName, deviceID: deviceID, provider: "apple"))
        defer { api.deleteAccount(token: session.token) }
        let handle = "age\(suffix.prefix(12))"
        XCTAssertEqual(api.putHandle(handle, token: session.token), 204)
        let phone = try XCTUnwrap(LocalTrustAPI.reservedPhonePool().randomElement())
        XCTAssertTrue(api.verifyPhone(phone: "+1\(phone)", token: session.token))

        api.resetRaceProxy()
        XCTAssertTrue(api.armAppTransactionFixture(retry: true))
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = displayName
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_ADULT"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_AUTHENTICATED"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_SESSION_TOKEN"] = session.token
        app.launchEnvironment["TRUST_AGE_TEST_APP_TRANSACTION_PROXY"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_AUTH")

        assertAppTransactionUnavailable(in: app)
        assertNoAccountWork(api.raceProxyState(), file: #filePath, line: #line)
        element("app-transaction-retry", in: app).tap()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20), app.debugDescription)

        var state = try XCTUnwrap(api.raceProxyState())
        XCTAssertEqual(state["app_transaction_request_count"] as? Int, 2)
        XCTAssertEqual(state["app_transaction_failure_count"] as? Int, 1)
        XCTAssertEqual(state["app_transaction_success_count"] as? Int, 1)
        var counts = state["request_counts"] as? [String: Int] ?? [:]
        XCTAssertGreaterThan(counts["GET /api/v1/circle"] ?? 0, 0, "The first account read should occur after transaction registration recovers.")
        XCTAssertEqual(counts["POST /api/v1/location"], nil)
        XCTAssertEqual(counts["POST /api/v1/push/devices"], nil)

        app.terminate()
        api.resetRaceProxy()
        XCTAssertTrue(api.armAppTransactionFixture(retry: false))
        app.launch()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20), app.debugDescription)
        state = try XCTUnwrap(api.raceProxyState())
        counts = state["request_counts"] as? [String: Int] ?? [:]
        XCTAssertEqual(state["app_transaction_request_count"] as? Int, 1)
        XCTAssertEqual(state["app_transaction_success_count"] as? Int, 1)
        XCTAssertGreaterThan(counts["GET /api/v1/circle"] ?? 0, 0, "A relaunch must re-establish transaction linkage before restoring account data.")
        XCTAssertEqual(counts["POST /api/v1/location"], nil)
        XCTAssertEqual(counts["POST /api/v1/push/devices"], nil)
        app.terminate()
    }

    func testAgeAndPrivacyBlocksSuppressAccountLocationAndPushRequests() throws {
        try requireAgeAssuranceFaultProxy()
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let session = try XCTUnwrap(api.developmentSession(name: "Blocked\(suffix.prefix(6))", deviceID: "trust-age-block-\(suffix.prefix(12))"))
        defer { api.deleteAccount(token: session.token) }

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_AUTHENTICATED"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_SESSION_TOKEN"] = session.token
        app.launchEnvironment["TRUST_AGE_TEST_UNAVAILABLE"] = "1"

        for fixture in ["TRUST_AGE_TEST_UNAVAILABLE", "TRUST_AGE_TEST_PRIVACY_HELD"] {
            app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_UNAVAILABLE")
            app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_PRIVACY_HELD")
            app.launchEnvironment[fixture] = "1"
            api.resetRaceProxy()
            app.launch()
            if fixture == "TRUST_AGE_TEST_UNAVAILABLE" {
                assertUnavailableAgeCheck(in: app)
            } else {
                XCTAssertTrue(element("age-privacy-hold-delete-account", in: app).waitForExistence(timeout: 15))
            }
            XCTAssertFalse(element("tab-circle", in: app).exists)
            assertNoAccountWork(api.raceProxyState(), file: #filePath, line: #line)
            app.terminate()
            app.launchEnvironment.removeValue(forKey: fixture)
        }
    }

    /// Paired acceptance prototype. Run this case simultaneously in two independent
    /// XCTest processes with the same pair ID and roles alice/bob. The accounts are
    /// created from their own app UI; the local API resolves the peer's public handle.
    func testPairedRequestAcceptAndPresenceGrantRole() throws {
        // The pair receives moving Core Simulator routes configured by the harness
        // before launch; this diagnostic uses no XCTest static location override.
        let environment = ProcessInfo.processInfo.environment
        guard let role = environment["TRUST_UI_PAIR_ROLE"], ["alice", "bob"].contains(role),
              let pairID = environment["TRUST_UI_PAIR_ID"], pairID.range(of: "^[a-f0-9]{8}$", options: .regularExpression) != nil else {
            throw XCTSkip("Set TRUST_UI_PAIR_ROLE=alice|bob and one shared eight-hex TRUST_UI_PAIR_ID in both simulator launchd environments.")
        }

        let aliceHandle = "pa\(pairID)a"
        let bobHandle = "pa\(pairID)b"
        let ownHandle = role == "alice" ? aliceHandle : bobHandle
        let peerHandle = role == "alice" ? bobHandle : aliceHandle
        let ownName = role == "alice" ? "PairAlice" : "PairBob"
        let deviceID = "trust-pair-\(pairID)-\(role)"
        let session = try XCTUnwrap(api.developmentSession(name: ownName, deviceID: deviceID))
        // The pair shares server state while the other simulator's UI is still
        // refreshing. The isolated Memory API is stopped after both runners exit.

        let pool = LocalTrustAPI.reservedPhonePool()
        let pairPhoneBase = Int(pairID.prefix(6), radix: 16)! % (pool.count / 2) * 2
        let slot = pairPhoneBase + (role == "alice" ? 0 : 1)
        let phoneDigits = pool[slot]
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = ownName
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        configureLocalAgeFixture(for: app)
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        completeLocalAgeFixture(in: app)

        let handleField = app.textFields.firstMatch
        XCTAssertTrue(handleField.waitForExistence(timeout: 20))
        handleField.tap()
        let suggested = handleField.value as? String ?? ""
        handleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: suggested.count) + ownHandle)
        let continueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Continue")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { continueButton.isEnabled })
        let discoveryToggle = app.switches["onboarding-discovery-toggle"]
        XCTAssertTrue(discoveryToggle.waitForExistence(timeout: 5))
        if !isSwitchOn(discoveryToggle) {
            discoveryToggle.tap()
            XCTAssertTrue(waitUntil(timeout: 5) { self.isSwitchOn(discoveryToggle) }, "Phone discovery should be explicitly enabled before continuing.")
        }
        continueButton.tap()
        let phone = app.textFields["phone-number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        phone.tap()
        phone.typeText("+1\(phoneDigits)")
        app.buttons["send-phone-code"].tap()
        let codeNotice = app.staticTexts["phone-notice"]
        XCTAssertTrue(codeNotice.waitForExistence(timeout: 10))
        let code = codeNotice.label.filter(\.isNumber)
        XCTAssertEqual(code.count, 6)
        let codeField = app.textFields["phone-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText(code)
        app.buttons["verify-phone-code"].tap()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        let ownAccount = api.circle(token: session.token)?["you"] as? [String: Any]
        XCTAssertEqual(ownAccount?["handle"] as? String, ownHandle)
        XCTAssertEqual(ownAccount?["onboardingComplete"] as? Bool, true, "The API peer should see this simulator account as fully onboarded.")
        XCTAssertEqual(ownAccount?["phoneVerified"] as? Bool, true)
        XCTAssertEqual(ownAccount?["discoveryEnabled"] as? Bool, true, "The test explicitly opts into discoverability on both accounts.")
        app.buttons["tab-you"].tap()
        let ownHandleButton = app.buttons["copy-own-handle"]
        XCTAssertTrue(ownHandleButton.waitForExistence(timeout: 10))
        XCTAssertEqual(ownHandleButton.value as? String, "@\(ownHandle)", "This simulator's UI must remain signed into its own paired identity.")

        if role == "alice" {
            var peerLookup = api.lookupPersonResponse(handle: peerHandle, token: session.token)
            // Handle discovery is intentionally rate-limited (60 searches/minute).
            // Poll slowly and reuse the successful response instead of immediately
            // spending another request from the same budget to fetch the account ID.
            let resolvedPeer = waitUntil(timeout: 60, pollInterval: 2) {
                peerLookup = self.api.lookupPersonResponse(handle: peerHandle, token: session.token)
                return (200..<300).contains(peerLookup.status)
                    && (peerLookup.json as? [String: Any])?["accountId"] as? String != nil
            }
            XCTAssertTrue(resolvedPeer, "Bob's handle should resolve after onboarding. API response: HTTP \(peerLookup.status) \(String(describing: peerLookup.json)); Alice state: \(String(describing: ownAccount))")
            guard let peerID = (peerLookup.json as? [String: Any])?["accountId"] as? String else { XCTFail("Bob's public handle should resolve after onboarding."); return }
            app.buttons["tab-sharing"].tap()
            let add = app.buttons["add-someone-button"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let phoneLookup = app.textFields["connection-handle"]
            XCTAssertTrue(phoneLookup.waitForExistence(timeout: 8))
            // The paired request uses Bob's verified phone number. Cancellation is
            // covered in the single-UI test, where the peer cannot race acceptance.
            let bobPhoneDigits = pool[pairPhoneBase + 1]
            phoneLookup.typeText("+1 (\(bobPhoneDigits.prefix(3))) \(bobPhoneDigits.dropFirst(3).prefix(3))-\(bobPhoneDigits.suffix(4))")
            XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 12), "A verified exact phone match should resolve to Bob's handle.")
            XCTAssertEqual(app.staticTexts["connection-lookup-handle"].label, "@\(peerHandle)")
            let keyboardDone = app.buttons["Done"]
            if keyboardDone.exists { keyboardDone.tap() }
            let sendRequest = app.buttons["send-connection-request"]
            XCTAssertTrue(sendRequest.waitForExistence(timeout: 5))
            sendRequest.tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                let pending = !(self.api.connectionRequests(token: session.token)?["sent"] as? [[String: Any]] ?? []).isEmpty
                return pending || self.api.member(personID: peerID, token: session.token) != nil
            }, "Sending by phone should create a pending request or Bob should already have accepted it.")
            app.buttons["cancel-add-person"].tap()
            XCTAssertTrue(waitUntil(timeout: 90) { self.api.member(personID: peerID, token: session.token) != nil }, "Bob's UI did not accept the request.")

            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let refreshStartedAt = Date()
            app.swipeDown()
            let memberGroup = app.descendants(matching: .any)["sharing-mode-group-pairbob"]
            XCTAssertTrue(memberGroup.waitForExistence(timeout: 20), "Alice's UI should show Bob after Bob accepts.\n\(app.debugDescription)")
            self.add(XCTAttachment(string: "Alice's Sharing list converged after pull-to-refresh in \(Date().timeIntervalSince(refreshStartedAt)) seconds."))
            let peerNameKey = "pairbob"
            let actions = app.buttons["sharing-actions-\(peerNameKey)"]
            XCTAssertTrue(actions.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(api.member(personID: peerID, token: session.token)?["outboundPresenceGranted"] as? Bool ?? true)
            actions.tap()
            let grant = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Let PairBob know when I’m Home or Away")).firstMatch
            XCTAssertTrue(grant.waitForExistence(timeout: 5))
            grant.tap()
            XCTAssertTrue(waitUntil(timeout: 10) { self.api.member(personID: peerID, token: session.token)?["outboundPresenceGranted"] as? Bool == true })
            XCTAssertTrue(app.staticTexts["Home/Away sharing preference updated."].waitForExistence(timeout: 15), "Wait for the first grant write and refresh to finish before changing the choice again.")
            let sealed = app.buttons["sharing-mode-sealed-pairbob"]
            XCTAssertTrue(sealed.waitForExistence(timeout: 8))
            sealed.tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                self.outboundPresentation(personID: peerID, token: session.token) == "untilTheyLook"
            }, "Alice must choose Sealed before Bob can see her Home/Away status.")
            allowBackgroundLocationIfPrompted(in: app)
            // Mirror Bob's authenticated session so the UI test waits for each
            // Alice status change to become visible to the actual recipient.
            let bobSession = try XCTUnwrap(api.developmentSession(
                name: "PairBob",
                deviceID: "trust-pair-\(pairID)-bob"
            ))
            XCTAssertEqual(bobSession.personID, peerID)
            let homeStatus = app.buttons["home-status-control"]
            XCTAssertTrue(homeStatus.waitForExistence(timeout: 10))
            XCTAssertTrue(scrollUpUntilHittable(homeStatus, in: app), app.debugDescription)
            XCTAssertTrue(waitUntil(timeout: 240) {
                self.yourHomeState(token: bobSession.token) == "hidden"
            }, "Bob must finish Look and Home set/clear and publish the Hidden readiness barrier before Alice starts her Home/Away/Hidden sequence.")

            for state in ["home", "away", "hidden"] {
                XCTAssertTrue(scrollUpUntilHittable(homeStatus, in: app), app.debugDescription)
                homeStatus.tap()
                let choice = app.buttons.matching(identifier: "set-home-status-\(state)").firstMatch
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "The Sharing status menu should offer \(state).")
                XCTAssertTrue(choice.isEnabled && choice.isHittable, app.debugDescription)
                choice.tap()
                XCTAssertTrue(waitUntil(timeout: 5) { !choice.exists }, "The selected status menu should dismiss.")
                attachScreenshot(of: app, named: "Alice - Selected \(state)")
                XCTAssertTrue(waitUntil(timeout: 15) { self.yourHomeState(token: session.token) == state }, "Alice's selected status should persist as \(state).")
                if state == "hidden" {
                    XCTAssertTrue(waitUntil(timeout: 30) {
                        let response = self.api.memberResponse(personID: session.personID, token: bobSession.token)
                        guard (200..<300).contains(response.status),
                              let member = response.member,
                              member["inboundPresenceGranted"] as? Bool == true else { return false }
                        // A successful recipient response must still include Alice;
                        // Hidden is proven only when that member has no visible
                        // Home/Away payload, not when the request or lookup fails.
                        return member["homePresence"] == nil || member["homePresence"] is NSNull
                    }, "Hidden should suppress Alice's status for Bob while the explicit grant and Sealed mode remain active.")
                } else {
                    XCTAssertTrue(waitUntil(timeout: 30) {
                        self.visibleHomePresence(personID: session.personID, token: bobSession.token) == state
                    }, "Bob should see Alice's \(state.capitalized) status through his own circle response.")
                }
                XCTAssertTrue(waitUntil(timeout: 30) {
                    self.yourHomeState(token: bobSession.token) == state
                }, "Wait for Bob's same-state API acknowledgement before Alice changes her status again.")
            }
            XCTAssertTrue(homeStatus.label.contains("Hidden"), "Alice's Sharing control should reflect the final Hidden choice.")

            let originalConnectionID = try XCTUnwrap(api.member(personID: peerID, token: session.token)?["connectionId"] as? String)
            XCTAssertFalse(originalConnectionID.isEmpty)
            XCTAssertTrue(waitUntil(timeout: 20) {
                let response = self.api.memberResponse(personID: session.personID, token: bobSession.token)
                return (200..<300).contains(response.status) && response.member?["connectionId"] as? String == originalConnectionID
            }, "Bob's successful circle response should carry the same active connection ID.")
            XCTAssertTrue(waitUntil(timeout: 30) { self.inboundPresentation(personID: peerID, token: session.token) == "off" }, "Wait until Bob's UI Stop has taken effect before Alice removes him.")
            XCTAssertTrue(actions.waitForExistence(timeout: 8))
            actions.tap()
            let remove = app.buttons["remove-person-action-pairbob"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
            let confirmRemove = app.buttons.matching(identifier: "remove-person-confirm")
            XCTAssertTrue(confirmRemove.firstMatch.waitForExistence(timeout: 5))
            confirmRemove.element(boundBy: 0).tap()
            XCTAssertTrue(waitUntil(timeout: 20) {
                self.successfulCircleOmitsMember(personID: peerID, token: session.token)
                    && self.successfulCircleOmitsMember(personID: session.personID, token: bobSession.token)
            }, "Removal must be reflected by successful decoded circle responses for both accounts.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let bobGroup = app.descendants(matching: .any)["sharing-mode-group-pairbob"]
            XCTAssertTrue(waitUntil(timeout: 15) { !bobGroup.exists }, "Alice's refreshed Sharing list should remove Bob.")
            attachScreenshot(of: app, named: "Pair lifecycle - Alice removed Bob")

            XCTAssertTrue(waitUntil(timeout: 90) { !(self.api.connectionRequests(token: session.token)?["incoming"] as? [[String: Any]] ?? []).isEmpty }, "Bob should send Alice a fresh request by phone after removal.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let acceptAgain = app.buttons["accept-connection-request-\(bobHandle)"]
            XCTAssertTrue(acceptAgain.waitForExistence(timeout: 15), "Alice should refresh Sharing to render Bob's new incoming request.\n\(app.debugDescription)")
            // Bob changes his real Sharing status to Away only after his UI has
            // rendered the Sent row. Wait for that API-visible acknowledgement
            // before accepting so the paired test cannot race through the state.
            XCTAssertTrue(waitUntil(timeout: 240) {
                self.yourHomeState(token: bobSession.token) == "away"
            }, "Bob's UI should acknowledge seeing the pending Sent row before Alice accepts it.")
            acceptAgain.tap()
            XCTAssertTrue(waitUntil(timeout: 90) { self.activeConnectionID(personID: peerID, token: session.token).map { $0 != originalConnectionID } == true }, "Acceptance should produce a nonempty new connection ID.")
            let reconnectedGroup = app.descendants(matching: .any)["sharing-mode-group-pairbob"]
            XCTAssertTrue(reconnectedGroup.waitForExistence(timeout: 20), "Alice's UI should show Bob after accepting the new request.")
            let reconnectedOff = app.buttons["sharing-mode-off-pairbob"]
            XCTAssertTrue(reconnectedOff.waitForExistence(timeout: 8))
            XCTAssertTrue(reconnectedOff.isSelected, "Alice's reconnected row should visibly start Off.")
            attachScreenshot(of: app, named: "Pair lifecycle - Alice reconnected Off")
            try assertReconnectedPair(
                ownToken: session.token, peerToken: bobSession.token,
                ownID: session.personID, peerID: peerID, originalConnectionID: originalConnectionID
            )

        } else {
            XCTAssertTrue(waitUntil(timeout: 90) { !(self.api.connectionRequests(token: session.token)?["incoming"] as? [[String: Any]] ?? []).isEmpty }, "Alice's UI did not send a request.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let accept = app.buttons["accept-connection-request-\(aliceHandle)"]
            XCTAssertTrue(accept.waitForExistence(timeout: 15))
            accept.tap()
            guard let aliceID = api.lookupPerson(handle: peerHandle, token: session.token) else { XCTFail("Alice's public handle should resolve after onboarding."); return }
            XCTAssertTrue(waitUntil(timeout: 15) { self.api.member(personID: aliceID, token: session.token) != nil })
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let refreshStartedAt = Date()
            app.swipeDown()
            let memberGroup = app.descendants(matching: .any)["sharing-mode-group-pairalice"]
            XCTAssertTrue(memberGroup.waitForExistence(timeout: 20), "Bob's UI should show Alice after accepting.\n\(app.debugDescription)")
            self.add(XCTAttachment(string: "Bob's Sharing list converged after pull-to-refresh in \(Date().timeIntervalSince(refreshStartedAt)) seconds."))

            let sealed = app.buttons["sharing-mode-sealed-pairalice"]
            XCTAssertTrue(sealed.waitForExistence(timeout: 10), app.debugDescription)
            sealed.tap()
            XCTAssertTrue(waitUntil(timeout: 10) { self.outboundPresentation(personID: aliceID, token: session.token) == "untilTheyLook" }, "Bob's UI should update Bob→Alice, visible as outboundShare in Bob's circle response.")
            allowBackgroundLocationIfPrompted(in: app)

            let aliceSession = try XCTUnwrap(api.developmentSession(
                name: "PairAlice",
                deviceID: "trust-pair-\(pairID)-alice"
            ))
            XCTAssertEqual(aliceSession.personID, aliceID, "The recipient observer must be the same Alice account that completed UI onboarding.")
            XCTAssertTrue(waitUntil(timeout: 30) {
                guard let member = self.api.member(personID: aliceID, token: session.token) else { return false }
                return member["inboundPresenceGranted"] as? Bool == true
                    && member["outboundPresenceGranted"] as? Bool == false
            }, "Bob's circle response should first show Alice's one-way grant from her Sharing UI, while Bob's reciprocal grant is still off.")
            // SwiftUI Menu drops the nested identifier in the native menu host.
            // Match its visible accessibility label, as in the single-app flow,
            // so Bob makes the reciprocal choice through his own Sharing UI.
            let alicePresenceGrant = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Let PairAlice know when I’m Home or Away")
            ).firstMatch
            let aliceActions = app.buttons["sharing-actions-pairalice"]
            XCTAssertTrue(aliceActions.waitForExistence(timeout: 8), app.debugDescription)
            aliceActions.tap()
            XCTAssertTrue(alicePresenceGrant.waitForExistence(timeout: 5), "Bob's native Sharing menu should expose the visible grant action.\n\(app.debugDescription)")
            alicePresenceGrant.tap()
            XCTAssertTrue(app.staticTexts["Home/Away sharing preference updated."].waitForExistence(timeout: 15), "Bob's UI should acknowledge the reciprocal grant write.")
            XCTAssertTrue(waitUntil(timeout: 30) {
                let bobView = self.api.memberResponse(personID: aliceID, token: session.token)
                let aliceView = self.api.memberResponse(personID: session.personID, token: aliceSession.token)
                guard (200..<300).contains(bobView.status), (200..<300).contains(aliceView.status),
                      let bobMember = bobView.member, let aliceMember = aliceView.member else { return false }
                return bobMember["outboundPresenceGranted"] as? Bool == true
                    && bobMember["inboundPresenceGranted"] as? Bool == true
                    && aliceMember["inboundPresenceGranted"] as? Bool == true
            }, "Successful circle responses for Bob and Alice should show both explicit grant directions after Bob's UI action.")

            // This Sealed Look is a real recipient UI action, not an API fixture. With
            // an isolated Memory API, Bob's test role can confirm the receipt after
            // the app displays the one-time snapshot. A missing Core Location upload
            // makes the Look endpoint reject with no_location.
            XCTAssertTrue(waitUntil(timeout: 30) {
                let member = self.api.member(personID: aliceID, token: session.token)
                return (member?["inboundShare"] as? [String: Any])?["presentation"] as? String == "untilTheyLook"
            }, "Alice must be Sealed toward Bob before Bob requests a Look.")
            XCTAssertFalse(api.hasLookEvent(subjectID: aliceID, token: session.token), "The fresh pair should not already contain a Look receipt for Alice.")
            app.buttons["tab-circle"].tap()
            // API state is authoritative, but Bob may already have a cached Circle
            // snapshot from before Alice chose Sealed. Refresh the recipient's
            // People list before opening the profile so the UI exercises the same
            // state the API assertion just observed.
            app.swipeDown()
            let aliceRow = app.buttons["person-row-pairalice"]
            XCTAssertTrue(aliceRow.waitForExistence(timeout: 15), "Bob's People list should show Alice before Look.\n\(app.debugDescription)")
            aliceRow.tap()
            let sharingDirections = app.staticTexts["person-sharing-directions"]
            XCTAssertTrue(waitUntil(timeout: 15) {
                sharingDirections.exists && sharingDirections.label.contains("They share with you: Sealed")
            }, "Bob's refreshed person screen should show Alice's inbound Sealed sharing before offering Look.\n\(app.debugDescription)")
            let lookAction = app.buttons["person-profile-peek"]
            XCTAssertTrue(lookAction.waitForExistence(timeout: 10), "A Sealed person should offer the notify-first Look action.")
            lookAction.tap()
            let confirmLook = app.buttons["confirm-look-notify"]
            XCTAssertTrue(confirmLook.waitForExistence(timeout: 8))
            confirmLook.tap()
            XCTAssertTrue(app.buttons["view-open-map"].waitForExistence(timeout: 20), "Bob should open the API-backed Look snapshot, not just see the pre-Look explanation.\n\(app.debugDescription)")
            XCTAssertTrue(waitUntil(timeout: 20) { self.api.hasLookEvent(subjectID: aliceID, token: session.token) }, "The API should record Bob's real UI Look for Alice.")
            let lookEvent = try XCTUnwrap(api.latestLookEvent(subjectID: aliceID, token: session.token))
            XCTAssertEqual(lookEvent["kind"] as? String, "look")
            XCTAssertEqual(lookEvent["includedLive"] as? Bool, true, "The Look receipt must prove that a current location point was included.")
            add(XCTAttachment(string: "Bob completed a Sealed Look in UI and the API recorded includedLive=true while both simulators followed the moving Core Simulator route."))

            // A confirmed Look snapshot should render as a map pin, and the receipt
            // should appear in Activity under the same event ID returned by the API.
            let openMap = app.buttons["view-open-map"]
            XCTAssertTrue(openMap.waitForExistence(timeout: 10), app.debugDescription)
            openMap.tap()
            let mapCanvas = app.descendants(matching: .any)["map-screen-canvas"]
            XCTAssertTrue(mapCanvas.waitForExistence(timeout: 20), "A confirmed Look should add its snapshot pin to the map.")
            XCTAssertTrue(app.descendants(matching: .any)["map-screen-person-panel"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["PairAlice"].exists, "The selected map pin should identify Alice.")
            let snapshotTime = app.descendants(matching: .any).matching(identifier: "map-selected-location-time").firstMatch
            XCTAssertTrue(snapshotTime.waitForExistence(timeout: 5))
            XCTAssertTrue(snapshotTime.label.localizedCaseInsensitiveContains("snapshot"))
            let viewSelected = app.buttons["map-view-selected-person"]
            if !viewSelected.isHittable { app.swipeUp() }
            XCTAssertTrue(viewSelected.isHittable, "Map details must scroll so the selected-person action remains reachable.")
            attachScreenshot(of: app, named: "Paired Sealed Look - snapshot map pin")
            viewSelected.tap()
            XCTAssertTrue(app.buttons["view-open-map"].waitForExistence(timeout: 10), "The map action must open the selected person's location.")
            app.buttons["view-open-map"].tap()
            XCTAssertTrue(app.buttons["map-back-to-people"].waitForExistence(timeout: 10))
            app.buttons["map-back-to-people"].tap()
            app.buttons["tab-log"].tap()
            let lookEventID = try XCTUnwrap(lookEvent["id"] as? String).uppercased()
            let activityRow = app.descendants(matching: .any)["activity-event-\(lookEventID)"]
            XCTAssertTrue(activityRow.waitForExistence(timeout: 20), "The viewer's Activity list should include the Look receipt recorded by the API.")
            XCTAssertTrue(activityRow.label.contains("PairAlice"), "Activity should name the person the viewer just looked at.")
            attachScreenshot(of: app, named: "Paired Sealed Look - Activity receipt")
            app.buttons["tab-circle"].tap()

            // Verify first-use Home selection using the moving Core Simulator route.
            // Home's exact coordinates stay in the on-device store; the API only
            // receives the place label/ID and the resulting coarse presence state.
            app.buttons["tab-you"].tap()
            let myLocation = app.buttons["my-location"]
            XCTAssertTrue(myLocation.waitForExistence(timeout: 10))
            myLocation.tap()
            let setHome = app.buttons["home-set-button"]
            XCTAssertTrue(setHome.waitForExistence(timeout: 10), app.debugDescription)
            if !setHome.isHittable { app.swipeUp() }
            setHome.tap()
            let whenInUseAlert = app.alerts.firstMatch
            if whenInUseAlert.waitForExistence(timeout: 2) {
                let whileUsing = whenInUseAlert.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "While Using")
                ).firstMatch
                let allowOnce = whenInUseAlert.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Allow Once")
                ).firstMatch
                if whileUsing.exists { whileUsing.tap() }
                else if allowOnce.exists { allowOnce.tap() }
                else { XCTFail("When-In-Use location permission appeared without a recognizable allow action.\n\(app.debugDescription)") }
            }
            let homePlaceStatus = app.staticTexts["home-place-status"]
            XCTAssertTrue(waitUntil(timeout: 30) {
                homePlaceStatus.exists && homePlaceStatus.label.localizedCaseInsensitiveContains("set")
            }, "The You → My Location screen should confirm Home was set from the moving simulator route.\n\(app.debugDescription)")
            let setHomeResponse = api.yourHomePlace(token: session.token)
            XCTAssertTrue((200..<300).contains(setHomeResponse.status), "A successful circle response should expose the newly set Home place.")
            XCTAssertEqual(setHomeResponse.label, "Home")
            // A fresh account/device may have only When-In-Use access. Home/Away
            // geofencing requires Always, so complete the real permission upgrade
            // instead of dismissing the explainer and then expecting a transition.
            allowBackgroundLocationIfPrompted(in: app)
            let locationPermission = app.staticTexts["location-permission-status"]
            XCTAssertTrue(waitUntil(timeout: 12) {
                locationPermission.exists && locationPermission.label.localizedCaseInsensitiveContains("always")
            }, "The paired Home/Away test requires Always location permission; complete Trust's explainer and the iOS Always prompt.\n\(app.debugDescription)\n\(XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)")

            let originalHomePlaceID = try XCTUnwrap(setHomeResponse.placeID)
            XCTAssertTrue(waitUntil(timeout: 20) {
                self.yourHomeState(token: session.token) == "home"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "home"
            }, "Setting Home should publish Home to a connected person who has granted Home/Away visibility.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.yourHomeState(token: session.token) == "away"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "away"
            }, "As the moving simulator leaves the saved Home radius, both accounts should observe Away.")

            // Re-setting Home is an update-in-place action. It keeps the logical
            // place ID on the server but stores the new current coordinate locally.
            // A fresh simulator fix can fall back at 20 seconds; allow time for that
            // one-shot request, the server update, and both accounts' next reads.
            XCTAssertTrue(setHome.isHittable, "Set Home Here should remain available when a place already exists.")
            setHome.tap()
            XCTAssertTrue(waitUntil(timeout: 40) {
                self.yourHomeState(token: session.token) == "home"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "home"
            }, "Saving Home at the new current location should publish Home again to the connected account; allow for the location request's 20-second last-known-fix fallback.")
            let updatedHomeResponse = api.yourHomePlace(token: session.token)
            XCTAssertEqual(updatedHomeResponse.label, "Home")
            XCTAssertEqual(updatedHomeResponse.placeID, originalHomePlaceID, "Updating the saved coordinate should keep the same logical Home place ID.")
            XCTAssertTrue(homePlaceStatus.label.localizedCaseInsensitiveContains("set"))
            XCTAssertTrue(locationPermission.label.localizedCaseInsensitiveContains("always"), "Updating Home must retain Always location permission.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.yourHomeState(token: session.token) == "away"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "away"
            }, "The updated Home location should continue to drive Away when the moving simulator leaves its new radius.")

            let clearHome = app.buttons["home-clear-button"]
            XCTAssertTrue(clearHome.waitForExistence(timeout: 10), app.debugDescription)
            if !clearHome.isHittable { app.swipeUp() }
            clearHome.tap()
            XCTAssertTrue(waitUntil(timeout: 20) {
                homePlaceStatus.exists && !homePlaceStatus.label.localizedCaseInsensitiveContains("set")
            }, "Clearing Home should return the You screen to its unset state.\n\(app.debugDescription)")
            let clearHomeResponse = api.yourHomePlace(token: session.token)
            XCTAssertTrue((200..<300).contains(clearHomeResponse.status), "A successful circle response should confirm Home was cleared.")
            XCTAssertNil(clearHomeResponse.label, "The API should no longer expose a Home place after Clear Home.")
            add(XCTAttachment(string: "Bob set Home, drove the moving simulator out of range, updated the same logical Home place from the new fix, observed Home→Away again, then cleared it. Alice's independent account observed both status transitions. The server received only the place ID/label; coordinates remained on-device."))

            // Signal that Bob has completed Look and Home set/clear before Alice
            // starts her recipient-visibility sequence. Hidden is a stable marker:
            // geofence updates must not replace an explicit Hidden choice.
            let doneWithLocation = app.buttons["Done"]
            XCTAssertTrue(doneWithLocation.waitForExistence(timeout: 8), app.debugDescription)
            doneWithLocation.tap()
            app.buttons["tab-sharing"].tap()
            let bobHomeStatus = app.buttons["home-status-control"]
            XCTAssertTrue(bobHomeStatus.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(scrollUpUntilHittable(bobHomeStatus, in: app), app.debugDescription)
            bobHomeStatus.tap()
            let markHidden = app.buttons.matching(identifier: "set-home-status-hidden").firstMatch
            XCTAssertTrue(markHidden.waitForExistence(timeout: 5))
            markHidden.tap()
            XCTAssertTrue(waitUntil(timeout: 20) { self.yourHomeState(token: session.token) == "hidden" }, "Bob's UI should publish the Hidden readiness barrier for Alice.")
            XCTAssertTrue(bobHomeStatus.label.localizedCaseInsensitiveContains("Hidden"), "Bob's Sharing control should show the acknowledged Hidden state.")
            add(XCTAttachment(string: "Bob completed Look and Home set/clear, then set Hidden in Sharing UI as a stable readiness barrier for Alice's Home/Away/Hidden sequence."))

            // Alice transitions Home -> Away -> Hidden in her UI. Her role waits
            // for each recipient-visible response before moving to the next state.
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.visibleHomePresence(personID: aliceID, token: session.token) == "home"
            }, "Bob should receive Alice's Home status after both grants are enabled.")
            XCTAssertEqual(api.postHomePresence(state: "home", token: session.token), 204, "Bob acknowledges Home only after his recipient response sees Alice's Home.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.visibleHomePresence(personID: aliceID, token: session.token) == "away"
            }, "Bob should receive Alice's Away status after Home.")
            XCTAssertEqual(api.postHomePresence(state: "away", token: session.token), 204, "Bob acknowledges Away only after his recipient response sees Alice's Away.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                let response = self.api.memberResponse(personID: aliceID, token: session.token)
                guard (200..<300).contains(response.status),
                      let member = response.member,
                      member["inboundPresenceGranted"] as? Bool == true else { return false }
                return member["homePresence"] == nil || member["homePresence"] is NSNull
            }, "Bob's response should hide Alice's Home/Away after she chooses Hidden.")
            XCTAssertEqual(api.postHomePresence(state: "hidden", token: session.token), 204, "Bob acknowledges Hidden only after his successful recipient response suppresses Alice's presence.")
            app.buttons["tab-circle"].tap()
            app.swipeDown()
            let hiddenAliceRow = app.buttons["person-row-pairalice"]
            XCTAssertTrue(hiddenAliceRow.waitForExistence(timeout: 15), "Bob's Duo People list should still show Alice after refreshing the Hidden state.\n\(app.debugDescription)")
            hiddenAliceRow.tap()
            let aliceStatus = app.staticTexts["person-status"]
            XCTAssertTrue(waitUntil(timeout: 15) {
                aliceStatus.exists && aliceStatus.label.localizedCaseInsensitiveContains("hidden")
            }, "Bob's Duo person screen should render Alice as Hidden after a successful recipient response suppressed her Home/Away payload.\n\(app.debugDescription)")
            app.buttons["tab-sharing"].tap()
            let later = app.buttons["always-explainer-later"]
            if later.waitForExistence(timeout: 2) { later.tap() }
            let off = app.buttons["sharing-mode-off-pairalice"]
            XCTAssertTrue(off.waitForExistence(timeout: 8))
            XCTAssertTrue(waitUntil(timeout: 5) { off.isHittable }, "Stop should be tappable after the sharing explainer closes.")
            off.tap()
            let confirmStop = app.buttons.matching(identifier: "stop-sharing-confirm")
            XCTAssertTrue(confirmStop.firstMatch.waitForExistence(timeout: 5))
            confirmStop.element(boundBy: 0).tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                self.outboundPresentation(personID: aliceID, token: session.token) == "off"
            }, "Stopping sharing through Bob's UI should immediately revoke Bob→Alice visibility.")

            let originalConnectionID = try XCTUnwrap(api.member(personID: aliceID, token: session.token)?["connectionId"] as? String)
            XCTAssertFalse(originalConnectionID.isEmpty)
            XCTAssertTrue(waitUntil(timeout: 20) {
                let response = self.api.memberResponse(personID: session.personID, token: aliceSession.token)
                return (200..<300).contains(response.status) && response.member?["connectionId"] as? String == originalConnectionID
            }, "Alice's successful circle response should carry the same active connection ID.")
            XCTAssertTrue(waitUntil(timeout: 90) {
                self.successfulCircleOmitsMember(personID: aliceID, token: session.token)
                    && self.successfulCircleOmitsMember(personID: session.personID, token: aliceSession.token)
            }, "Alice's UI removal should produce successful circle responses without the peer for both accounts.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let aliceGroup = app.descendants(matching: .any)["sharing-mode-group-pairalice"]
            XCTAssertTrue(waitUntil(timeout: 15) { !aliceGroup.exists }, "Bob's refreshed Sharing list should remove Alice.")
            attachScreenshot(of: app, named: "Pair lifecycle - Bob removed by Alice")

            app.buttons["add-someone-button"].tap()
            let lookup = app.textFields["connection-handle"]
            XCTAssertTrue(lookup.waitForExistence(timeout: 8))
            let alicePhoneDigits = LocalTrustAPI.reservedPhonePool()[pairPhoneBase]
            lookup.typeText("+1 (\(alicePhoneDigits.prefix(3))) \(alicePhoneDigits.dropFirst(3).prefix(3))-\(alicePhoneDigits.suffix(4))")
            XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 12), "Alice's verified fictional phone should resolve for the re-add.")
            XCTAssertEqual(app.staticTexts["connection-lookup-handle"].label, "@\(aliceHandle)")
            let keyboardDone = app.buttons["Done"]
            if keyboardDone.exists && keyboardDone.isHittable {
                keyboardDone.tap()
            } else {
                // On Duo/iOS 27 the software-keyboard accessory can report
                // “Done” while XCTest cannot scroll it into a hittable frame.
                // Return invokes this field's .onSubmit and dismisses focus;
                // valid phone input is already resolved, so it does not issue
                // another lookup.
                lookup.typeText("\n")
            }
            let sendAgain = app.buttons["send-connection-request"]
            XCTAssertTrue(sendAgain.waitForExistence(timeout: 5))
            sendAgain.tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                let pending = !(self.api.connectionRequests(token: session.token)?["sent"] as? [[String: Any]] ?? []).isEmpty
                return pending || self.activeConnectionID(personID: aliceID, token: session.token).map { $0 != originalConnectionID } == true
            }, "Bob's UI should create a pending request or Alice should already have accepted it.")
            app.buttons["cancel-add-person"].tap()
            app.buttons["tab-you"].tap()
            XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["tab-you"].isSelected }, "Bob should open You while Alice reviews the request.")
            app.buttons["tab-sharing"].tap()
            XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["tab-sharing"].isSelected }, "Bob should return to Sharing to verify his Sent request.")
            let pendingSentRequest = app.descendants(matching: .any)["connection-request-sent-\(aliceHandle)"]
            XCTAssertTrue(pendingSentRequest.waitForExistence(timeout: 15), "Bob should see the new Sent request before Alice accepts it.\n\(app.debugDescription)")
            let requestReviewStatus = app.buttons["home-status-control"]
            XCTAssertTrue(requestReviewStatus.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(scrollUpUntilHittable(requestReviewStatus, in: app), app.debugDescription)
            requestReviewStatus.tap()
            let markAway = app.buttons.matching(identifier: "set-home-status-away").firstMatch
            XCTAssertTrue(markAway.waitForExistence(timeout: 5), app.debugDescription)
            markAway.tap()
            XCTAssertTrue(waitUntil(timeout: 20) { self.yourHomeState(token: session.token) == "away" }, "Bob should publish Away through the Sharing UI after seeing the pending Sent request.")
            XCTAssertTrue(waitUntil(timeout: 240) {
                self.activeConnectionID(personID: aliceID, token: session.token).map { $0 != originalConnectionID } == true
            }, "Alice should accept Bob's request in her UI and create a new relationship.")
            // Acceptance happens on the other device while Bob stays on Sharing.
            // There is no guaranteed push delivery for this state change, so
            // re-enter Sharing to exercise its explicit cross-device refresh.
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["tab-sharing"].isSelected }, "Bob should re-enter Sharing after Alice accepts.")
            app.swipeDown()
            let reconnectedAlice = app.descendants(matching: .any)["sharing-mode-group-pairalice"]
            XCTAssertTrue(reconnectedAlice.waitForExistence(timeout: 20), "Bob's refreshed Sharing list should show Alice reconnected. API member: \(String(describing: api.member(personID: aliceID, token: session.token))).\n\(app.debugDescription)")
            let requestsError = app.descendants(matching: .any)["connection-requests-error"]
            if !waitUntil(timeout: 15, condition: { !requestsError.exists }) {
                let retry = app.buttons["retry-connection-requests"]
                XCTAssertTrue(retry.waitForExistence(timeout: 8), "A stale Requests notice should expose Retry.\n\(app.debugDescription)")
                retry.tap()
                XCTAssertTrue(waitUntil(timeout: 30) { !requestsError.exists }, "Retry should clear the stale Requests notice after the account's successful re-add.\n\(app.debugDescription)")
                add(XCTAttachment(string: "Returning to Sharing did not clear the prior Requests notice within 15 seconds; the visible Retry action was used and cleared it."))
            }
            let requestsSection = app.descendants(matching: .any)["connection-requests-section"]
            XCTAssertTrue(waitUntil(timeout: 30) {
                !pendingSentRequest.exists && !requestsSection.exists && !requestsError.exists
            }, "After Alice accepts, Bob's completed Requests refresh should remove the stale Sent row and its now-empty Requests section.\n\(app.debugDescription)")
            XCTAssertTrue(waitUntil(timeout: 15) { self.outboundPresentation(personID: aliceID, token: session.token) == "off" }, "The reconnected row should start Off.")
            XCTAssertTrue(app.buttons["sharing-mode-off-pairalice"].isSelected, "Bob's reconnected row should visibly start Off.")
            add(XCTAttachment(string: "Bob's UI showed the Sent request while pending. After Alice accepted, a completed app refresh removed that stale row, showed the empty Requests state, retained the reconnected relationship, and kept sharing Off."))
            attachScreenshot(of: app, named: "Pair lifecycle - Bob reconnected Off")
            try assertReconnectedPair(
                ownToken: session.token, peerToken: aliceSession.token,
                ownID: session.personID, peerID: aliceID, originalConnectionID: originalConnectionID
            )
        }
    }

    func testPrivacyHeldAccountCanDeleteAfterRelaunch() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-held-delete-\(suffix)"
        let name = "HeldDelete\(suffix.prefix(6))"
        let session = try XCTUnwrap(api.developmentSession(name: name, deviceID: deviceID))
        defer { api.deleteAccount(token: session.token) }

        XCTAssertEqual(api.placePrivacyHold(token: session.token), 204)
        XCTAssertEqual(api.request("GET", "/api/v1/circle", token: session.token).status, 423)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = name
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        configureLocalAgeFixture(for: app)
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        completeLocalAgeFixture(in: app)

        let delete = app.buttons["age-privacy-hold-delete-account"]
        XCTAssertTrue(delete.waitForExistence(timeout: 20), app.debugDescription)

        // The authorization needed only for account deletion must survive an app
        // restart while the server continues to deny ordinary account access. The
        // second launch has no UI-test or development-session bypass; retain only the
        // DEBUG age fixture so this simulator keeps using its isolated test keychain.
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TRUST_DEV_SESSION")
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST")
        app.launch()
        XCTAssertTrue(delete.waitForExistence(timeout: 20), app.debugDescription)

        delete.tap()
        let confirm = app.alerts.buttons.matching(identifier: "age-privacy-hold-delete-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        var replacementSession: DisposableSession?
        XCTAssertTrue(waitUntil(timeout: 20) {
            guard let candidate = self.api.developmentSession(name: name, deviceID: deviceID) else { return false }
            guard candidate.personID != session.personID else { return false }
            replacementSession = candidate
            return true
        }, "Deleting the held account should invalidate its identity; the same test device must receive a new development account.")
        if let replacementSession {
            defer { api.deleteAccount(token: replacementSession.token) }
            XCTAssertNotEqual(replacementSession.personID, session.personID)
        }
    }

    /// Run these three cases serially, using the same TRUST_UI_HOME_HANDOFF_DEVICE_ID
    /// on both simulators. The Development API maps that device key to one account;
    /// each simulator keeps its own Keychain Home coordinates and monitor.
    func testSameAccountHomeHandoffOwnerSetsHome() throws {
        let session = try sameAccountHomeHandoffSession()
        let app = launchDevelopmentApp(deviceID: session.deviceID, displayName: "HomeHandoff")
        setHomeInUI(app)
        let saved = api.yourHomePlace(token: session.token)
        XCTAssertEqual(saved.status, 200)
        XCTAssertEqual(saved.label, "Home")
        XCTAssertNotNil(saved.placeID, "The API marker must identify the active Home monitor.")
        XCTAssertTrue(app.staticTexts["home-place-status"].label.localizedCaseInsensitiveContains("set"))
    }

    func testSameAccountHomeHandoffFirstUseDeviceTakesOver() throws {
        let session = try sameAccountHomeHandoffSession()
        let original = api.yourHomePlace(token: session.token)
        XCTAssertEqual(original.status, 200)
        XCTAssertNotNil(original.placeID, "Simulator A must publish its Home marker before simulator B starts.")
        let app = launchDevelopmentApp(deviceID: session.deviceID, displayName: "HomeHandoff")
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["tab-you"].tap()
        let locationButton = app.buttons["my-location"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 10), app.debugDescription)
        locationButton.tap()
        let elsewhere = app.staticTexts["home-monitoring-elsewhere"]
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 15), "A first-use simulator should detect the server marker owned by the other device.\n\(app.debugDescription)")
        XCTAssertTrue(elsewhere.label.localizedCaseInsensitiveContains("move monitoring to this device"))
        XCTAssertTrue(app.staticTexts["home-place-status"].label.localizedCaseInsensitiveContains("another device"))
        setHomeInUI(app)
        let replacement = api.yourHomePlace(token: session.token)
        XCTAssertEqual(replacement.status, 200)
        XCTAssertEqual(replacement.label, "Home")
        XCTAssertNotEqual(replacement.placeID, original.placeID, "Taking over from a different local Home coordinate must publish a new ownership marker.")
        assertAlwaysLocationPermission(in: app)
    }

    func testSameAccountHomeHandoffPreviousOwnerDetectsTakeoverAndClear() throws {
        let session = try sameAccountHomeHandoffSession()
        let takeover = api.yourHomePlace(token: session.token)
        XCTAssertEqual(takeover.status, 200)
        XCTAssertNotNil(takeover.placeID, "Simulator B must publish its replacement server marker before simulator A resumes.")
        let app = launchDevelopmentApp(deviceID: session.deviceID, displayName: "HomeHandoff")
        app.buttons["tab-you"].tap()
        let myLocation = app.buttons["my-location"]
        XCTAssertTrue(myLocation.waitForExistence(timeout: 10), app.debugDescription)
        myLocation.tap()
        let elsewhere = app.staticTexts["home-monitoring-elsewhere"]
        XCTAssertTrue(elsewhere.waitForExistence(timeout: 15), "The former owner must reconcile the new server marker and stop its local monitor.")
        assertAlwaysLocationPermission(in: app)
        let cleared = app.buttons["home-clear-button"]
        XCTAssertTrue(cleared.waitForExistence(timeout: 5))
        cleared.tap()
        XCTAssertTrue(waitUntil(timeout: 15) {
            let current = self.api.yourHomePlace(token: session.token)
            return current.status == 200 && current.placeID == nil
        }, "Clear Home must remove the shared server marker.")
        app.terminate()
        app.launch()
        let youTab = app.buttons["tab-you"]
        XCTAssertTrue(youTab.waitForExistence(timeout: 15), app.debugDescription)
        youTab.tap()
        let locationButton = app.buttons["my-location"]
        XCTAssertTrue(locationButton.waitForExistence(timeout: 10), app.debugDescription)
        locationButton.tap()
        XCTAssertTrue(waitUntil(timeout: 15) {
            let status = app.staticTexts["home-place-status"]
            return status.exists && status.label.localizedCaseInsensitiveContains("no home")
        }, "After a confirmed remote clear and reconnect, the former owner's local Home must be cleared.\n\(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["home-monitoring-elsewhere"].exists, "After the API marker is cleared, the reconnection must not show remote ownership.\n\(app.debugDescription)")
        assertAlwaysLocationPermission(in: app)
    }

    /// The peer accepts through the local API after this UI's initial circle fetch.
    /// Returning to Sharing must fetch promptly and render the new relationship.
    func testSharingTabRefreshShowsPeerAcceptedAfterInitialFetch() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let mainDeviceID = "trust-refresh-main-\(suffix)"
        let peerDeviceID = "trust-refresh-peer-\(suffix)"
        let mainName = "RefreshMain\(suffix.prefix(6))"
        let peerName = "RefreshPeer\(suffix.prefix(6))"
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let mainPhone = try XCTUnwrap(phones.first)
        let peerPhone = try XCTUnwrap(phones.last)
        let mainSession = try XCTUnwrap(api.developmentSession(name: mainName, deviceID: mainDeviceID))
        let peerSession = try XCTUnwrap(api.developmentSession(name: peerName, deviceID: peerDeviceID))
        defer {
            api.deleteAccount(token: peerSession.token)
            api.deleteAccount(token: mainSession.token)
        }

        let mainHandle = "rm\(suffix.prefix(10))"
        let peerHandle = "rp\(suffix.prefix(10))"
        XCTAssertEqual(api.putHandle(mainHandle, token: mainSession.token), 204)
        XCTAssertEqual(api.putHandle(peerHandle, token: peerSession.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(mainPhone)", token: mainSession.token))
        XCTAssertTrue(api.verifyPhone(phone: "+1\(peerPhone)", token: peerSession.token))
        XCTAssertEqual(api.setPhoneDiscovery(true, token: peerSession.token), 204)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = mainDeviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = mainName
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        configureLocalAgeFixture(for: app)
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        completeLocalAgeFixture(in: app)

        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.buttons["copy-own-handle"].waitForExistence(timeout: 10))
        app.buttons["tab-sharing"].tap()
        let groupID = "sharing-mode-group-\(peerName.lowercased())"
        XCTAssertFalse(app.descendants(matching: .any)[groupID].exists, "The initial circle fetch should be empty before peer acceptance.")

        app.buttons["add-someone-button"].tap()
        let lookup = app.textFields["connection-handle"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 8))
        lookup.typeText(peerHandle)
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10))
        app.buttons["send-connection-request"].tap()
        app.buttons["cancel-add-person"].tap()
        guard let request = (api.connectionRequests(token: peerSession.token)?["incoming"] as? [[String: Any]])?.first,
              let requestID = request["id"] as? String else {
            XCTFail("The peer should receive the UI-created request.")
            return
        }
        XCTAssertEqual(api.request("POST", "/api/v1/connection-requests/\(requestID)/accept", token: peerSession.token).status, 204)
        let acceptedAt = Date()
        XCTAssertTrue(waitUntil(timeout: 15) { self.api.member(personID: peerSession.personID, token: mainSession.token) != nil })

        app.buttons["tab-you"].tap()
        app.buttons["tab-sharing"].tap()
        let connected = app.descendants(matching: .any)[groupID]
        XCTAssertTrue(connected.waitForExistence(timeout: 15), "Returning to Sharing must fetch and render the accepted member without relying on a manual pull gesture.\n\(app.debugDescription)")
        add(XCTAttachment(string: "The UI rendered the API-accepted member after Sharing-tab entry in \(Date().timeIntervalSince(acceptedAt)) seconds."))
    }

    func testAlwaysSharedLocationHistoryRendersAndClearsAfterStop() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let viewerDeviceID = "trust-history-viewer-\(suffix)"
        let subjectDeviceID = "trust-history-subject-\(suffix)"
        let viewerName = "HistoryViewer\(suffix.prefix(5))"
        let subjectName = "HistoryPeer\(suffix.prefix(5))"
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let viewerPhone = try XCTUnwrap(phones.first)
        let subjectPhone = try XCTUnwrap(phones.last)
        let viewer = try XCTUnwrap(api.developmentSession(name: viewerName, deviceID: viewerDeviceID))
        let subject = try XCTUnwrap(api.developmentSession(name: subjectName, deviceID: subjectDeviceID))
        defer {
            api.deleteAccount(token: subject.token)
            api.deleteAccount(token: viewer.token)
        }

        XCTAssertEqual(api.putHandle("hv\(suffix.prefix(10))", token: viewer.token), 204)
        XCTAssertEqual(api.putHandle("hp\(suffix.prefix(10))", token: subject.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(viewerPhone)", token: viewer.token))
        XCTAssertTrue(api.verifyPhone(phone: "+1\(subjectPhone)", token: subject.token))

        let request = api.request(
            "POST",
            "/api/v1/connection-requests",
            token: viewer.token,
            body: ["recipientId": subject.personID]
        )
        XCTAssertEqual(request.status, 200)
        let requestID = try XCTUnwrap((request.json as? [String: Any])?["id"] as? String)
        XCTAssertEqual(api.request("POST", "/api/v1/connection-requests/\(requestID)/accept", token: subject.token).status, 204)

        // Always requires Plus for the person sharing. The Development API exposes
        // its review unlock so this test never enters StoreKit or creates a purchase.
        XCTAssertEqual(api.request("POST", "/api/v1/circle/entitlement", token: subject.token, body: ["reviewUnlock": true]).status, 204)
        let subjectConnectionID = try XCTUnwrap(activeConnectionID(personID: viewer.personID, token: subject.token))
        let subjectShareRevision = try XCTUnwrap(activeShareRevision(personID: viewer.personID, token: subject.token))
        XCTAssertEqual(
            api.request(
                "PATCH",
                "/api/v1/people/\(viewer.personID)/share",
                token: subject.token,
                body: ["connectionId": subjectConnectionID, "revision": subjectShareRevision, "resting": "always"]
            ).status,
            204
        )

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let historyPoints: [[String: Any]] = (0..<3).map { index in
            let timestamp = now.addingTimeInterval(TimeInterval(-120 * (index + 1)))
            return [
                "timestamp": formatter.string(from: timestamp),
                "latitude": 47.60 + Double(index) * 0.001,
                "longitude": -122.33 - Double(index) * 0.001
            ]
        }
        XCTAssertEqual(
            api.request(
                "POST",
                "/api/v1/location",
                token: subject.token,
                body: [
                    "timestamp": formatter.string(from: now),
                    "latitude": 47.60,
                    "longitude": -122.33,
                    "batteryPercent": 75,
                    "isCharging": false,
                    "points": historyPoints
                ]
            ).status,
            204
        )
        let seededHistory = api.request("GET", "/api/v1/people/\(subject.personID)/history", token: viewer.token)
        XCTAssertEqual(seededHistory.status, 200)
        XCTAssertEqual(((seededHistory.json as? [String: Any])?["points"] as? [[String: Any]])?.count, 3)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = viewerDeviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = viewerName
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        configureLocalAgeFixture(for: app)
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        completeLocalAgeFixture(in: app)

        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 15))
        let peerRow = app.buttons["person-row-\(subjectName.lowercased())"]
        XCTAssertTrue(peerRow.waitForExistence(timeout: 15), app.debugDescription)
        let availableLabel = peerRow.label
        peerRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["person-history"].waitForExistence(timeout: 15), app.debugDescription)
        for index in 0..<3 {
            XCTAssertTrue(
                app.descendants(matching: .any)["person-history-visit-\(index)"].waitForExistence(timeout: 10),
                "The Always-shared trail should render all three points returned by the API.\n\(app.debugDescription)"
            )
        }
        attachScreenshot(of: app, named: "Always sharing - location history")

        // Stop sharing on the subject's server account, then force the viewer's
        // circle refresh. The Person screen must no longer expose retained visits.
        let stoppedShareRevision = try XCTUnwrap(activeShareRevision(personID: viewer.personID, token: subject.token))
        XCTAssertEqual(
            api.request("PATCH", "/api/v1/people/\(viewer.personID)/share", token: subject.token, body: ["connectionId": subjectConnectionID, "revision": stoppedShareRevision, "resting": "off"]).status,
            204
        )
        let stoppedCircle = api.memberResponse(personID: subject.personID, token: viewer.token)
        XCTAssertEqual(stoppedCircle.status, 200)
        XCTAssertNotNil(stoppedCircle.member, "Stopping sharing must retain the connection in the server circle.")
        XCTAssertEqual((stoppedCircle.member?["inboundShare"] as? [String: Any])?["presentation"] as? String, "off")
        let stoppedHistory = api.request("GET", "/api/v1/people/\(subject.personID)/history", token: viewer.token)
        XCTAssertEqual(stoppedHistory.status, 409, "The server must revoke history access immediately when Always sharing stops.")
        app.buttons["circle-back"].tap()
        XCTAssertTrue(peerRow.waitForExistence(timeout: 5))
        let peopleList = app.scrollViews["people-list"]
        XCTAssertTrue(peopleList.waitForExistence(timeout: 5), app.debugDescription)
        peopleList.swipeDown()
        XCTAssertTrue(waitUntil(timeout: 15) { peerRow.label != availableLabel }, "The row should reflect the server-confirmed Stop before opening Person again.\n\(app.debugDescription)")
        peerRow.tap()
        XCTAssertTrue(app.staticTexts["person-status"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["person-history"].exists, "Stopping Always must remove the viewer's cached history from the Person screen.")
    }

    func testRealOnboardingHandleRequestAcceptAndStopSharing() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-ui-test-\(suffix)"
        let mainName = "UI\(suffix.prefix(8))"
        let peerName = "Peer\(suffix.prefix(8))"
        // Use only fictional 555-0100..0199 values across established area codes.
        // The fixed 202-555-0199 no-match fixture is excluded. A wide randomized pool
        // avoids reusing persistent local SMS budget keys across sequential simulator runs.
        let reservedPhones = LocalTrustAPI.reservedPhonePool().shuffled().prefix(3)
        let phoneDigits = try XCTUnwrap(reservedPhones.first)
        let peerPhoneDigits = try XCTUnwrap(reservedPhones.dropFirst().first)

        let mainSession = try XCTUnwrap(api.developmentSession(name: mainName, deviceID: deviceID))
        var disposableTokens = [mainSession.token]
        defer { disposableTokens.reversed().forEach { api.deleteAccount(token: $0) } }

        let peerSession = try XCTUnwrap(api.developmentSession(name: peerName, deviceID: "trust-ui-peer-\(suffix)"))
        disposableTokens.append(peerSession.token)


        let peerHandle = "peer\(suffix.prefix(8))"
        XCTAssertEqual(api.putHandle(peerHandle, token: peerSession.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(peerPhoneDigits)", token: peerSession.token), "The target must be phone-verified before handle discovery.")
        XCTAssertEqual(api.putAvatarPreset("fox", token: peerSession.token), 200)
        XCTAssertEqual(api.setPhoneDiscovery(true, token: peerSession.token), 204)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        configureLocalAgeFixture(for: app)
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        completeLocalAgeFixture(in: app)

        let handleField = app.textFields.firstMatch
        XCTAssertTrue(handleField.waitForExistence(timeout: 20), "A fresh development identity should land on real handle onboarding.")
        handleField.tap()
        let suggestedHandle = handleField.value as? String ?? ""
        let chosenHandle = "ui\(suffix.prefix(8))"
        handleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: suggestedHandle.count) + chosenHandle)
        let continueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Continue")).firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 8) { continueButton.isEnabled }, "The locally checked handle should become available.")
        let discoveryToggle = app.switches["onboarding-discovery-toggle"]
        XCTAssertTrue(discoveryToggle.waitForExistence(timeout: 5))
        discoveryToggle.tap()
        continueButton.tap()

        let phone = app.textFields["phone-number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 12), "Completing the handle should open phone verification.")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "By tapping Send code")).firstMatch.exists)
        phone.tap()
        phone.typeText("+1\(phoneDigits)")
        app.buttons["send-phone-code"].tap()

        let codeNotice = app.staticTexts["phone-notice"]
        XCTAssertTrue(codeNotice.waitForExistence(timeout: 10), "Development API should show its test OTP in the app.")
        let digits = codeNotice.label.filter(\.isNumber)
        XCTAssertEqual(digits.count, 6, "The code used here must come from the app's development-only OTP notice.")
        let codeField = app.textFields["phone-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText(digits)
        app.buttons["verify-phone-code"].tap()
        let enteredApp = app.buttons["tab-sharing"].waitForExistence(timeout: 15)
        XCTAssertTrue(enteredApp, "Phone verification did not advance: \(codeNotice.exists ? codeNotice.label : "no phone notice")")

        let onboarded = api.circle(token: mainSession.token)
        XCTAssertEqual((onboarded?["you"] as? [String: Any])?["handle"] as? String, chosenHandle)
        XCTAssertEqual((onboarded?["you"] as? [String: Any])?["phoneVerified"] as? Bool, true)
        XCTAssertEqual((onboarded?["you"] as? [String: Any])?["discoveryEnabled"] as? Bool, true)

        app.buttons["tab-sharing"].tap()
        let addSomeone = app.buttons["add-someone-button"]
        XCTAssertTrue(addSomeone.waitForExistence(timeout: 10))
        addSomeone.tap()
        let lookupField = app.textFields["connection-handle"]
        XCTAssertTrue(lookupField.waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "Requests - Add someone empty")
        lookupField.typeText("+1 (\(peerPhoneDigits.prefix(3))) \(peerPhoneDigits.dropFirst(3).prefix(3))-\(peerPhoneDigits.suffix(4))")
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10), "Typing a complete phone number should resolve the exact public handle.")
        XCTAssertEqual(app.staticTexts["connection-lookup-handle"].label, "@\(peerHandle)")
        XCTAssertTrue(app.descendants(matching: .any)["connection-lookup-avatar"].waitForExistence(timeout: 5), "An exact phone match should show the saved picture descriptor.")
        attachScreenshot(of: app, named: "Requests - Phone match and picture")
        lookupField.tap()
        lookupField.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertFalse(app.staticTexts["connection-lookup-handle"].exists, "Editing the query should clear the prior match immediately.")
        app.buttons["clear-connection-lookup"].tap()
        XCTAssertEqual(lookupField.value as? String, "Handle or phone number", "The clear control should empty the entire previous query.")
        lookupField.typeText("+1 202 555 0199")
        let noMatch = app.staticTexts["connection-lookup-no-match"]
        XCTAssertTrue(noMatch.waitForExistence(timeout: 10), "An unmatched complete phone number should show a no-match state.")
        XCTAssertEqual(app.buttons["invite-to-trust"].label, "Share invite link", "The action should describe the native share sheet, without claiming the number is unregistered.")
        attachScreenshot(of: app, named: "Requests - No match invite")
        let outgoingBeforeInvite = (api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]])?.count ?? 0
        app.buttons["invite-to-trust"].tap()
        let nativeShareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(nativeShareSheet.waitForExistence(timeout: 10), "Tapping Invite should open the native share sheet.")
        let copyAction = app.cells.matching(identifier: "actionGroupCell")
            .matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copyAction.waitForExistence(timeout: 5), "The native share sheet should offer its Copy action.")
        attachScreenshot(of: app, named: "Requests - Native invite share sheet")
        app.buttons["header.closeButton"].tap()
        let clearLookup = app.buttons["clear-connection-lookup"]
        // Earlier iOS 27.1 runs ignored close and swipe, but the latest run dismissed
        // normally. Keep the swipe fallback conditional so it is used only if needed.
        if !waitUntil(timeout: 2, condition: { clearLookup.isHittable }) {
            nativeShareSheet.swipeDown()
        }
        var didRelaunchAfterShareSheet = false
        var returnedFromShareSheet = waitUntil(timeout: 5) { clearLookup.isHittable && app.staticTexts["connection-lookup-no-match"].exists }
        if !returnedFromShareSheet {
            didRelaunchAfterShareSheet = true
            // iOS 27.1 can leave the system activity sheet presented after both close
            // and swipe. Relaunch the same authenticated local account and reopen Add.
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
            app.buttons["tab-you"].tap()
            let restoredHandle = app.buttons["copy-own-handle"]
            XCTAssertTrue(restoredHandle.waitForExistence(timeout: 10))
            XCTAssertEqual(restoredHandle.value as? String, "@\(chosenHandle)", "Relaunch must restore the same visible account handle.")
            app.buttons["tab-sharing"].tap()
            XCTAssertTrue(addSomeone.waitForExistence(timeout: 10))
            addSomeone.tap()
            returnedFromShareSheet = lookupField.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(returnedFromShareSheet, "The Add screen should be recoverable after dismissing or relaunching from the native share sheet.")
        XCTAssertEqual(api.circle(token: mainSession.token)?["you"].flatMap { ($0 as? [String: Any])?["id"] as? String }, mainSession.personID, "Recovery must return to the same authenticated account.")
        XCTAssertEqual((api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]])?.count ?? 0, outgoingBeforeInvite, "Looking up or sharing an invite must not create a connection request.")
        if didRelaunchAfterShareSheet {
            let recovery = XCTAttachment(string: "iOS 27.1 did not dismiss the native share sheet with close or swipe; the test explicitly relaunched and reopened Add. The authenticated person ID and server request count were checked after recovery.")
            recovery.name = "Diagnostics - iOS 27.1 share-sheet recovery"
            recovery.lifetime = .keepAlways
            add(recovery)
        }
        if !didRelaunchAfterShareSheet {
            app.buttons["clear-connection-lookup"].tap()
        }
        lookupField.typeText(peerHandle)
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10))
        app.buttons["send-connection-request"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.api.connectionRequests(token: mainSession.token)?["sent"] is [[String: Any]]
                && !((self.api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]]) ?? []).isEmpty
        }, "Sending should create a pending request visible to the sender.")
        app.buttons["cancel-add-person"].tap()
        let sentRequestHandle = app.staticTexts["connection-request-handle-\(peerHandle)"]
        XCTAssertTrue(sentRequestHandle.waitForExistence(timeout: 8), "The sent request should remain visible after closing Add someone.")
        attachScreenshot(of: app, named: "Requests - Sent and pending")
        XCTAssertTrue(addSomeone.waitForExistence(timeout: 5))
        addSomeone.tap()
        XCTAssertTrue(lookupField.waitForExistence(timeout: 5), "The add sheet should reopen after cancellation.")
        XCTAssertEqual(lookupField.value as? String, "Handle or phone number", "Reopening should start with a fresh lookup.")
        app.buttons["cancel-add-person"].tap()
        let cancelPending = app.buttons["cancel-connection-request-\(peerHandle)"]
        XCTAssertTrue(cancelPending.waitForExistence(timeout: 8), "The sent request should expose a UI cancellation action.")
        cancelPending.tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            (self.api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]])?.isEmpty == true
        }, "Canceling from the pending request row should cancel the server request.")

        // The peer cannot race the cancellation above because it is API-only in
        // this focused UI test. Now let it send the reverse request so this UI
        // account exercises the explicit incoming accept flow.
        XCTAssertTrue((200..<300).contains(api.createConnectionRequest(recipientID: mainSession.personID, token: peerSession.token)))
        app.buttons["tab-you"].tap()
        app.buttons["tab-sharing"].tap()
        let incomingAccept = app.buttons["accept-connection-request-\(peerHandle)"]
        XCTAssertTrue(incomingAccept.waitForExistence(timeout: 12), "A received request should show the handle and explicit Accept action.")
        attachScreenshot(of: app, named: "Requests - Incoming with accept and decline")
        incomingAccept.tap()

        let memberGroupID = "sharing-mode-group-\(peerName.lowercased())"
        XCTAssertTrue(app.descendants(matching: .any)[memberGroupID].waitForExistence(timeout: 12), "Accepting the handle request should add the peer to Sharing.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "off"
                && self.inboundPresentation(personID: peerSession.personID, token: mainSession.token) == "off"
        }, "The server should report Off in both directions after the join.")
        let acceptedPerson = app.descendants(matching: .any)[memberGroupID]
        if !acceptedPerson.isHittable { app.swipeUp() }
        attachScreenshot(of: app, named: "Requests - Connected with sharing Off")

        // SwiftUI's native Menu exposes the title as the accessibility label on iOS 27.1,
        // even when its nested button identifier is discarded by the platform menu host.
        let presenceGrant = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Let \(peerName) know when I’m Home or Away")
        ).firstMatch
        XCTAssertTrue(app.buttons["sharing-actions-\(peerName.lowercased())"].waitForExistence(timeout: 5))
        XCTAssertFalse(api.member(personID: peerSession.personID, token: mainSession.token)?["outboundPresenceGranted"] as? Bool ?? true,
                       "Home/Away visibility and arrival alerts must start disabled for a new connection.")
        app.buttons["sharing-actions-\(peerName.lowercased())"].tap()
        XCTAssertTrue(presenceGrant.waitForExistence(timeout: 5))
        presenceGrant.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.api.member(personID: peerSession.personID, token: mainSession.token)?["outboundPresenceGranted"] as? Bool == true
        }, "The per-person control should persist the explicit presence/arrival grant.")
        XCTAssertTrue(app.staticTexts["Home/Away sharing preference updated."].waitForExistence(timeout: 15), "Wait for the acknowledged write and UI refresh before opening the menu again.")
        app.buttons["sharing-actions-\(peerName.lowercased())"].tap()
        XCTAssertTrue(presenceGrant.waitForExistence(timeout: 5))
        presenceGrant.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.api.member(personID: peerSession.personID, token: mainSession.token)?["outboundPresenceGranted"] as? Bool == false
        }, "Turning the per-person grant back off should persist the revocation.")

        let sealed = app.buttons["sharing-mode-sealed-\(peerName.lowercased())"]
        XCTAssertTrue(sealed.waitForExistence(timeout: 5))
        sealed.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "untilTheyLook"
        }, "The sharing selection should update the peer's server response.")

        let later = app.buttons["always-explainer-later"]
        if later.waitForExistence(timeout: 2) { later.tap() }
        let off = app.buttons["sharing-mode-off-\(peerName.lowercased())"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        let offBecameHittable = waitUntil(timeout: 5) { off.isHittable }
        if !offBecameHittable {
            let accessibility = XCTAttachment(string: app.debugDescription)
            accessibility.name = "Diagnostics - Off unavailable after explainer"
            accessibility.lifetime = .keepAlways
            add(accessibility)
            attachScreenshot(of: app, named: "Diagnostics - Off unavailable after explainer")
        }
        XCTAssertTrue(offBecameHittable, "Off should be tappable after the sharing explainer closes.")
        off.tap()
        let confirmStop = app.buttons.matching(identifier: "stop-sharing-confirm")
        XCTAssertTrue(confirmStop.firstMatch.waitForExistence(timeout: 5))
        // SwiftUI exposes two automation aliases for one alert action on Duo.
        confirmStop.element(boundBy: 0).tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "off"
        }, "Stopping sharing should persist Off in the peer's API response.")
        let peerAfterStop = api.member(personID: mainSession.personID, token: peerSession.token)
        XCTAssertEqual(peerAfterStop?["inboundLive"] as? Bool, false)
        XCTAssertTrue(peerAfterStop?["live"] == nil || peerAfterStop?["live"] is NSNull)

        let declinedSession = try XCTUnwrap(api.developmentSession(name: "DeclinedPeer", deviceID: "trust-decline-\(suffix)"))
        disposableTokens.append(declinedSession.token)
        let declinedHandle = "decline\(suffix.prefix(8))"
        XCTAssertEqual(api.putHandle(declinedHandle, token: declinedSession.token), 204)
        let declinedPhone = try XCTUnwrap(reservedPhones.dropFirst(2).first)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(declinedPhone)", token: declinedSession.token))
        XCTAssertTrue((200..<300).contains(api.createConnectionRequest(recipientID: mainSession.personID, token: declinedSession.token)))
        app.buttons["tab-you"].tap()
        app.buttons["tab-sharing"].tap()
        let decline = app.buttons["decline-connection-request-\(declinedHandle)"]
        XCTAssertTrue(decline.waitForExistence(timeout: 12))
        decline.tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            let incoming = self.api.connectionRequests(token: mainSession.token)?["incoming"] as? [[String: Any]] ?? []
            return incoming.isEmpty
        })
        XCTAssertNil(api.member(personID: declinedSession.personID, token: mainSession.token))
        XCTAssertEqual(api.createConnectionRequest(recipientID: mainSession.personID, token: declinedSession.token), 409, "Decline must enforce the server's directional cooldown.")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        XCTAssertFalse(app.buttons["accept-connection-request-\(declinedHandle)"].exists)
        XCTAssertTrue(waitUntil(timeout: 10) { self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "off" })
        attachScreenshot(of: app, named: "Requests - Declined and Stop persists after relaunch")

    }


    func testStopRemainsOffAcrossStaleCircleResponseAndRelaunch() throws {
        guard api.raceProxyState() != nil else {
            throw XCTSkip("This regression requires the loopback race proxy on port 5089, forwarding to the isolated Development API on port 5090.")
        }
        let fixture = try makeConnectedFixture(prefix: "stop-race")
        defer {
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        let connectionID = try setResting("sealed", personID: fixture.peer.personID, owner: fixture.main)

        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName)
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        let memberID = "sharing-mode-group-\(fixture.peerName.lowercased())"
        XCTAssertTrue(app.descendants(matching: .any)[memberID].waitForExistence(timeout: 15), app.debugDescription)
        let off = app.buttons["sharing-mode-off-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(app.buttons["sharing-mode-sealed-\(fixture.peerName.lowercased())"].isSelected)

        app.buttons["tab-you"].tap()
        XCTAssertTrue(api.armCircleRace(), "The loopback proxy must arm the held circle read.")
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { $0["holding"] as? Bool == true }, "Tab entry should hold the real pre-Stop circle response.")
        off.tap()
        let confirm = app.buttons.matching(identifier: "stop-sharing-confirm")
        XCTAssertTrue(confirm.firstMatch.waitForExistence(timeout: 5))
        confirm.element(boundBy: 0).tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["share_ack_count"] as? Int ?? 0) == 1 }, "The proxy must observe the successful Stop acknowledgement before releasing the stale read.")
        XCTAssertTrue(waitUntil(timeout: 8) { off.isSelected }, "The UI must apply the acknowledged Stop before the stale response is released.")
        XCTAssertTrue(api.releaseHeldCircle())
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["stale_release_count"] as? Int ?? 0) == 1 && ($0["circle_failure_count"] as? Int ?? 0) == 1 })
        XCTAssertTrue(waitUntil(timeout: 8) { off.isSelected }, "The acknowledged Stop must remain visibly Off after stale data and a failed refresh.")
        XCTAssertEqual(outboundPresentation(personID: fixture.peer.personID, token: fixture.main.token), "off")
        XCTAssertEqual(inboundPresentation(personID: fixture.main.personID, token: fixture.peer.token), "off")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        let ownHandle = app.buttons["copy-own-handle"]
        XCTAssertTrue(ownHandle.waitForExistence(timeout: 12), "Relaunch must restore the same main account.")
        XCTAssertEqual(ownHandle.value as? String, "@\(fixture.mainHandle)")
        let persisted = api.memberResponse(personID: fixture.peer.personID, token: fixture.main.token)
        XCTAssertEqual(persisted.status, 200)
        XCTAssertNotNil(persisted.member)
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(app.staticTexts["sharing-intro"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.descendants(matching: .any)[memberID].waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntil(timeout: 10) { app.buttons["sharing-mode-off-\(fixture.peerName.lowercased())"].isSelected }, "The same relationship must remain Off after relaunch.")
        XCTAssertNotEqual(connectionID, "", "The fixture should retain the connection identity it exercised.")
    }

    func testShareModeSelectionWaitsForSuccessAndPreservesPausedStateOnFailure() throws {
        guard api.raceProxyState() != nil else {
            throw XCTSkip("This regression requires the loopback race proxy on port 5089, forwarding to the isolated Development API on port 5090.")
        }
        let fixture = try makeConnectedFixture(prefix: "share-ack")
        defer {
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        let personID = fixture.peer.personID
        let peer = fixture.peerName.lowercased()
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "off")
        let initialRevision = try XCTUnwrap(activeShareRevision(personID: personID, token: fixture.main.token))

        let app = launchDevelopmentApp(
            deviceID: fixture.mainDeviceID,
            displayName: fixture.mainName,
            arguments: ["-appearancePreference", "light", "-trust.appLanguage", "en"]
        )
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        let group = app.descendants(matching: .any)["sharing-mode-group-\(peer)"]
        XCTAssertTrue(group.waitForExistence(timeout: 15), app.debugDescription)
        let off = app.buttons["sharing-mode-off-\(peer)"]
        let sealed = app.buttons["sharing-mode-sealed-\(peer)"]
        let always = app.buttons["sharing-mode-always-\(peer)"]
        let pending = app.staticTexts["sharing-pending-\(peer)"]
        let summary = app.staticTexts["sharing-summary-\(peer)"]
        XCTAssertTrue(off.isSelected)
        XCTAssertTrue(off.isEnabled)

        XCTAssertTrue(api.armShareResponse(failureAfterRelease: false))
        sealed.tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            $0["holding"] as? Bool == true && $0["held_resource"] as? String == "share"
        }, "The proxy should hold the successful Share response after the API has processed it.")
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "untilTheyLook")
        XCTAssertEqual(activeShareRevision(personID: personID, token: fixture.main.token), initialRevision + 1)
        XCTAssertTrue(off.isSelected, "Pending state must leave the last-confirmed Off selection visible.")
        XCTAssertFalse(sealed.isSelected)
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertTrue(off.isEnabled, "Off stays available while another mode update is pending.")
        XCTAssertEqual(api.raceProxyState()?["share_ack_count"] as? Int, 0,
                       "The client must not receive an acknowledgement until the held response is released.")

        off.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), "Off during an update must retain the explicit Stop confirmation.")
        let cancelStop = app.alerts.buttons["Cancel"]
        XCTAssertTrue(cancelStop.waitForExistence(timeout: 3))
        cancelStop.tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(off.isSelected)
        XCTAssertTrue(pending.exists)
        XCTAssertEqual(api.raceProxyState()?["share_ack_count"] as? Int, 0, "Canceling the Stop alert must not send another share request.")

        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitForProxyState(timeout: 12) { ($0["share_ack_count"] as? Int ?? 0) == 1 })
        XCTAssertTrue(waitUntil(timeout: 12) { sealed.isSelected && !pending.exists }, "The selection should change only after the successful response arrives.")
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "untilTheyLook")
        let sealedRevision = try XCTUnwrap(activeShareRevision(personID: personID, token: fixture.main.token))
        XCTAssertEqual(sealedRevision, initialRevision + 1)
        let firstShareExplainer = app.buttons["always-explainer-later"]
        if firstShareExplainer.waitForExistence(timeout: 3) {
            XCTAssertTrue(firstShareExplainer.isHittable)
            firstShareExplainer.tap()
            XCTAssertFalse(firstShareExplainer.waitForExistence(timeout: 3), "Dismiss only the first-share permission explanation before continuing the race fixture.")
        }

        app.buttons["sharing-actions-\(peer)"].tap()
        let pause = app.buttons["pause-sharing-\(peer)"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        let oneHour = app.buttons["pause-duration-3600"]
        XCTAssertTrue(oneHour.waitForExistence(timeout: 5))
        oneHour.tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            summary.exists && summary.label.localizedCaseInsensitiveContains("paused")
                && self.outboundPresentation(personID: personID, token: fixture.main.token) == "paused"
                && !pending.exists && sealed.isEnabled
        }, "The fixture must enter a real one-hour pause through the app before the failure case.")
        let pausedSummary = summary.label
        let pausedRevision = try XCTUnwrap(activeShareRevision(personID: personID, token: fixture.main.token))
        XCTAssertEqual(pausedRevision, sealedRevision + 1)
        XCTAssertFalse(off.isSelected)
        XCTAssertFalse(sealed.isSelected)
        XCTAssertFalse(always.isSelected)

        XCTAssertTrue(api.armShareResponse(failureAfterRelease: true))
        sealed.tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            $0["holding"] as? Bool == true && $0["held_resource"] as? String == "share"
        }, "The failed Share response should be held before it reaches the API.")
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "paused",
                       "The failure path must not mutate backend state before release.")
        XCTAssertEqual(activeShareRevision(personID: personID, token: fixture.main.token), pausedRevision)
        XCTAssertEqual(summary.label, pausedSummary, "Paused-until context remains visible during a pending mode request.")
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertTrue(off.isEnabled)
        XCTAssertFalse(off.isSelected)
        XCTAssertFalse(sealed.isSelected)
        XCTAssertFalse(always.isSelected)
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitForProxyState(timeout: 12) { ($0["share_failure_count"] as? Int ?? 0) == 1 })
        XCTAssertTrue(waitUntil(timeout: 12) { !pending.exists }, "The failed request should finish without changing the confirmed paused state.")
        XCTAssertEqual(api.raceProxyState()?["share_ack_count"] as? Int, 0, "A failed Share response must not count as an acknowledgement.")
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "paused")
        XCTAssertEqual(activeShareRevision(personID: personID, token: fixture.main.token), pausedRevision)
        XCTAssertEqual(summary.label, pausedSummary)
        XCTAssertFalse(off.isSelected)
        XCTAssertFalse(sealed.isSelected)
        XCTAssertFalse(always.isSelected)

        XCTAssertTrue(api.armShareResponse(failureAfterRelease: false))
        sealed.tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            $0["holding"] as? Bool == true && $0["held_resource"] as? String == "share"
        }, "Retry should hold the successful Share response after backend processing.")
        XCTAssertEqual(summary.label, pausedSummary, "The confirmed pause remains the visible state until retry acknowledgement.")
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertFalse(off.isSelected)
        XCTAssertFalse(sealed.isSelected)
        XCTAssertFalse(always.isSelected)
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "untilTheyLook")
        XCTAssertEqual(activeShareRevision(personID: personID, token: fixture.main.token), pausedRevision + 1)
        XCTAssertEqual(api.raceProxyState()?["share_ack_count"] as? Int, 0)
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitForProxyState(timeout: 12) { ($0["share_ack_count"] as? Int ?? 0) == 1 })
        XCTAssertTrue(waitUntil(timeout: 12) { sealed.isSelected && !summary.exists && !pending.exists })
        XCTAssertEqual(outboundPresentation(personID: personID, token: fixture.main.token), "untilTheyLook")
        XCTAssertEqual(activeShareRevision(personID: personID, token: fixture.main.token), pausedRevision + 1)
        attachScreenshot(of: app, named: "Sharing - acknowledged Sealed retry after a held failure")
    }

    func testRemoveStaysAbsentAfterStaleCircleResponseAndRelaunch() throws {
        guard api.raceProxyState() != nil else {
            throw XCTSkip("This regression requires the loopback race proxy on port 5089, forwarding to the isolated Development API on port 5090.")
        }
        let fixture = try makeConnectedFixture(prefix: "remove-race")
        defer {
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        _ = try setResting("sealed", personID: fixture.peer.personID, owner: fixture.main)

        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName)
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        let memberID = "sharing-mode-group-\(fixture.peerName.lowercased())"
        XCTAssertTrue(app.descendants(matching: .any)[memberID].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["tab-you"].tap()
        XCTAssertTrue(api.armCircleRace(), "The loopback proxy must arm the held circle read.")
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { $0["holding"] as? Bool == true }, "Tab entry should hold the real pre-Remove circle response.")

        let actions = app.buttons["sharing-actions-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()
        let remove = app.buttons["remove-person-action-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        let confirm = app.buttons.matching(identifier: "remove-person-confirm")
        XCTAssertTrue(confirm.firstMatch.waitForExistence(timeout: 5))
        confirm.element(boundBy: 0).tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["revoke_ack_count"] as? Int ?? 0) == 1 }, "The proxy must observe the successful Remove acknowledgement before releasing the stale read.")
        XCTAssertTrue(waitUntil(timeout: 8) { !app.descendants(matching: .any)[memberID].exists }, "The UI must apply the acknowledged Remove before the stale response is released.")
        XCTAssertTrue(api.releaseHeldCircle())
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["stale_release_count"] as? Int ?? 0) == 1 && ($0["circle_failure_count"] as? Int ?? 0) == 1 })
        XCTAssertTrue(waitUntil(timeout: 8) { !app.descendants(matching: .any)[memberID].exists }, "The acknowledged Remove must stay absent after stale data and a failed refresh.")
        XCTAssertNil(api.memberResponse(personID: fixture.peer.personID, token: fixture.main.token).member)
        XCTAssertNil(api.memberResponse(personID: fixture.main.personID, token: fixture.peer.token).member)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        let ownHandle = app.buttons["copy-own-handle"]
        XCTAssertTrue(ownHandle.waitForExistence(timeout: 12), "Relaunch must restore the same main account.")
        XCTAssertEqual(ownHandle.value as? String, "@\(fixture.mainHandle)")
        XCTAssertNil(api.memberResponse(personID: fixture.peer.personID, token: fixture.main.token).member)
        XCTAssertNil(api.memberResponse(personID: fixture.main.personID, token: fixture.peer.token).member)
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(app.staticTexts["sharing-intro"].waitForExistence(timeout: 12))
        XCTAssertTrue(waitUntil(timeout: 12) { !app.descendants(matching: .any)[memberID].exists }, "The removed relationship must remain absent after relaunch.")
    }

    func testStopAllFailureDoesNotPartiallyStopAndRetryPersistsAfterRelaunch() throws {
        guard api.raceProxyState() != nil else {
            throw XCTSkip("This regression requires the loopback fault proxy on port 5089, forwarding to the isolated Development API on port 5090.")
        }
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let mainName = "AllMain\(suffix.prefix(5))"
        let mainHandle = "am\(suffix.prefix(8))"
        let mainDeviceID = "trust-stop-all-main-\(suffix)"
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(3))
        let main = try makeTestAccount(displayName: mainName, deviceID: mainDeviceID, handle: mainHandle, phone: "+1\(phones[0])")
        let firstName = "AllAlpha\(suffix.prefix(5))"
        let secondName = "AllZulu\(suffix.prefix(5))"
        let first = try makeTestAccount(displayName: firstName, deviceID: "trust-stop-all-alpha-\(suffix)", handle: "aa\(suffix.prefix(8))", phone: "+1\(phones[1])")
        let second = try makeTestAccount(displayName: secondName, deviceID: "trust-stop-all-zulu-\(suffix)", handle: "az\(suffix.prefix(8))", phone: "+1\(phones[2])")
        defer {
            api.deleteAccount(token: second.token)
            api.deleteAccount(token: first.token)
            api.deleteAccount(token: main.token)
        }
        try connect(main, to: first)
        try connect(main, to: second)
        _ = try setResting("sealed", personID: first.personID, owner: main)
        _ = try setResting("sealed", personID: second.personID, owner: main)

        let app = launchDevelopmentApp(deviceID: mainDeviceID, displayName: mainName)
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        let firstID = "sharing-mode-group-\(firstName.lowercased())"
        let secondID = "sharing-mode-group-\(secondName.lowercased())"
        XCTAssertTrue(app.descendants(matching: .any)[firstID].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)[secondID].waitForExistence(timeout: 15), app.debugDescription)

        func confirmStopAll() {
            let stopAll = app.buttons["stop-all-sharing"]
            XCTAssertTrue(scrollUpUntilHittable(stopAll, in: app), "Stop All should be reachable in Sharing.\n\(app.debugDescription)")
            stopAll.tap()
            let confirm = app.buttons.matching(identifier: "stop-all-sharing-confirm")
            XCTAssertTrue(confirm.firstMatch.waitForExistence(timeout: 5))
            // SwiftUI can expose two automation aliases for this one alert action.
            confirm.element(boundBy: 0).tap()
        }

        XCTAssertTrue(api.armStopAllFailure(), "The proxy should fail the next atomic Stop All request.")
        confirmStopAll()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            ($0["stop_all_failure_count"] as? Int ?? 0) == 1
        }, "The proxy must observe one failed atomic Stop All request. State: \(api.raceProxyState() ?? [:])")
        XCTAssertEqual(api.raceProxyState()?["stop_all_ack_count"] as? Int, 0)
        XCTAssertEqual(outboundPresentation(personID: first.personID, token: main.token), "untilTheyLook")
        XCTAssertEqual(outboundPresentation(personID: second.personID, token: main.token), "untilTheyLook")
        XCTAssertTrue(app.buttons["sharing-mode-sealed-\(firstName.lowercased())"].isSelected)
        XCTAssertTrue(app.buttons["sharing-mode-sealed-\(secondName.lowercased())"].isSelected)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        let ownHandle = app.buttons["copy-own-handle"]
        XCTAssertTrue(ownHandle.waitForExistence(timeout: 12), "Relaunch must restore the same main account.")
        XCTAssertEqual(ownHandle.value as? String, "@\(mainHandle)")
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(waitUntil(timeout: 12) { app.buttons["sharing-mode-sealed-\(firstName.lowercased())"].isSelected })
        XCTAssertTrue(waitUntil(timeout: 12) { app.buttons["sharing-mode-sealed-\(secondName.lowercased())"].isSelected })

        api.resetRaceProxy()
        confirmStopAll()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            ($0["stop_all_ack_count"] as? Int ?? 0) == 1
        }, "The retry must commit one atomic Stop All request. State: \(api.raceProxyState() ?? [:])")
        XCTAssertEqual(outboundPresentation(personID: first.personID, token: main.token), "off")
        XCTAssertEqual(outboundPresentation(personID: second.personID, token: main.token), "off")
        XCTAssertTrue(waitUntil(timeout: 12) { app.buttons["sharing-mode-off-\(firstName.lowercased())"].isSelected })
        XCTAssertTrue(waitUntil(timeout: 12) { app.buttons["sharing-mode-off-\(secondName.lowercased())"].isSelected })

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.buttons["copy-own-handle"].waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons["copy-own-handle"].value as? String, "@\(mainHandle)")
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(waitUntil(timeout: 12) { app.buttons["sharing-mode-off-\(firstName.lowercased())"].isSelected })
        XCTAssertTrue(waitUntil(timeout: 12) { app.buttons["sharing-mode-off-\(secondName.lowercased())"].isSelected })
        XCTAssertEqual(outboundPresentation(personID: first.personID, token: main.token), "off")
        XCTAssertEqual(outboundPresentation(personID: second.personID, token: main.token), "off")
    }

    func testDelayedLookResponseIsDiscardedAfterReplacementRelationship() throws {
        guard api.raceProxyState() != nil else {
            throw XCTSkip("This regression requires the loopback fault proxy on port 5089, forwarding to the isolated Development API on port 5090.")
        }
        let fixture = try makeConnectedFixture(prefix: "look-race")
        defer {
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        _ = try setResting("sealed", personID: fixture.main.personID, owner: fixture.peer)
        let oldConnectionID = try XCTUnwrap(activeConnectionID(personID: fixture.main.personID, token: fixture.peer.token))
        XCTAssertEqual(uploadTestLocation(points: makeLocationPoints(count: 1), token: fixture.peer.token), 204)

        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName)
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 15))
        let row = app.buttons["person-row-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        row.tap()
        let lookAction = app.buttons["person-profile-peek"]
        XCTAssertTrue(lookAction.waitForExistence(timeout: 12), "The Sealed person screen should offer a Look action.")
        XCTAssertTrue(api.armLookRace(), "Arm the proxy to capture the Look response body.")
        lookAction.tap()
        let confirm = app.buttons["confirm-look-notify"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) { $0["holding"] as? Bool == true && $0["held_resource"] as? String == "look" }, "Confirming Look should start the held response.")
        XCTAssertTrue(waitUntil(timeout: 8) { self.api.hasLookEvent(subjectID: fixture.peer.personID, token: fixture.main.token) }, "The server should process the Look before its sensitive response is released.")

        let replacementConnectionID = try replaceConnection(subject: fixture.peer, viewer: fixture.main, newShare: "sealed")
        XCTAssertNotEqual(replacementConnectionID, oldConnectionID, "Re-adding must create a different relationship identity.")
        XCTAssertEqual(inboundPresentation(personID: fixture.peer.personID, token: fixture.main.token), "untilTheyLook")
        XCTAssertTrue(api.releaseHeldResponse(), "Release the old Look response after the server has replaced the relationship.")
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["look_release_count"] as? Int ?? 0) == 1 })
        XCTAssertTrue(waitUntil(timeout: 8) { !app.buttons["confirm-look-notify"].exists }, "The app must finish handling the delayed Look before the result is checked.")
        Thread.sleep(forTimeInterval: 0.5) // AppModel delays navigation by 320 ms after a valid Look.
        XCTAssertFalse(app.buttons["view-open-map"].exists, "A delayed snapshot from the removed relationship must not open on its replacement.")
        XCTAssertEqual(try XCTUnwrap(activeConnectionID(personID: fixture.main.personID, token: fixture.peer.token)), replacementConnectionID)
        XCTAssertEqual(api.memberResponse(personID: fixture.peer.personID, token: fixture.main.token).status, 200)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        let ownHandle = app.buttons["copy-own-handle"]
        XCTAssertTrue(ownHandle.waitForExistence(timeout: 12))
        XCTAssertEqual(ownHandle.value as? String, "@\(fixture.mainHandle)")
        app.buttons["tab-circle"].tap()
        let relaunchedRow = app.buttons["person-row-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(relaunchedRow.waitForExistence(timeout: 12))
        relaunchedRow.tap()
        XCTAssertTrue(app.buttons["person-profile-peek"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["view-open-map"].exists, "Relaunch must not reveal a snapshot retained from the prior relationship.")
    }

    /// Exercises consent revalidation against real HTTP with an isolated store and the existing
    /// Development entitlement fixture. This is not an Apple purchase/receipt test.
    func testDelayedHistoryFixtureCannotReappearAfterStopRemoveAndReconnect() throws {
        guard api.raceProxyState() != nil else {
            throw XCTSkip("Requires the isolated loopback fault proxy and Development entitlement fixture.")
        }
        let fixture = try makeConnectedFixture(prefix: "history-stop-race")
        defer {
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        XCTAssertEqual(api.request("POST", "/api/v1/circle/entitlement", token: fixture.peer.token,
                                   body: ["reviewUnlock": true]).status, 204,
                       "Only the existing isolated Development fixture supplies Plus in this consent test.")
        _ = try setResting("always", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(uploadTestLocation(points: makeLocationPoints(count: 3), token: fixture.peer.token), 204)
        let originalConnection = try XCTUnwrap(activeConnectionID(personID: fixture.peer.personID, token: fixture.main.token))
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName,
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        let row = app.buttons["person-row-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(api.armHistoryRace())
        row.tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            $0["held_resource"] as? String == "history" && ($0["history_hold_count"] as? Int) == 1
                && ($0["history_status_count"] as? Int) == 200 && ($0["history_point_count"] as? Int) == 3
        }, "The proxy must hold a successful, populated History response before Stop.")
        XCTAssertTrue(element("person-history-loading", in: app).waitForExistence(timeout: 5))

        _ = try setResting("off", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(api.request("GET", "/api/v1/people/\(fixture.peer.personID)/history", token: fixture.main.token).status, 409)
        // Do not refresh the app first: the in-flight result itself must revalidate
        // server consent, just as Look does, before retaining sensitive locations.
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["history_release_count"] as? Int) == 1 })
        XCTAssertTrue(waitUntil(timeout: 15) { !self.element("person-history-loading", in: app).exists })
        XCTAssertFalse(element("person-history", in: app).exists,
                       "A History body fetched before the peer stopped must not restore visits after Stop.")
        XCTAssertFalse(element("person-history-visit-0", in: app).exists)
        XCTAssertFalse(element("person-history-error", in: app).exists,
                       "Confirmed Stop should reconcile the consent state rather than show a generic loading error.")
        attachScreenshot(of: app, named: "History - Stopped while response was in flight")

        let replacement = try replaceConnection(subject: fixture.peer, viewer: fixture.main, newShare: "sealed")
        XCTAssertNotEqual(replacement, originalConnection)
        app.buttons["tab-sharing"].tap()
        app.buttons["tab-circle"].tap()
        if app.buttons["circle-back"].exists { app.buttons["circle-back"].tap() }
        XCTAssertTrue(row.waitForExistence(timeout: 12))
        row.tap()
        XCTAssertTrue(app.buttons["person-profile-peek"].waitForExistence(timeout: 12))
        XCTAssertFalse(element("person-history", in: app).exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.buttons["person-profile-peek"].waitForExistence(timeout: 12))
        XCTAssertFalse(element("person-history", in: app).exists,
                       "Reconnection and relaunch must not recover history from the removed relationship.")
        XCTAssertEqual(activeConnectionID(personID: fixture.peer.personID, token: fixture.main.token), replacement)
    }

    func testDelayedHistoryFixtureStaysClosedWhenConsentRefreshIsOffline() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated fault proxy and Development entitlement fixture.") }
        let fixture = try makeConnectedFixture(prefix: "history-refresh-offline")
        defer {
            _ = api.request("POST", "/__test/reconnect", body: [:])
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        XCTAssertEqual(api.request("POST", "/api/v1/circle/entitlement", token: fixture.peer.token, body: ["reviewUnlock": true]).status, 204)
        _ = try setResting("always", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(uploadTestLocation(points: makeLocationPoints(count: 3), token: fixture.peer.token), 204)
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName,
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        let row = app.buttons["person-row-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(api.armHistoryRace())
        row.tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) {
            $0["held_resource"] as? String == "history" && ($0["history_status_count"] as? Int) == 200
                && ($0["history_point_count"] as? Int) == 3
        })
        _ = try setResting("off", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(api.request("POST", "/__test/arm-offline", body: ["accountId": fixture.main.personID]).status, 200)
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitForProxyState(timeout: 12) { ($0["offline_circle_count"] as? Int ?? 0) > 0 },
                      "A sensitive result must attempt authoritative consent revalidation.")
        XCTAssertTrue(element("person-history-error", in: app).waitForExistence(timeout: 12),
                      "Unavailable consent must keep locations closed and offer recovery.")
        XCTAssertFalse(element("person-history", in: app).exists)
        XCTAssertFalse(element("person-history-visit-0", in: app).exists)
        XCTAssertFalse(element("person-history-loading", in: app).exists)
        attachScreenshot(of: app, named: "History - Consent refresh failed closed with Retry")
        XCTAssertEqual(api.request("POST", "/__test/reconnect", body: [:]).status, 200)
        app.buttons["tab-sharing"].tap()
        app.buttons["tab-circle"].tap()
        XCTAssertTrue(waitUntil(timeout: 12) { !self.element("person-history-error", in: app).exists })
        XCTAssertFalse(element("person-history", in: app).exists)
    }

    func testDelayedLookStaysClosedWhenConsentRefreshIsOffline() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated loopback fault proxy.") }
        let fixture = try makeConnectedFixture(prefix: "look-refresh-offline")
        defer {
            _ = api.request("POST", "/__test/reconnect", body: [:])
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        _ = try setResting("sealed", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(uploadTestLocation(points: makeLocationPoints(count: 1), token: fixture.peer.token), 204)
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName,
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        let row = app.buttons["person-row-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(api.armLookRace())
        app.buttons["person-profile-peek"].tap()
        XCTAssertTrue(app.buttons["confirm-look-notify"].waitForExistence(timeout: 8))
        app.buttons["confirm-look-notify"].tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) { $0["held_resource"] as? String == "look" })
        _ = try setResting("off", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(api.request("POST", "/__test/arm-offline", body: ["accountId": fixture.main.personID]).status, 200)
        XCTAssertTrue(api.releaseHeldResponse())
        XCTAssertTrue(waitForProxyState(timeout: 12) { ($0["offline_circle_count"] as? Int ?? 0) > 0 })
        XCTAssertTrue(waitUntil(timeout: 12) { !app.buttons["confirm-look-notify"].exists })
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(app.buttons["view-open-map"].exists,
                       "A successful Look response is insufficient if current consent cannot be revalidated.")
        XCTAssertFalse(element("person-history", in: app).exists)
        attachScreenshot(of: app, named: "Look - Consent refresh failed closed")
        XCTAssertEqual(api.request("POST", "/__test/reconnect", body: [:]).status, 200)
        app.buttons["tab-sharing"].tap()
        app.buttons["tab-circle"].tap()
        XCTAssertTrue(waitUntil(timeout: 12) { !app.buttons["person-profile-peek"].exists })
        XCTAssertFalse(app.buttons["view-open-map"].exists)
    }

    func testOfflinePeerRemovalReconcilesAfterRelaunchAndReconnect() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated loopback fault proxy.") }
        let fixture = try makeConnectedFixture(prefix: "offline-revoke")
        defer {
            _ = api.request("POST", "/__test/reconnect", body: [:])
            api.deleteAccount(token: fixture.peer.token)
            api.deleteAccount(token: fixture.main.token)
        }
        _ = try setResting("sealed", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(uploadTestLocation(points: makeLocationPoints(count: 1), token: fixture.peer.token), 204)
        let connection = try XCTUnwrap(activeConnectionID(personID: fixture.main.personID, token: fixture.peer.token))
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName,
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        let row = app.buttons["person-row-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Cache the connected peer before interruption.")
        XCTAssertEqual(api.request("POST", "/__test/arm-offline", body: ["accountId": fixture.main.personID]).status, 200)
        _ = try setResting("off", personID: fixture.main.personID, owner: fixture.peer)
        XCTAssertEqual(api.request("POST", "/api/v1/people/\(fixture.main.personID)/revoke", token: fixture.peer.token,
                                   body: ["connectionId": connection]).status, 204)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(waitForProxyState(timeout: 12) { ($0["offline_circle_count"] as? Int ?? 0) > 0 },
                      "The relaunched account must actually encounter the simulated network outage.")
        let offline = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Offline · people from")).firstMatch
        XCTAssertTrue(offline.waitForExistence(timeout: 10), "The person needs visible context that this is cached state.")
        let share = app.buttons["sharing-mode-off-\(fixture.peerName.lowercased())"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "The previously connected peer must actually be restored from the account's disk cache.")
        XCTAssertFalse(app.buttons["view-open-map"].exists)
        XCTAssertFalse(element("person-history", in: app).exists)
        attachScreenshot(of: app, named: "Offline - Relaunched while peer removed the connection")

        XCTAssertEqual(api.request("POST", "/__test/reconnect", body: [:]).status, 200)
        XCTAssertTrue(successfulCircleOmitsMember(personID: fixture.peer.personID, token: fixture.main.token))
        app.buttons["tab-circle"].tap()
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(waitUntil(timeout: 15) { !share.exists }, "A successful reconnect must remove the stale sharing controls.")
        XCTAssertTrue(waitUntil(timeout: 10) { !offline.exists }, "A successful Circle response must clear the offline banner.")
        app.buttons["tab-circle"].tap()
        XCTAssertTrue(waitUntil(timeout: 15) { !row.exists }, "The removed peer must disappear after the successful Circle refresh.")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 15))
        XCTAssertFalse(row.exists, "The confirmed removal must replace the offline disk cache.")
        XCTAssertFalse(element("person-history", in: app).exists)
        XCTAssertFalse(app.buttons["view-open-map"].exists)
    }

    func testAddPersonCanRetrySameQueryAndConfirmedSendSurvivesFailedLookup() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated loopback fault proxy.") }
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let numbers = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let main = try makeTestAccount(displayName: "AddMain\(suffix)", deviceID: "add-main-\(suffix)",
                                       handle: "am\(suffix)", phone: "+1\(numbers[0])")
        let peer = try makeTestAccount(displayName: "AddPeer\(suffix)", deviceID: "add-peer-\(suffix)",
                                       handle: "ap\(suffix)", phone: "+1\(numbers[1])")
        defer { api.deleteAccount(token: peer.token); api.deleteAccount(token: main.token) }
        let app = launchDevelopmentApp(deviceID: "add-main-\(suffix)", displayName: "AddMain\(suffix)",
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        app.buttons["tab-sharing"].tap()
        app.buttons["add-someone-button"].tap()
        let query = app.textFields["connection-handle"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        XCTAssertEqual(api.request("POST", "/__test/arm-lookup-failure", body: [:]).status, 200)
        query.typeText("ap\(suffix)")
        XCTAssertTrue(app.staticTexts["connection-lookup-notice"].waitForExistence(timeout: 10))
        let retry = app.buttons["retry-connection-lookup"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "A failed search must offer recovery without requiring an edit.")
        XCTAssertTrue(retry.isHittable, "Recovery remains usable with the keyboard visible.")
        XCTAssertGreaterThanOrEqual(retry.frame.width, 44)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        attachScreenshot(of: app, named: "Add - Failed exact handle with same-query Retry")
        retry.tap()
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10))
        XCTAssertEqual(query.value as? String, "ap\(suffix)", "Retry must preserve what the person typed.")
        XCTAssertFalse(app.staticTexts["connection-lookup-notice"].exists)
        XCTAssertEqual(api.raceProxyState()?["lookup_failure_count"] as? Int, 1)
        let sendsBefore = api.raceProxyState()?["connection_send_count"] as? Int ?? 0
        XCTAssertEqual(api.request("POST", "/__test/arm-lookup-failure-after-send", body: [:]).status, 200)
        app.buttons["send-connection-request"].tap()
        XCTAssertTrue(app.staticTexts["connection-lookup-sent"].waitForExistence(timeout: 12),
                      "A confirmed Send must remain acknowledged even if the following identity refresh fails.")
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["lookup_failure_count"] as? Int) == 2 })
        XCTAssertFalse(app.buttons["send-connection-request"].exists, "A reconciliation failure must not offer a duplicate Send.")
        XCTAssertEqual(api.raceProxyState()?["connection_send_count"] as? Int, sendsBefore + 1)
        XCTAssertEqual((api.connectionRequests(token: main.token)?["sent"] as? [[String: Any]])?.count, 1)
        XCTAssertTrue((api.circle(token: main.token)?["members"] as? [[String: Any]])?.isEmpty ?? false,
                      "A pending request must never start a connection or sharing.")
        attachScreenshot(of: app, named: "Add - Confirmed request stays Pending after refresh failure")
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertEqual(api.request("POST", "/__test/arm-stale-lookup", body: [:]).status, 200)
        retry.tap()
        XCTAssertTrue(app.staticTexts["connection-lookup-sent"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["send-connection-request"].exists,
                       "A contradictory identity lookup must not undo a confirmed pending request.")
        XCTAssertEqual(api.raceProxyState()?["connection_send_count"] as? Int, sendsBefore + 1)
        app.buttons["cancel-add-person"].tap()
        let cancel = app.buttons["cancel-connection-request-ap\(suffix)"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertEqual(api.request("POST", "/__test/arm-request-action-failure", body: [:]).status, 200)
        cancel.tap()
        let cancelRetry = app.buttons["retry-connection-request-ap\(suffix)"]
        XCTAssertTrue(cancelRetry.waitForExistence(timeout: 10), "A failed Cancel must leave a named, retryable request.")
        XCTAssertEqual((api.connectionRequests(token: main.token)?["sent"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(api.request("POST", "/__test/arm-request-refresh-failure", body: [:]).status, 200)
        cancelRetry.tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["request_list_failure_count"] as? Int ?? 0) > 0 })
        XCTAssertTrue(waitUntil(timeout: 8) { !cancel.exists && !cancelRetry.exists },
                      "A confirmed Cancel must remain complete when the follow-up list cannot be loaded.")
        XCTAssertTrue(waitUntil(timeout: 10) { (self.api.connectionRequests(token: main.token)?["sent"] as? [[String: Any]])?.isEmpty == true })
    }

    func testFailedAcceptKeepsNamedRequestAndOtherRequestsAvailableForRetry() throws {
        guard api.raceProxyState() != nil else { throw XCTSkip("Requires the isolated loopback fault proxy.") }
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(3))
        let main = try makeTestAccount(displayName: "Requests\(suffix)", deviceID: "requests-\(suffix)", handle: "rq\(suffix)", phone: "+1\(phones[0])")
        let first = try makeTestAccount(displayName: "First\(suffix)", deviceID: "first-\(suffix)", handle: "rf\(suffix)", phone: "+1\(phones[1])")
        let second = try makeTestAccount(displayName: "Second\(suffix)", deviceID: "second-\(suffix)", handle: "rs\(suffix)", phone: "+1\(phones[2])")
        defer { [second, first, main].forEach { api.deleteAccount(token: $0.token) } }
        XCTAssertEqual(api.createConnectionRequest(recipientID: main.personID, token: first.token), 200)
        XCTAssertEqual(api.createConnectionRequest(recipientID: main.personID, token: second.token), 200)
        let app = launchDevelopmentApp(deviceID: "requests-\(suffix)", displayName: "Requests\(suffix)",
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        app.buttons["tab-sharing"].tap()
        let acceptFirst = app.buttons["accept-connection-request-rf\(suffix)"]
        let acceptSecond = app.buttons["accept-connection-request-rs\(suffix)"]
        XCTAssertTrue(acceptFirst.waitForExistence(timeout: 12))
        XCTAssertTrue(acceptSecond.exists)
        XCTAssertEqual(api.request("POST", "/__test/arm-request-action-failure", body: [:]).status, 200)
        acceptFirst.tap()
        XCTAssertTrue(element("connection-request-error-rf\(suffix)", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(acceptFirst.exists, "Keep the named failed request available so the person can retry it.")
        XCTAssertTrue(acceptSecond.exists, "A failure on one request must not hide another person's request.")
        XCTAssertTrue(waitUntil(timeout: 8) { acceptFirst.isEnabled })
        XCTAssertEqual((api.connectionRequests(token: main.token)?["incoming"] as? [[String: Any]])?.count, 2)
        attachScreenshot(of: app, named: "Requests - Failed Accept retains both named requests")
        let retryFirst = app.buttons["retry-connection-request-rf\(suffix)"]
        XCTAssertTrue(retryFirst.waitForExistence(timeout: 5))
        XCTAssertTrue(retryFirst.isHittable)
        XCTAssertGreaterThanOrEqual(retryFirst.frame.width, 44)
        retryFirst.tap()
        XCTAssertTrue(waitUntil(timeout: 12) { self.api.member(personID: first.personID, token: main.token) != nil })
        XCTAssertTrue(waitUntil(timeout: 8) { !self.element("connection-request-error-rf\(suffix)", in: app).exists })
        XCTAssertEqual(inboundPresentation(personID: first.personID, token: main.token), "off")
        XCTAssertEqual(outboundPresentation(personID: first.personID, token: main.token), "off")
        let declineSecond = app.buttons["decline-connection-request-rs\(suffix)"]
        XCTAssertTrue(declineSecond.waitForExistence(timeout: 8))
        XCTAssertEqual(api.request("POST", "/__test/arm-request-refresh-failure", body: [:]).status, 200)
        declineSecond.tap()
        XCTAssertTrue(waitForProxyState(timeout: 8) { ($0["request_list_failure_count"] as? Int ?? 0) > 0 })
        XCTAssertTrue(waitUntil(timeout: 8) { !declineSecond.exists },
                      "A confirmed Decline must not remain actionable when the following list refresh fails.")
        XCTAssertTrue(waitUntil(timeout: 10) { (self.api.connectionRequests(token: main.token)?["incoming"] as? [[String: Any]])?.isEmpty == true })
        XCTAssertNil(api.member(personID: second.personID, token: main.token))
    }

    func testPauseShowsMultiDayEndAndExplicitResumeRestoresOnlyThatPerson() throws {
        let fixture = try makeConnectedFixture(prefix: "pause-story")
        defer { api.deleteAccount(token: fixture.peer.token); api.deleteAccount(token: fixture.main.token) }
        _ = try setResting("sealed", personID: fixture.peer.personID, owner: fixture.main)
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName,
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        app.buttons["tab-sharing"].tap()
        let name = fixture.peerName.lowercased()
        let actions = app.buttons["sharing-actions-\(name)"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        let pause = app.buttons["pause-sharing-\(name)"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        let threeDays = app.buttons["pause-duration-259200"]
        XCTAssertTrue(threeDays.waitForExistence(timeout: 8))
        XCTAssertTrue(threeDays.isHittable)
        attachScreenshot(of: app, named: "Pause - Named person and restoration explanation")
        threeDays.tap()
        let summary = app.staticTexts["sharing-summary-\(name)"]
        XCTAssertTrue(waitUntil(timeout: 12) { summary.exists && self.outboundPresentation(personID: fixture.peer.personID, token: fixture.main.token) == "paused" })
        XCTAssertTrue(summary.label.contains("Sealed"))
        XCTAssertGreaterThan(summary.label.filter(\.isLetter).count, "Paused until Back to Sealed".filter(\.isLetter).count,
                             "A multi-day pause must include a day/date, not only the clock time.")
        XCTAssertEqual(inboundPresentation(personID: fixture.main.personID, token: fixture.peer.token), "paused")
        attachScreenshot(of: app, named: "Pause - Three day end date and time")
        actions.tap()
        let resume = app.buttons["resume-sharing-\(name)"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5), "Resuming should be explicit rather than inferred from the mode rail.")
        XCTAssertTrue(resume.label.contains("Sealed"))
        attachScreenshot(of: app, named: "Pause - Explicit Resume Sealed action")
        resume.tap()
        XCTAssertTrue(waitUntil(timeout: 12) { self.outboundPresentation(personID: fixture.peer.personID, token: fixture.main.token) == "untilTheyLook" })
        XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["sharing-mode-sealed-\(name)"].isSelected && !summary.exists })
        XCTAssertEqual(outboundPresentation(personID: fixture.main.personID, token: fixture.peer.token), "off",
                       "Resuming my share must not turn on the other person's share.")
        let locationLater = app.buttons["always-explainer-later"]
        if locationLater.waitForExistence(timeout: 2) {
            locationLater.tap()
            XCTAssertTrue(waitUntil(timeout: 8) { !locationLater.exists })
        }
        XCTAssertTrue(waitUntil(timeout: 8) { actions.isHittable })
        actions.tap()
        let details = app.buttons["presence-grant-details-\(name)"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Home-arrival alert")).firstMatch.exists,
                      "The full status, alert and suppression disclosure must be readable outside a truncated menu row.")
        attachScreenshot(of: app, named: "Sharing - Full Home and Away disclosure")
        app.alerts.buttons.matching(identifier: "presence-grant-details-close").firstMatch.tap()
        XCTAssertEqual(api.member(personID: fixture.peer.personID, token: fixture.main.token)?["outboundPresenceGranted"] as? Bool, false,
                       "Reading the explanation must not turn on status sharing.")
    }

    func testProfilePictureIsStagedAndDiscoveryStaysExplicitAcrossRelaunch() throws {
        let fixture = try makeConnectedFixture(prefix: "profile-story")
        defer { api.deleteAccount(token: fixture.peer.token); api.deleteAccount(token: fixture.main.token) }
        func ownProfile() -> [String: Any] { api.circle(token: fixture.main.token)?["you"] as? [String: Any] ?? [:] }
        XCTAssertEqual(ownProfile()["discoveryEnabled"] as? Bool, false)
        let app = launchDevelopmentApp(deviceID: fixture.mainDeviceID, displayName: fixture.mainName,
                                       arguments: ["-trust.appLanguage", "en"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        XCTAssertEqual(app.buttons["copy-own-handle"].value as? String, "@\(fixture.mainHandle)")
        let edit = app.buttons["edit-profile-picture"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        edit.tap()
        XCTAssertTrue(app.buttons["avatar-photo-options"].waitForExistence(timeout: 8))
        app.buttons["Fox icon"].tap()
        XCTAssertTrue(app.buttons["avatar-save"].isEnabled)
        XCTAssertNil(ownProfile()["avatar"] as? [String: Any], "Choosing a picture must not save it before Save.")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 8))
        XCTAssertNil(ownProfile()["avatar"] as? [String: Any])
        edit.tap()
        XCTAssertTrue(app.buttons["Fox icon"].waitForExistence(timeout: 8))
        app.buttons["Fox icon"].tap()
        app.buttons["avatar-save"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) { (ownProfile()["avatar"] as? [String: Any])?["presetId"] as? String == "fox" })
        XCTAssertEqual(ownProfile()["discoveryEnabled"] as? Bool, false,
                       "Saving a picture must never opt the person into discovery.")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 15))
        app.buttons["tab-you"].tap()
        XCTAssertEqual(app.buttons["copy-own-handle"].value as? String, "@\(fixture.mainHandle)")
        let discovery = app.switches["phone-discovery-toggle"]
        XCTAssertTrue(discovery.waitForExistence(timeout: 8))
        XCTAssertFalse(isSwitchOn(discovery))
        discovery.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { ownProfile()["discoveryEnabled"] as? Bool == true })
        XCTAssertTrue(waitUntil(timeout: 5) { discovery.isEnabled })
        discovery.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { ownProfile()["discoveryEnabled"] as? Bool == false })
        XCTAssertEqual(inboundPresentation(personID: fixture.peer.personID, token: fixture.main.token), "off")
        XCTAssertEqual(outboundPresentation(personID: fixture.peer.personID, token: fixture.main.token), "off")
        attachScreenshot(of: app, named: "Profile - Saved picture with explicit discovery off and sharing off")
        edit.tap()
        XCTAssertTrue(app.buttons["avatar-photo-options"].waitForExistence(timeout: 8))
        app.buttons["avatar-photo-options"].tap()
        XCTAssertTrue(app.buttons["avatar-remove"].waitForExistence(timeout: 5))
        app.buttons["avatar-remove"].tap()
        XCTAssertNotNil(ownProfile()["avatar"] as? [String: Any], "Removal is staged until Save too.")
        app.buttons["avatar-save"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) { ownProfile()["avatar"] as? [String: Any] == nil })
        XCTAssertEqual(ownProfile()["discoveryEnabled"] as? Bool, false)
    }

    private func makeConnectedFixture(prefix: String) throws -> ConnectedTestFixture {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let mainName = "RaceMain\(suffix.prefix(6))"
        let peerName = "RacePeer\(suffix.prefix(6))"
        let mainDeviceID = "trust-\(prefix)-main-\(suffix)"
        let peerDeviceID = "trust-\(prefix)-peer-\(suffix)"
        let handles = ("ma\(suffix.prefix(8))", "pe\(suffix.prefix(8))")
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let main = try makeTestAccount(displayName: mainName, deviceID: mainDeviceID, handle: handles.0, phone: "+1\(phones[0])")
        let peer = try makeTestAccount(displayName: peerName, deviceID: peerDeviceID, handle: handles.1, phone: "+1\(phones[1])")
        try connect(main, to: peer)
        return ConnectedTestFixture(main: main, peer: peer, mainName: mainName, peerName: peerName, mainDeviceID: mainDeviceID, mainHandle: handles.0)
    }

    private func makeTestAccount(displayName: String, deviceID: String, handle: String, phone: String) throws -> DisposableSession {
        let session = try XCTUnwrap(api.developmentSession(name: displayName, deviceID: deviceID))
        XCTAssertEqual(api.putHandle(handle, token: session.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: phone, token: session.token), "The fixture phone must be verified through the Development OTP path.")
        return session
    }

    private func connect(_ requester: DisposableSession, to recipient: DisposableSession) throws {
        let request = api.request("POST", "/api/v1/connection-requests", token: requester.token, body: ["recipientId": recipient.personID])
        XCTAssertEqual(request.status, 200)
        let requestID = try XCTUnwrap((request.json as? [String: Any])?["id"] as? String)
        XCTAssertEqual(api.request("POST", "/api/v1/connection-requests/\(requestID)/accept", token: recipient.token).status, 204)
    }

    private func replaceConnection(subject: DisposableSession, viewer: DisposableSession, newShare: String) throws -> String {
        let oldConnectionID = try XCTUnwrap(activeConnectionID(personID: viewer.personID, token: subject.token))
        _ = try setResting("off", personID: viewer.personID, owner: subject)
        let removed = api.request(
            "POST",
            "/api/v1/people/\(viewer.personID)/revoke",
            token: subject.token,
            body: ["connectionId": oldConnectionID]
        )
        XCTAssertEqual(removed.status, 204, "The peer should remove the old relationship through the real API.")
        try connect(viewer, to: subject)
        let newConnectionID = try XCTUnwrap(activeConnectionID(personID: viewer.personID, token: subject.token))
        XCTAssertNotEqual(newConnectionID, oldConnectionID)
        _ = try setResting(newShare, personID: viewer.personID, owner: subject)
        return newConnectionID
    }

    private func makeLocationPoints(count: Int) -> [[String: Any]] {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var points: [[String: Any]] = []
        points.reserveCapacity(count)
        for index in 0..<count {
            let secondsAgo = -120.0 * Double(index)
            let timestamp = formatter.string(from: now.addingTimeInterval(secondsAgo))
            let latitude = 47.60 + Double(index) * 0.001
            let longitude = -122.33 - Double(index) * 0.001
            let point: [String: Any] = [
                "timestamp": timestamp,
                "latitude": latitude,
                "longitude": longitude
            ]
            points.append(point)
        }
        return points
    }

    private func uploadTestLocation(points: [[String: Any]], token: String) -> Int {
        guard let current = points.first,
              let timestamp = current["timestamp"],
              let latitude = current["latitude"],
              let longitude = current["longitude"] else { return 0 }
        return api.request(
            "POST",
            "/api/v1/location",
            token: token,
            body: [
                "timestamp": timestamp,
                "latitude": latitude,
                "longitude": longitude,
                "batteryPercent": 75,
                "isCharging": false,
                "points": points
            ]
        ).status
    }

    @discardableResult
    private func setResting(_ resting: String, personID: String, owner: DisposableSession) throws -> String {
        let connectionID = try XCTUnwrap(activeConnectionID(personID: personID, token: owner.token))
        let revision = try XCTUnwrap(activeShareRevision(personID: personID, token: owner.token))
        XCTAssertEqual(api.request(
            "PATCH",
            "/api/v1/people/\(personID)/share",
            token: owner.token,
            body: ["connectionId": connectionID, "revision": revision, "resting": resting]
        ).status, 204)
        return connectionID
    }

    private func launchDevelopmentApp(deviceID: String, displayName: String, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = displayName
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        configureLocalAgeFixture(for: app)
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        completeLocalAgeFixture(in: app)
        return app
    }

    private func configureLocalAgeFixture(for app: XCUIApplication) {
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
    }

    /// Use the app's existing DEBUG-only self-attestation fixture so these API tests
    /// do not inherit the simulator's Apple age range or change production age checks.
    private func completeLocalAgeFixture(in app: XCUIApplication) {
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_STATE")
        let month = app.textFields["age-birth-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 15), "The explicit DEBUG age fixture should start at the birth-date gate.\n\(app.debugDescription)")
        guard month.exists else { return }
        let day = app.textFields["age-birth-day"]
        let year = app.textFields["age-birth-year"]
        for (field, value) in [(month, "01"), (day, "01"), (year, "1990")] {
            field.tap()
            field.typeText(value)
            let inputApplied = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", value),
                object: field
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [inputApplied], timeout: 5),
                .completed,
                "The DEBUG age fixture should enter \(field.identifier)=\(value); current value: \(field.value ?? "<empty>")."
            )
        }
        let proceed = app.buttons["age-gate-continue"]
        XCTAssertTrue(waitUntil(timeout: 5) { proceed.isEnabled }, "The eligible local age fixture should enable Continue.")
        proceed.tap()
        XCTAssertTrue(waitUntil(timeout: 30) {
            app.textFields.firstMatch.exists
                || app.buttons["tab-circle"].exists
                || app.buttons["age-privacy-hold-delete-account"].exists
        }, "The eligible DEBUG age fixture should reach onboarding, the signed-in app, or its server privacy-hold screen.\n\(app.debugDescription)")
    }

    private func sameAccountHomeHandoffSession() throws -> (deviceID: String, token: String) {
        guard let deviceID = ProcessInfo.processInfo.environment["TRUST_UI_HOME_HANDOFF_DEVICE_ID"],
              deviceID.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil else {
            throw XCTSkip("Set one unique TRUST_UI_HOME_HANDOFF_DEVICE_ID for all serial handoff phases and both simulators.")
        }
        let session = try XCTUnwrap(api.developmentSession(name: "HomeHandoff", deviceID: deviceID))
        let profile = api.circle(token: session.token)?["you"] as? [String: Any]
        if profile?["onboardingComplete"] as? Bool != true {
            XCTAssertEqual(api.putHandle("homehandoff", token: session.token), 204)
            let phone = try XCTUnwrap(LocalTrustAPI.reservedPhonePool().randomElement())
            XCTAssertTrue(api.verifyPhone(phone: "+1\(phone)", token: session.token), "The disposable same-account fixture must use only the local Development OTP path.")
        }
        return (deviceID, session.token)
    }

    private func setHomeInUI(_ app: XCUIApplication) {
        let setHome = app.buttons["home-set-button"]
        let permissionStatus = app.staticTexts["location-permission-status"]
        if !setHome.exists && !permissionStatus.exists {
            let youTab = app.buttons["tab-you"]
            XCTAssertTrue(youTab.waitForExistence(timeout: 15))
            if !youTab.isSelected { youTab.tap() }
            let myLocation = app.buttons["my-location"]
            XCTAssertTrue(myLocation.waitForExistence(timeout: 10), app.debugDescription)
            myLocation.tap()
        }
        XCTAssertTrue(setHome.waitForExistence(timeout: 10), app.debugDescription)
        if !setHome.isHittable { app.swipeUp() }
        setHome.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permissionButtons = [app.alerts.buttons, springboard.alerts.buttons]
        let whileUsing = permissionButtons.map {
            $0.matching(NSPredicate(format: "label CONTAINS[c] %@", "While Using")).firstMatch
        }
        // Native location permission may be exposed by Springboard rather than
        // the target app. Observe both instead of timing out behind its alert.
        if waitUntil(timeout: 5, condition: { whileUsing.contains(where: \.exists) }),
           let action = whileUsing.first(where: \.exists) {
            action.tap()
        }
        let status = app.staticTexts["home-place-status"]
        XCTAssertTrue(waitUntil(timeout: 30) { status.exists && status.label.localizedCaseInsensitiveContains("set") }, app.debugDescription)
        allowBackgroundLocationIfPrompted(in: app)
        assertAlwaysLocationPermission(in: app)
    }

    private func assertAlwaysLocationPermission(in app: XCUIApplication) {
        let permission = app.staticTexts["location-permission-status"]
        XCTAssertTrue(waitUntil(timeout: 12) {
            permission.exists && permission.label.localizedCaseInsensitiveContains("always")
        }, "Home handoff requires the UI to show Always location permission.\n\(app.debugDescription)")
    }

    private func waitForProxyState(timeout: TimeInterval, condition: ([String: Any]) -> Bool) -> Bool {
        waitUntil(timeout: timeout) {
            guard let state = self.api.raceProxyState() else { return false }
            return condition(state)
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func requireAgeAssuranceFaultProxy() throws {
        guard api.raceProxyState()?["request_counts"] is [String: Int] else {
            throw XCTSkip("This age-assurance request-count scenario requires the loopback fault proxy on port 5089; the direct-API CI lane does not provide proxy controls.")
        }
    }

    private func assertAppTransactionUnavailable(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["app-transaction-title"].waitForExistence(timeout: 15), app.debugDescription, file: file, line: line)
        XCTAssertTrue(app.staticTexts["app-transaction-body"].exists, file: file, line: line)
        XCTAssertTrue(app.buttons["app-transaction-retry"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["tab-circle"].exists, "Account data must stay closed until AppTransaction registration succeeds.", file: file, line: line)
    }

    private func assertUnavailableAgeCheck(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["age-gate-title"].waitForExistence(timeout: 15), app.debugDescription, file: file, line: line)
        XCTAssertTrue(app.staticTexts["age-gate-body"].exists, file: file, line: line)
        XCTAssertTrue(app.buttons["age-gate-retry"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["tab-circle"].exists, "Account data must stay closed when age assurance is unavailable.", file: file, line: line)
    }

    private func assertNoAccountWork(_ state: [String: Any]?, file: StaticString = #filePath, line: UInt = #line) {
        guard let state else {
            XCTFail("The loopback proxy must provide request counters for this assertion.", file: file, line: line)
            return
        }
        guard let counts = state["request_counts"] as? [String: Int] else {
            XCTFail("The loopback proxy response is missing request counters.", file: file, line: line)
            return
        }
        for request in [
            "GET /api/v1/circle",
            "POST /api/v1/location",
            "POST /api/v1/push/devices",
            "PUT /api/v1/me/home",
            "POST /api/v1/me/home/presence",
            "GET /api/v1/storekit/account-token",
            "POST /api/v1/circle/entitlement"
        ] {
            XCTAssertEqual(counts[request] ?? 0, 0, "\(request) must remain suppressed while account access is blocked.", file: file, line: line)
        }
    }

    private func inboundPresentation(personID: String, token: String) -> String? {
        guard let inboundShare = api.member(personID: personID, token: token)?["inboundShare"] as? [String: Any] else {
            return nil
        }
        return inboundShare["presentation"] as? String
    }

    private func outboundPresentation(personID: String, token: String) -> String? {
        // CircleResponse serializes the viewer's outbound mode under `share`.
        guard let outboundShare = api.member(personID: personID, token: token)?["share"] as? [String: Any] else {
            return nil
        }
        return outboundShare["presentation"] as? String
    }

    private func yourHomeState(token: String) -> String? {
        guard let home = api.circle(token: token)?["yourHome"] as? [String: Any] else { return nil }
        return home["state"] as? String
    }

    private func visibleHomePresence(personID: String, token: String) -> String? {
        guard let member = api.member(personID: personID, token: token),
              let presence = member["homePresence"] as? [String: Any] else { return nil }
        return presence["state"] as? String
    }

    private func activeConnectionID(personID: String, token: String) -> String? {
        let response = api.memberResponse(personID: personID, token: token)
        guard (200..<300).contains(response.status),
              let connectionID = response.member?["connectionId"] as? String,
              !connectionID.isEmpty else { return nil }
        return connectionID
    }

    private func activeShareRevision(personID: String, token: String) -> Int64? {
        guard let share = api.member(personID: personID, token: token)?["share"] as? [String: Any],
              let revision = share["revision"] as? NSNumber else { return nil }
        return revision.int64Value
    }

    private func successfulCircleOmitsMember(personID: String, token: String) -> Bool {
        let response = api.request("GET", "/api/v1/circle", token: token)
        guard (200..<300).contains(response.status),
              let payload = response.json as? [String: Any],
              let members = payload["members"] as? [[String: Any]] else { return false }
        return !members.contains { ($0["person"] as? [String: Any])?["id"] as? String == personID }
    }

    private func assertReconnectedPair(
        ownToken: String,
        peerToken: String,
        ownID: String,
        peerID: String,
        originalConnectionID: String
    ) throws {
        let ownCircle = api.request("GET", "/api/v1/circle", token: ownToken)
        let peerCircle = api.request("GET", "/api/v1/circle", token: peerToken)
        XCTAssertTrue((200..<300).contains(ownCircle.status), "The reconnected account's circle must load successfully.")
        XCTAssertTrue((200..<300).contains(peerCircle.status), "The other account's circle must load successfully.")
        let ownPayload = try XCTUnwrap(ownCircle.json as? [String: Any])
        let peerPayload = try XCTUnwrap(peerCircle.json as? [String: Any])
        XCTAssertEqual((ownPayload["you"] as? [String: Any])?["id"] as? String, ownID)
        XCTAssertEqual((peerPayload["you"] as? [String: Any])?["id"] as? String, peerID)
        let ownMembers = try XCTUnwrap(ownPayload["members"] as? [[String: Any]])
        let peerMembers = try XCTUnwrap(peerPayload["members"] as? [[String: Any]])
        let memberForPeer = try XCTUnwrap(ownMembers.first { ($0["person"] as? [String: Any])?["id"] as? String == peerID })
        let memberForOwn = try XCTUnwrap(peerMembers.first { ($0["person"] as? [String: Any])?["id"] as? String == ownID })
        let newConnectionID = try XCTUnwrap(memberForPeer["connectionId"] as? String)
        XCTAssertFalse(newConnectionID.isEmpty)
        XCTAssertNotEqual(newConnectionID, originalConnectionID)
        XCTAssertEqual(memberForOwn["connectionId"] as? String, newConnectionID)
        assertReconnectedOffState(memberForPeer)
        assertReconnectedOffState(memberForOwn)
        for token in [ownToken, peerToken] {
            let requests = try XCTUnwrap(api.connectionRequests(token: token))
            XCTAssertTrue((requests["incoming"] as? [[String: Any]])?.isEmpty == true)
            XCTAssertTrue((requests["sent"] as? [[String: Any]])?.isEmpty == true)
        }
    }

    private func assertReconnectedOffState(_ member: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((member["share"] as? [String: Any])?["presentation"] as? String, "off", file: file, line: line)
        XCTAssertEqual((member["inboundShare"] as? [String: Any])?["presentation"] as? String, "off", file: file, line: line)
        XCTAssertEqual(member["outboundPresenceGranted"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(member["inboundPresenceGranted"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(member["inboundLive"] as? Bool, false, file: file, line: line)
        XCTAssertTrue(member["live"] == nil || member["live"] is NSNull, file: file, line: line)
        XCTAssertTrue(member["homePresence"] == nil || member["homePresence"] is NSNull, file: file, line: line)
    }

    private func waitUntil(timeout: TimeInterval, pollInterval: TimeInterval = 0.25, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return condition()
    }

    private func allowBackgroundLocationIfPrompted(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let locationSheetWasOpen = app.staticTexts["location-permission-status"].exists
        let primaryActions = [
            app.buttons["always-explainer-allow"],
            app.buttons["home-permission-action"],
            app.buttons["location-permission-action"]
        ]
        guard waitUntil(timeout: 3, condition: {
            primaryActions.contains { $0.exists && $0.isHittable }
        }), let primaryAction = primaryActions.first(where: { $0.exists && $0.isHittable }) else { return }

        // Use only the controls owned by the location flow. You also contains a
        // separate Notifications “Open iOS Settings” button.
        if primaryAction.label.localizedCaseInsensitiveContains("Settings") {
            primaryAction.tap()
            selectAlwaysLocationInSystemSettings(app: app, preserveLocationSheet: locationSheetWasOpen)
            return
        }
        primaryAction.tap()

        let appAlways = app.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Always")
        ).firstMatch
        let systemAlways = springboard.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Always")
        ).firstMatch
        let positiveWhileUsingPredicate = NSPredicate(
            format: "label CONTAINS[c] %@ AND NOT label BEGINSWITH[c] %@",
            "While Using", "Keep"
        )
        let appWhileUsing = app.alerts.buttons.matching(positiveWhileUsingPredicate).firstMatch
        let systemWhileUsing = springboard.alerts.buttons.matching(positiveWhileUsingPredicate).firstMatch
        // Some iOS authorization sheets offer an existing Always upgrade next
        // to "Keep Only While Using". Prefer the requested stronger choice
        // before considering a foreground-only step.
        let nativeChoiceAppeared = waitUntil(timeout: 8) {
            appAlways.exists || systemAlways.exists || appWhileUsing.exists || systemWhileUsing.exists
        }
        if !nativeChoiceAppeared {
            // After a person previously chose Keep Only While Using, iOS may
            // not present another permission sheet. The same identified
            // location control changes to the Settings recovery action.
            let settingsAction = waitForLocationSettingsAction(in: app, timeout: 5)
            XCTAssertNotNil(settingsAction,
                             "Without a native authorization choice, Trust should offer its location-scoped Settings recovery action.\n\(app.debugDescription)\n\(springboard.debugDescription)")
            settingsAction?.tap()
            selectAlwaysLocationInSystemSettings(app: app, preserveLocationSheet: locationSheetWasOpen)
            return
        }
        if appAlways.exists || systemAlways.exists {
            (appAlways.exists ? appAlways : systemAlways).tap()
            return
        }

        XCTAssertTrue(waitUntil(timeout: 8) { appWhileUsing.exists || systemWhileUsing.exists },
                      "The foreground location prompt should offer an affirmative While Using choice.\n\(app.debugDescription)\n\(springboard.debugDescription)")
        (appWhileUsing.exists ? appWhileUsing : systemWhileUsing).tap()
        XCTAssertTrue(waitUntil(timeout: 12) { appAlways.exists || systemAlways.exists }, "Accepting foreground access should lead to the requested Always location choice.\n\(app.debugDescription)\n\(springboard.debugDescription)")
        (appAlways.exists ? appAlways : systemAlways).tap()
    }

    private func waitForLocationSettingsAction(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let locationActions = [
            app.buttons["always-explainer-allow"],
            app.buttons["home-permission-action"],
            app.buttons["location-permission-action"]
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let action = locationActions.first(where: {
                $0.exists && $0.isHittable && $0.label.localizedCaseInsensitiveContains("Settings")
            }) {
                return action
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return locationActions.first(where: {
            $0.exists && $0.isHittable && $0.label.localizedCaseInsensitiveContains("Settings")
        })
    }

    private func selectAlwaysLocationInSystemSettings(app: XCUIApplication, preserveLocationSheet: Bool) {
        let tabIdentifiers = ["tab-circle", "tab-sharing", "tab-log", "tab-you"]
        let originalTabIdentifier = tabIdentifiers.first { identifier in
            let tab = app.buttons[identifier]
            return tab.exists && tab.isSelected
        }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(waitUntil(timeout: 12) { settings.state == .runningForeground },
                      "Open Settings should present the native Trust settings page.\n\(settings.debugDescription)")

        let locationRow = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Location")
        ).firstMatch
        if waitUntil(timeout: 4) { locationRow.exists && locationRow.isHittable } {
            locationRow.tap()
        } else {
            openTrustLocationServicesPermission(in: settings)
        }

        let alwaysOption = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Always")
        ).firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { alwaysOption.exists && alwaysOption.isHittable },
                      "Native Location settings should offer the Always authorization choice.\n\(settings.debugDescription)")
        alwaysOption.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmAlways = springboard.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Always")
        ).firstMatch
        if waitUntil(timeout: 3) { confirmAlways.exists && confirmAlways.isHittable } {
            confirmAlways.tap()
        }

        app.activate()
        let later = app.buttons["always-explainer-later"]
        if later.waitForExistence(timeout: 2) { later.tap() }

        let youTab = app.buttons["tab-you"]
        if youTab.exists && !youTab.isSelected { youTab.tap() }
        let myLocation = app.buttons["my-location"]
        if !app.staticTexts["location-permission-status"].exists, myLocation.waitForExistence(timeout: 8) {
            myLocation.tap()
        }
        let permission = app.staticTexts["location-permission-status"]
        XCTAssertTrue(waitUntil(timeout: 15) {
            permission.exists && permission.label.localizedCaseInsensitiveContains("always")
        }, "Returning from iOS Settings after choosing Always should update Trust's visible permission status.\n\(app.debugDescription)")

        let done = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Done")).firstMatch
        if done.exists && !preserveLocationSheet { done.tap() }
        if let originalTabIdentifier, originalTabIdentifier != "tab-you" {
            let originalTab = app.buttons[originalTabIdentifier]
            if originalTab.exists && !originalTab.isSelected { originalTab.tap() }
        }
    }

    private func openTrustLocationServicesPermission(in settings: XCUIApplication) {
        // UIApplication.openSettingsURLString can resume an old Apps-search
        // stack on this simulator runtime. Start at the native Settings root,
        // then use the public Privacy & Security → Location Services route.
        settings.terminate()
        settings.activate()
        XCTAssertTrue(waitUntil(timeout: 10) { settings.state == .runningForeground },
                      "Native Settings should return to its root before navigating Location Services.\n\(settings.debugDescription)")

        let privacy = settings.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Privacy & Security")
        ).firstMatch
        for _ in 0..<6 where !privacy.exists || !privacy.isHittable {
            settings.swipeUp()
        }
        XCTAssertTrue(waitForStableSettingsRow(privacy, timeout: 10),
                      "Settings root should expose Privacy & Security.\n\(settings.debugDescription)")
        guard privacy.exists && privacy.isHittable else { return }
        privacy.tap()

        let locationServices = settings.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Location Services")
        ).firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { locationServices.exists && locationServices.isHittable },
                      "Privacy & Security should expose Location Services.\n\(settings.debugDescription)")
        guard locationServices.exists && locationServices.isHittable else { return }
        locationServices.tap()

        let trustByIdentifier = settings.buttons["com.collapsetechnologies.trust"]
        let trustByName = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Trust")
        ).firstMatch
        for _ in 0..<8 where
            (!trustByIdentifier.exists || !trustByIdentifier.isHittable)
                && (!trustByName.exists || !trustByName.isHittable) {
            settings.swipeUp()
        }
        let trustRow = trustByIdentifier.exists ? trustByIdentifier : trustByName
        XCTAssertTrue(waitForStableSettingsRow(trustRow, timeout: 10),
                      "Location Services should contain the Trust app row.\n\(settings.debugDescription)")
        guard trustRow.exists && trustRow.isHittable else { return }
        trustRow.tap()
        let alwaysOption = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Always")
        ).firstMatch
        let trustPageDidOpen = waitUntil(timeout: 8) {
            !trustByIdentifier.exists && !trustByName.exists && alwaysOption.exists && alwaysOption.isHittable
        }
        if !trustPageDidOpen && trustRow.exists && trustRow.isHittable {
            // If iOS left the same result row in place, allow one idempotent
            // center tap after checking its geometry again.
            trustRow.tap()
        }
        XCTAssertTrue(waitUntil(timeout: 10) {
            !trustByIdentifier.exists && !trustByName.exists && alwaysOption.exists && alwaysOption.isHittable
        }, "Selecting Trust in Location Services should open its app-specific authorization choices.\n\(settings.debugDescription)")
    }

    private func waitForStableSettingsRow(_ row: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var priorFrame: CGRect?
        var stableSamples = 0
        while Date() < deadline {
            if row.exists && row.isHittable {
                let frame = row.frame
                if let priorFrame,
                   abs(priorFrame.minX - frame.minX) < 1,
                   abs(priorFrame.minY - frame.minY) < 1,
                   abs(priorFrame.width - frame.width) < 1,
                   abs(priorFrame.height - frame.height) < 1 {
                    stableSamples += 1
                    if stableSamples >= 2 { return true }
                } else {
                    stableSamples = 0
                }
                priorFrame = frame
            } else {
                priorFrame = nil
                stableSamples = 0
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return stableSamples >= 2 && row.exists && row.isHittable
    }

    private func scrollUpUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
    }

    private func isSwitchOn(_ element: XCUIElement) -> Bool {
        let value = String(describing: element.value ?? "").lowercased()
        return value == "1" || value == "on" || value == "true"
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct DisposableSession {
    let token: String
    let personID: String
}

private struct ConnectedTestFixture {
    let main: DisposableSession
    let peer: DisposableSession
    let mainName: String
    let peerName: String
    let mainDeviceID: String
    let mainHandle: String
}

/// XCTest runner helper that has no configurable host: every operation stays on loopback.
private final class LocalTrustAPI {
    static var baseURL: String {
        ProcessInfo.processInfo.environment["TRUST_UI_TEST_BASE_URL"]
            ?? UserDefaults.standard.string(forKey: "TRUST_UI_TEST_BASE_URL")
            ?? ""
    }
    private var base: URL? { URL(string: Self.baseURL) }
    var hasSafeConfiguration: Bool {
        guard let base,
              base.scheme?.lowercased() == "http",
              base.port == 5089,
              base.user == nil,
              base.password == nil,
              base.query == nil,
              base.fragment == nil,
              base.path.isEmpty || base.path == "/" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(base.host?.lowercased() ?? "")
    }

    func healthIsAvailable() -> Bool {
        let result = request("GET", "/health/live")
        return (200..<300).contains(result.status)
    }

    func raceProxyState() -> [String: Any]? {
        request("GET", "/__test/state").json as? [String: Any]
    }

    func armCircleRace() -> Bool {
        (200..<300).contains(request("POST", "/__test/arm", body: [:]).status)
    }

    func armHistoryRace() -> Bool {
        (200..<300).contains(request("POST", "/__test/arm-history", body: [:]).status)
    }

    func armLookRace() -> Bool {
        (200..<300).contains(request("POST", "/__test/arm-look", body: [:]).status)
    }

    func armShareResponse(failureAfterRelease: Bool) -> Bool {
        let path = failureAfterRelease ? "/__test/arm-share-failure" : "/__test/arm-share"
        return (200..<300).contains(request("POST", path, body: [:]).status)
    }

    func armStopAllFailure() -> Bool {
        (200..<300).contains(request("POST", "/__test/arm-stop-all", body: [:]).status)
    }

    func armAppTransactionFixture(retry: Bool) -> Bool {
        let path = retry ? "/__test/arm-app-transaction-retry" : "/__test/arm-app-transaction"
        return (200..<300).contains(request("POST", path, body: [:]).status)
    }

    func releaseHeldCircle() -> Bool {
        (200..<300).contains(request("POST", "/__test/release", body: [:]).status)
    }

    func releaseHeldResponse() -> Bool {
        (200..<300).contains(request("POST", "/__test/release", body: [:]).status)
    }

    func resetRaceProxy() {
        _ = request("POST", "/__test/reset", body: [:])
    }

    func developmentOTPWithoutSMSIsEnabled() -> Bool {
        let result = request("GET", "/api/v1/local-test-capabilities")
        return (200..<300).contains(result.status)
            && (result.json as? [String: Any])?["developmentOtpWithoutSms"] as? Bool == true
    }

    static func reservedPhonePool() -> [String] {
        let areaCodes = ["202", "212", "213", "305", "310", "312", "415", "617", "718", "917"]
        return areaCodes.flatMap { areaCode in
            (0..<100).compactMap { slot -> String? in
                let number = areaCode + "55501" + String(format: "%02d", slot)
                return number == "2025550199" ? nil : number
            }
        }
    }

    func developmentSession(name: String, deviceID: String, provider: String = "development") -> DisposableSession? {
        let result = request(
            "POST",
            "/api/v1/session/development",
            body: ["displayName": name, "deviceId": deviceID, "provider": provider]
        )
        guard result.status == 200,
              let json = result.json as? [String: Any],
              let token = json["token"] as? String,
              let you = json["you"] as? [String: Any],
              let personID = you["id"] as? String else { return nil }
        return DisposableSession(token: token, personID: personID)
    }

    func putHandle(_ handle: String, token: String) -> Int {
        request("PUT", "/api/v1/me/handle", token: token, body: ["handle": handle]).status
    }

    func putAvatarPreset(_ presetID: String, token: String) -> Int {
        request("PUT", "/api/v1/me/avatar/preset", token: token, body: ["presetId": presetID]).status
    }

    func setPhoneDiscovery(_ enabled: Bool, token: String) -> Int {
        request("PUT", "/api/v1/me/discovery", token: token, body: ["enabled": enabled, "consentVersion": 1]).status
    }

    func setPresenceGrant(personID: String, token: String, enabled: Bool) -> Int {
        guard let member = member(personID: personID, token: token),
              let connectionID = member["connectionId"] as? String else { return 0 }
        let revision = member["outboundPresenceRevision"] as? Int64 ?? 0
        return request(
            "PUT",
            "/api/v1/people/\(personID)/presence-grant",
            token: token,
            body: ["connectionId": connectionID, "revision": revision, "enabled": enabled]
        ).status
    }

    func postHomePresence(state: String, token: String) -> Int {
        request("POST", "/api/v1/me/home/presence", token: token, body: ["state": state]).status
    }

    func verifyPhone(phone: String, token: String) -> Bool {
        let sent = request("POST", "/api/v1/me/phone/send", token: token, body: ["phone": phone])
        guard (200..<300).contains(sent.status),
              let payload = sent.json as? [String: Any],
              // A development code is returned only on the no-SMS path.
              let code = payload["developmentCode"] as? String,
              code.count == 6,
              code.allSatisfy(\.isNumber) else { return false }
        return (200..<300).contains(request("POST", "/api/v1/me/phone/verify", token: token, body: ["phone": phone, "code": code]).status)
    }

    func connectionRequests(token: String) -> [String: Any]? {
        request("GET", "/api/v1/connection-requests", token: token).json as? [String: Any]
    }

    func createConnectionRequest(recipientID: String, token: String) -> Int {
        request("POST", "/api/v1/connection-requests", token: token, body: ["recipientId": recipientID]).status
    }

    func lookupPerson(handle: String, token: String) -> String? {
        guard let payload = lookupPersonResponse(handle: handle, token: token).json as? [String: Any] else { return nil }
        return payload["accountId"] as? String
    }

    func lookupPersonResponse(handle: String, token: String) -> (status: Int, json: Any?) {
        request("POST", "/api/v1/people/lookup", token: token, body: ["handle": handle])
    }

    func circle(token: String) -> [String: Any]? {
        request("GET", "/api/v1/circle", token: token).json as? [String: Any]
    }

    func hasLookEvent(subjectID: String, token: String) -> Bool {
        latestLookEvent(subjectID: subjectID, token: token) != nil
    }

    func latestLookEvent(subjectID: String, token: String) -> [String: Any]? {
        guard let events = circle(token: token)?["lookLog"] as? [[String: Any]] else { return nil }
        return events.last { ($0["subjectId"] as? String)?.lowercased() == subjectID.lowercased() }
    }

    func yourHomePlace(token: String) -> (status: Int, label: String?, placeID: String?) {
        let response = request("GET", "/api/v1/circle", token: token)
        guard (200..<300).contains(response.status),
              let payload = response.json as? [String: Any],
              let yourHome = payload["yourHome"] as? [String: Any],
              let place = yourHome["place"] as? [String: Any] else {
            return (response.status, nil, nil)
        }
        return (response.status, place["label"] as? String, place["placeId"] as? String)
    }

    func member(personID: String, token: String) -> [String: Any]? {
        guard let members = circle(token: token)?["members"] as? [[String: Any]] else { return nil }
        return members.first { ($0["person"] as? [String: Any])?["id"] as? String == personID }
    }

    func memberResponse(personID: String, token: String) -> (status: Int, member: [String: Any]?) {
        let response = request("GET", "/api/v1/circle", token: token)
        guard (200..<300).contains(response.status),
              let payload = response.json as? [String: Any],
              let members = payload["members"] as? [[String: Any]] else {
            return (response.status, nil)
        }
        let member = members.first { ($0["person"] as? [String: Any])?["id"] as? String == personID }
        return (response.status, member)
    }

    func deleteAccount(token: String) {
        let result = request("DELETE", "/api/v1/account", token: token)
        // 404 is acceptable when an earlier cleanup or server cascade already removed it.
        assert(result.status == 204 || result.status == 404, "Failed to delete disposable local API test account.")
    }

    func placePrivacyHold(token: String) -> Int {
        request("POST", "/api/v1/age-assurance/privacy-hold", token: token).status
    }

    func request(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) -> (status: Int, json: Any?) {
        guard hasSafeConfiguration, let base, let url = URL(string: path, relativeTo: base) else { return (0, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseStatus = 0
        var responseJSON: Any?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            responseStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, !data.isEmpty { responseJSON = try? JSONSerialization.jsonObject(with: data) }
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 12) == .success else { return (0, nil) }
        return (responseStatus, responseJSON)
    }
}
