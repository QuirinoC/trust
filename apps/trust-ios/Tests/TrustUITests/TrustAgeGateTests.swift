import XCTest

final class TrustAgeGateTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEligibleBirthDateContinuesToSignIn() {
        let app = launchAgeGate(resetState: true)
        enterBirthDate(year: Calendar.current.component(.year, from: Date()) - 13, in: app)

        element("age-gate-continue", in: app).tap()

        XCTAssertTrue(
            element("local-api-sign-in", in: app).waitForExistence(timeout: 30),
            "A valid eligible birth date should pass the gate before the sign-in screen appears."
        )
        XCTAssertFalse(app.textFields["age-birth-month"].exists)
    }

    func testUnder13AppleRangeExplainsRestrictionWithoutClaimingConsentFlow() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_AGE_RANGE_BLOCKED"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_AGE_RANGE_REQUIRED"] = "1"
        app.launch()

        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("age-gate-body", in: app).exists)
        XCTAssertTrue(element("age-gate-body", in: app).label.contains("age range"))
        XCTAssertFalse(element("age-gate-body", in: app).label.localizedCaseInsensitiveContains("consent"))
        XCTAssertFalse(app.textFields["age-birth-month"].exists)
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)
        app.swipeUp()
        XCTAssertTrue(element("age-gate-support", in: app).exists)
        XCTAssertTrue(element("age-gate-support-action", in: app).exists)
        if #available(iOS 26, *) {
            XCTAssertTrue(element("age-gate-apple-range", in: app).exists)
        }

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_AGE_RANGE_BLOCKED")
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_STATE")
        app.launchEnvironment["TRUST_AGE_TEST_RESET_PREFERENCES_ONLY"] = "1"
        app.launch()

        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(
            element("age-gate-body", in: app).label.contains("age range"),
            "An Apple age-range block must keep its Apple-specific path after app preferences are cleared."
        )
        XCTAssertFalse(app.textFields["age-birth-month"].exists)
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_PREFERENCES_ONLY")
        app.launchEnvironment["TRUST_AGE_TEST_APPLE_ACCOUNT_CHANGED"] = "1"
        app.launch()

        XCTAssertTrue(
            app.textFields["age-birth-month"].waitForExistence(timeout: 15),
            "A different Apple Account on a shared device must not inherit the previous person's device-wide age block."
        )
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)
    }

    func testConsentRevocationShowsBlockedStateWithSupportAndNoAgeRetry() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_CONSENT_REVOKED"] = "1"
        app.launch()

        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("age-gate-title", in: app).label.contains("disabled"))
        XCTAssertTrue(element("age-gate-body", in: app).label.contains("withdrew consent"))
        XCTAssertFalse(element("age-gate-retry", in: app).exists)
        XCTAssertFalse(element("age-gate-apple-range", in: app).exists)
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)
        XCTAssertFalse(app.textFields["age-birth-month"].exists)
        app.swipeUp()
        XCTAssertTrue(element("age-gate-support", in: app).exists)
    }

    func testPrivacyHoldOffersConfirmedSelfServeAccountDeletion() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_PRIVACY_HELD"] = "1"
        app.launch()

        let delete = element("age-privacy-hold-delete-account", in: app)
        XCTAssertTrue(delete.waitForExistence(timeout: 15))
        XCTAssertTrue(element("age-privacy-hold-support-action", in: app).exists)

        delete.tap()
        let cancel = app.descendants(matching: .any)
            .matching(identifier: "age-privacy-hold-delete-cancel")
            .firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(delete.exists, "Cancelling confirmation must leave the held account and its data intact.")
    }

    func testUnderMinimumBirthDateBlocksButCanUseAppleRangeToCorrectEntry() {
        let app = launchAgeGate(resetState: true, ageRangeRequired: true)
        enterBirthDate(year: Calendar.current.component(.year, from: Date()) - 12, in: app)

        element("age-gate-continue", in: app).tap()
        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["age-birth-month"].exists)
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)
        XCTAssertFalse(element("age-gate-retry", in: app).exists, "A locally entered under-13 result cannot be cleared by immediately re-entering a later date.")
        if #available(iOS 26, *) {
            XCTAssertTrue(element("age-gate-apple-range", in: app).exists, "A supported Apple age range provides a separate correction path without revealing a date-entry form.")
        }
        XCTAssertTrue(element("age-gate-support", in: app).exists, "A blocked person must have a visible support route if the local age result was entered incorrectly.")

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_STATE")
        app.launch()

        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["age-birth-month"].exists, "A saved under-13 decision must not show the age form again after relaunch.")
        XCTAssertFalse(element("local-api-sign-in", in: app).exists, "A saved under-13 decision must keep sign-in inaccessible.")
        XCTAssertFalse(element("age-gate-retry", in: app).exists, "The local under-13 result must not be cleared by re-entering another date after relaunch.")
        if #available(iOS 26, *) {
            XCTAssertTrue(element("age-gate-apple-range", in: app).exists, "The Apple correction path remains available after relaunch.")
        }
        XCTAssertTrue(element("age-gate-support", in: app).exists)

        app.terminate()
        app.launchEnvironment["TRUST_AGE_TEST_RESET_PREFERENCES_ONLY"] = "1"
        app.launch()

        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(app.textFields["age-birth-month"].exists, "Clearing app preferences to model a reinstall must not clear the device-only Keychain age block.")
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)
        XCTAssertTrue(element("age-gate-support", in: app).exists)
    }

    func testSavedUnderageBlockDoesNotPromptForAgeRangeOutsideRequiredRegion() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_AGE_RANGE_BLOCKED"] = "1"
        app.launch()

        XCTAssertTrue(element("age-gate-title", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("age-gate-body", in: app).label.contains("age range"))
        XCTAssertFalse(element("age-gate-apple-range", in: app).exists)
        XCTAssertFalse(element("local-api-sign-in", in: app).exists)
        app.swipeUp()
        XCTAssertTrue(element("age-gate-support", in: app).exists)
    }

    private func launchAgeGate(resetState: Bool, ageRangeRequired: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_AUTH"] = "1"
        if resetState {
            app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        }
        if ageRangeRequired {
            app.launchEnvironment["TRUST_AGE_TEST_AGE_RANGE_REQUIRED"] = "1"
        }
        app.launch()
        XCTAssertTrue(app.textFields["age-birth-month"].waitForExistence(timeout: 15))
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func enterBirthDate(year: Int, in app: XCUIApplication) {
        let month = app.textFields["age-birth-month"]
        let day = app.textFields["age-birth-day"]
        let birthYear = app.textFields["age-birth-year"]
        month.tap()
        month.typeText("01")
        day.tap()
        day.typeText("01")
        birthYear.tap()
        birthYear.typeText(String(year))
        XCTAssertTrue(element("age-gate-continue", in: app).isEnabled)
    }
}
