import XCTest

final class TrustSignInFlowTests: XCTestCase {
    func testFreshLaunchShowsSignInWithoutAgeOrAppVerificationGate() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchArguments += ["-trust.appLanguage", "en"]
        app.launch()

        let signIn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Sign in with Apple")
        ).firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        let enabledExpectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: signIn)
        XCTAssertEqual(XCTWaiter.wait(for: [enabledExpectation], timeout: 10), .completed,
                       "Fresh sign-in must become available after session restoration, without waiting for the optional product catalog.")
        XCTAssertFalse(app.textFields["age-birth-month"].exists)
        XCTAssertFalse(app.staticTexts["age-gate-title"].exists)
        XCTAssertFalse(app.staticTexts["app-transaction-title"].exists)
    }
}
