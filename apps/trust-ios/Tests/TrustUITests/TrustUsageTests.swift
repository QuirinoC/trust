import XCTest

/// Safe, fixture-backed app use. These flows stay inside the DEBUG demo and never send SMS,
/// change a live account, or open StoreKit purchase confirmation.
final class TrustUsageTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLookRecordsOneSnapshotAndSealedPersonHasNoHistory() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))

        let maya = app.buttons["person-row-maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 10))
        maya.tap()
        XCTAssertTrue(app.staticTexts["person-sharing-directions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["person-history"].exists, "A Sealed person must not load or show history.")
        XCTAssertTrue(app.buttons["person-profile-peek"].exists, "A Sealed person should offer Look.")

        app.buttons["person-profile-peek"].tap()
        XCTAssertTrue(app.buttons["confirm-look-notify"].waitForExistence(timeout: 5))
        app.buttons["confirm-look-notify"].tap()
        XCTAssertTrue(app.staticTexts["person-sharing-directions"].waitForExistence(timeout: 8), "Look should return to its single snapshot view.")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "One snapshot")).firstMatch.exists)

        app.buttons["circle-back"].tap()
        XCTAssertTrue(app.buttons["person-row-maya"].waitForExistence(timeout: 5), "Look should return to the People list.")
    }

    func testPauseResumeOffAndRemoveAreSeparateActions() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()

        let pause = app.buttons["pause-sharing-maya"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        let oneHour = app.buttons["pause-duration-3600"]
        XCTAssertTrue(oneHour.waitForExistence(timeout: 5))
        oneHour.tap()
        XCTAssertTrue(app.staticTexts["sharing-summary-maya"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sharing-summary-maya"].label.contains("Paused"))

        app.buttons["sharing-mode-sealed-maya"].tap()
        XCTAssertTrue(app.staticTexts["sharing-summary-maya"].label.contains("Sealed"))
        app.buttons["sharing-mode-off-maya"].tap()
        tapConfirmationAction("stop-sharing-confirm", in: app)
        XCTAssertTrue(app.staticTexts["sharing-summary-maya"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["sharing-summary-maya"].label.contains("Not sharing"))

        app.buttons["sharing-actions-maya"].tap()
        let remove = app.buttons["remove-person-action-maya"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        tapConfirmationAction("remove-person-confirm", in: app)
        XCTAssertFalse(app.staticTexts["sharing-summary-maya"].waitForExistence(timeout: 2))
    }

    func testInviteActivityYouAndDarkAppearance() {
        let app = launchDemo(dark: true)
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(app.staticTexts["sharing-intro"].waitForExistence(timeout: 5))

        app.buttons["add-someone-button"].tap()
        let phone = app.textFields["add-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        phone.tap()
        phone.typeText("4155550100")
        app.buttons["add-phone-button"].tap()
        XCTAssertTrue(app.staticTexts["invite-notice"].waitForExistence(timeout: 5), "The demo reports its invite limitation without sending a real text.")
        XCTAssertTrue(app.textFields["invite-code"].exists, "Joining an invite remains a separate explicit action.")
        XCTAssertTrue(app.buttons["join-invite-button"].exists)

        app.buttons["tab-log"].tap()
        let event = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "activity-event-")
        ).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5), "Activity should show dated event receipts.")

        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.buttons["mode-option-home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["location-permission-status"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].exists)
    }

    func testPaywallScreenshotRouteIsReachable() {
        let app = launchDemo(route: "paywall")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Plus")).firstMatch.waitForExistence(timeout: 10))
    }

    private func launchDemo(dark: Bool = false, route: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        if let route { app.launchEnvironment["TRUST_SCREENSHOT"] = route }
        if dark { app.launchArguments += ["-uiUserInterfaceStyle", "Dark"] }
        app.launch()
        return app
    }

    private func tapConfirmationAction(_ identifier: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        // SwiftUI exposes a confirmation-dialog action through both its legacy and modern
        // automation attributes; the build log confirms these are two aliases of one control.
        matches.element(boundBy: 0).tap()
    }
}
