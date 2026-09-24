import XCTest

/// Actual app usage. One Debug launch of the offline demo, the same fixture as “See the app”.
/// `TRUST_UI_TEST=1` skips the system location and notification sheets so the walk can finish.
final class TrustUsageTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoWalksPeopleLookSharingLogAndYou() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launch()

        let people = app.buttons["tab-circle"]
        XCTAssertTrue(people.waitForExistence(timeout: 20), "People tab did not appear")

        let mayaLook = app.buttons["Look at Maya. They will be notified."]
        XCTAssertTrue(mayaLook.waitForExistence(timeout: 10))
        mayaLook.tap()

        let snapshot = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "One snapshot of their current place.")
        ).firstMatch
        XCTAssertTrue(snapshot.waitForExistence(timeout: 5), "Look confirm did not show the snapshot line. \(app.debugDescription)")
        app.buttons["Close"].tap()

        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(app.staticTexts["Pause"].waitForExistence(timeout: 5))

        app.buttons["tab-log"].tap()
        let looked = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "looked at you")
        ).firstMatch
        XCTAssertTrue(looked.waitForExistence(timeout: 5), "Log did not show a look. \(app.debugDescription)")

        app.buttons["tab-you"].tap()
        let plus = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Always, 20 people, live pins")
        ).firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "You did not show Plus. \(app.debugDescription)")
    }
}
