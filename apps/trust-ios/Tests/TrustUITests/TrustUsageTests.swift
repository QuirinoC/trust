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
        XCTAssertTrue(app.staticTexts["add-person-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["add-person-explanation"].exists, "Explain that connecting does not start sharing, without repeating phone-format guidance.")
        let handle = app.textFields["connection-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertEqual(handle.placeholderValue, "Handle or phone number")
        let addScreenshot = XCTAttachment(screenshot: app.screenshot())
        addScreenshot.name = "Add someone - redesigned empty state"
        addScreenshot.lifetime = .keepAlways
        add(addScreenshot)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "complete phone number")).firstMatch.exists, "Do not repeat the identifier guidance below the field.")
        XCTAssertFalse(app.buttons["lookup-connection-handle"].exists, "Lookup should happen automatically as the person types.")
        handle.typeText("jordan")
        XCTAssertTrue(app.staticTexts["connection-lookup-notice"].waitForExistence(timeout: 5), "The demo should not fabricate handle lookup results.")
        XCTAssertFalse(app.textFields["invite-code"].exists)
        XCTAssertFalse(app.textFields["add-phone"].exists)
        app.buttons["clear-connection-lookup"].tap()
        handle.typeText("jo!\n")
        XCTAssertTrue(app.staticTexts["connection-lookup-notice"].waitForExistence(timeout: 3), "Submitting an invalid handle should explain the problem instead of leaving the sheet blank.")
        XCTAssertTrue(app.staticTexts["connection-lookup-notice"].label.contains("valid"))
        app.buttons["clear-connection-lookup"].tap()
        handle.typeText("415-555\n")
        XCTAssertTrue(app.staticTexts["connection-lookup-hint"].waitForExistence(timeout: 3), "Submitting an incomplete phone number should explain the required format without showing guidance on the initial screen.")
        XCTAssertTrue(app.staticTexts["connection-lookup-hint"].label.contains("complete phone number"))
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
        // Start directly on You so this persistence test does not race the demo's
        // first-launch toast and initial tab transition.
        let app = launchDemo(route: "you")
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))

        for option in ["System", "Light", "Dark"] {
            let picker = app.descendants(matching: .any)["appearance-preference"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5), "The appearance picker should be available in You.")
            picker.tap()
            let choice = app.buttons[option]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "The picker should offer the \(option) appearance.")
            let choiceHittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"),
                object: choice)
            XCTAssertEqual(
                XCTWaiter.wait(for: [choiceHittable], timeout: 5),
                .completed,
                "The \(option) appearance choice should be hittable before selection. \(app.debugDescription)")
            choice.tap()

            // The collapsed native Picker can keep the selected option's label hittable, so
            // verify the value itself rather than infer menu dismissal from that label.
            // Changing the color scheme can recreate the SwiftUI hierarchy, so reacquire it.
            let updatedPicker = app.descendants(matching: .any)["appearance-preference"]
            let selectionApplied = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", option),
                object: updatedPicker)
            let selectionResult = XCTWaiter.wait(for: [selectionApplied], timeout: 10)
            if selectionResult != .completed {
                XCTFail(
                    "The picker should reflect the selected appearance. " +
                    "Expected=\(option), actual label=\(updatedPicker.label), value=\(String(describing: updatedPicker.value)). " +
                    "Picker=\(updatedPicker.debugDescription)\nApp hierarchy=\(app.debugDescription)")
            }

            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
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
        let resetPicker = app.descendants(matching: .any)["appearance-preference"]
        let systemSelected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "System"),
            object: resetPicker)
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
        let app = launchDemo(forceEnglish: false)
        var changedLanguage = false
        defer {
            // Keep a failed assertion from leaking French into the rest of the suite.
            if changedLanguage {
                if app.state != .runningForeground { app.launch() }
                if app.buttons["tab-you"].waitForExistence(timeout: 10) {
                    app.buttons["tab-you"].tap()
                    selectSystemLanguage(in: app)
                }
                app.terminate()
            }
        }
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()

        let picker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let french = app.buttons["Français"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()
        changedLanguage = true

        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Français"),
            object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let localizedTab = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Toi"),
            object: app.buttons["tab-you"])
        XCTAssertEqual(
            XCTWaiter.wait(for: [localizedTab], timeout: 5),
            .completed,
            "Changing language should update visible copy immediately.")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        let restoredPicker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(restoredPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredPicker.value as? String, "Français")

        selectSystemLanguage(in: app)
        changedLanguage = false
        app.terminate()

    }

    func testPaywallScreenshotRouteIsReachable() {
        let app = launchDemo(route: "paywall")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Plus")).firstMatch.waitForExistence(timeout: 10))
    }

    func testLookupScreenshotRouteShowsCurrentAddPersonDesign() {
        let app = launchDemo(route: "lookup")
        XCTAssertTrue(app.staticTexts["add-person-heading"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["connection-lookup-result"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["send-connection-request"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "App Store - Find a person by handle"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Phone verification - Disclosed Send code action"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launchDemo(dark: Bool = false, route: String? = nil, forceEnglish: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        if let route { app.launchEnvironment["TRUST_SCREENSHOT"] = route }
        if dark { app.launchArguments += ["-uiUserInterfaceStyle", "Dark"] }
        // Demo tests assert English copy. The argument-domain override makes each launch
        // independent of the persistent language preference left by other simulator runs.
        if forceEnglish { app.launchArguments += ["-trust.appLanguage", "en"] }
        app.launch()
        return app
    }

    private func selectSystemLanguage(in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let systemOption = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "iPhone")
        ).firstMatch
        XCTAssertTrue(systemOption.waitForExistence(timeout: 5), "The language menu should offer the system-language option.")
        systemOption.tap()
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@", "iPhone"),
            object: app.descendants(matching: .any)["language-preference"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }

    private func tapConfirmationAction(_ identifier: String, in app: XCUIApplication) {
        let matches = app.buttons.matching(identifier: identifier)
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 5))
        // SwiftUI exposes a confirmation-dialog action through both its legacy and modern
        // automation attributes; the build log confirms these are two aliases of one control.
        let action = matches.element(boundBy: 0)
        action.tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: action)
        XCTAssertEqual(
            XCTWaiter.wait(for: [dismissed], timeout: 5),
            .completed,
            "The confirmation dialog should dismiss before the next sharing action.")
    }
}
