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

        let openMap = app.buttons["view-open-map"]
        XCTAssertTrue(openMap.waitForExistence(timeout: 5))
        openMap.tap()
        let mapCanvas = app.descendants(matching: .any)["map-screen-canvas"]
        XCTAssertTrue(mapCanvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(mapCanvas.frame.width, 200, "The Map route should keep a useful map canvas inside the wide People detail pane.")

        app.buttons["map-back-to-people"].tap()
        XCTAssertTrue(app.buttons["person-row-maya"].waitForExistence(timeout: 5), "Look should return to the People list.")
    }

    func testPauseResumeOffAndRemoveAreSeparateActions() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()

        app.buttons["sharing-actions-maya"].tap()
        let pause = app.buttons["pause-sharing-maya"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        let oneHour = app.buttons["pause-duration-3600"]
        XCTAssertTrue(oneHour.waitForExistence(timeout: 5))
        oneHour.tap()
        let pauseSheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: oneHour
        )
        XCTAssertEqual(XCTWaiter.wait(for: [pauseSheetDismissed], timeout: 5), .completed)
        let sharingSummary = app.staticTexts["sharing-summary-maya"]
        XCTAssertTrue(sharingSummary.waitForExistence(timeout: 5))
        XCTAssertTrue(sharingSummary.label.contains("Paused"))

        app.buttons["sharing-mode-sealed-maya"].tap()
        let later = app.buttons["always-explainer-later"]
        if later.waitForExistence(timeout: 5) {
            later.tap()
            let explainerDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: later
            )
            XCTAssertEqual(XCTWaiter.wait(for: [explainerDismissed], timeout: 5), .completed)
        }
        XCTAssertTrue(app.buttons["sharing-mode-sealed-maya"].isSelected)
        let off = app.buttons["sharing-mode-off-maya"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        let offBecameHittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: off
        )
        let hittabilityResult = XCTWaiter.wait(for: [offBecameHittable], timeout: 5)
        if hittabilityResult != .completed {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Off mode not hittable"
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Off mode accessibility hierarchy"
            add(hierarchy)
            XCTFail("Off should become tappable after dismissing the Always explainer.")
        }
        off.tap()
        XCTAssertTrue(app.buttons["stop-sharing-confirm"].waitForExistence(timeout: 5))
        tapConfirmationAction("stop-sharing-confirm", in: app)
        let offSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"),
            object: app.buttons["sharing-mode-off-maya"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [offSelected], timeout: 5), .completed)

        app.buttons["sharing-actions-maya"].tap()
        let remove = app.buttons["remove-person-action-maya"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        tapConfirmationAction("remove-person-confirm", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["sharing-mode-group-maya"].waitForExistence(timeout: 2))
    }

    func testInviteActivityYouAndDarkAppearance() {
        let app = launchDemo(dark: true)
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(app.staticTexts["sharing-intro"].waitForExistence(timeout: 5))
        let homeStatus = app.buttons["home-status-control"]
        XCTAssertTrue(homeStatus.exists, "Presence should be a secondary setting, not a segmented row beside per-person sharing controls.")
        homeStatus.tap()
        let setHidden = app.buttons["set-home-status-hidden"]
        XCTAssertTrue(setHidden.waitForExistence(timeout: 5))
        app.buttons["set-home-status-home"].firstMatch.tap()

        app.buttons["add-someone-button"].tap()
        let handle = app.textFields["connection-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "handle in their You tab")).firstMatch.exists)
        handle.typeText("jordan")
        app.buttons["lookup-connection-handle"].tap()
        XCTAssertTrue(app.staticTexts["connection-lookup-notice"].waitForExistence(timeout: 5), "The demo should not fabricate handle lookup results.")
        XCTAssertFalse(app.textFields["invite-code"].exists)
        XCTAssertFalse(app.textFields["add-phone"].exists)
        app.buttons["cancel-add-person"].tap()

        app.buttons["tab-log"].tap()
        let event = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "activity-event-")
        ).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 5), "Activity should show dated event receipts.")

        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.buttons["my-location"].waitForExistence(timeout: 5))
        app.buttons["copy-own-handle"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Handle copied")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["my-location"].tap()
        XCTAssertTrue(app.staticTexts["location-permission-status"].exists)
        app.buttons["Done"].tap()
        app.buttons["edit-profile-picture"].tap()
        XCTAssertTrue(app.buttons["avatar-photo-options"].waitForExistence(timeout: 5))
        app.buttons["Fox icon"].tap()
        XCTAssertTrue(app.buttons["avatar-save"].isEnabled)
        app.buttons["avatar-save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["support-link"].waitForExistence(timeout: 5))
    }

    func testAppearancePreferencePersistsAcrossRelaunch() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()

        for option in ["System", "Light", "Dark"] {
            let picker = app.descendants(matching: .any)["appearance-preference"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "The appearance picker should be available in You.")
            picker.tap()
            let choice = app.buttons[option]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "The picker should offer the \(option) appearance.")
            choice.tap()
            let selectionApplied = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", option),
                object: picker)
            XCTAssertEqual(
                XCTWaiter.wait(for: [selectionApplied], timeout: 5),
                .completed,
                "The picker should reflect the selected appearance.")

            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
            app.buttons["tab-you"].tap()
            let relaunchedPicker = app.descendants(matching: .any)["appearance-preference"]
            XCTAssertTrue(relaunchedPicker.waitForExistence(timeout: 5))
            let preferenceRestored = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", option),
                object: relaunchedPicker)
            XCTAssertEqual(
                XCTWaiter.wait(for: [preferenceRestored], timeout: 5),
                .completed,
                "\(option) should persist after restarting the app.")
        }

        let picker = app.descendants(matching: .any)["appearance-preference"]
        picker.tap()
        app.buttons["System"].tap()
        let systemSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "System"),
            object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [systemSelected], timeout: 5), .completed)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        let restoredPicker = app.descendants(matching: .any)["appearance-preference"]
        XCTAssertTrue(restoredPicker.waitForExistence(timeout: 5))
        let restoredToSystem = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "System"),
            object: restoredPicker)
        XCTAssertEqual(
            XCTWaiter.wait(for: [restoredToSystem], timeout: 5),
            .completed,
            "The simulator should be left using System appearance.")
    }

    func testLanguagePreferenceChangesCopyAndPersists() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()

        let picker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let french = app.buttons["Français"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()

        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Français"),
            object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertEqual(app.buttons["tab-you"].label, "Toi", "Changing language should update visible copy immediately.")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        let restoredPicker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(restoredPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredPicker.value as? String, "Français")

        restoredPicker.tap()
        app.buttons["Suivre la langue de l’iPhone"].tap()
        app.terminate()
    }

    func testPaywallScreenshotRouteIsReachable() {
        let app = launchDemo(route: "paywall")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Plus")).firstMatch.waitForExistence(timeout: 10))
    }

    func testPhoneCodeRequiresTheDisclosedButtonAction() {
        let app = launchDemo(route: "phone")
        XCTAssertTrue(app.textFields["phone-number"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "By tapping Send code")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacy-link"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["terms-link"].exists)

        let send = app.buttons["send-phone-code"]
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled, "A code cannot be sent without a phone number.")
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
