import UIKit
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

    func testEmptyHistoryFillsPersonScreenInBothAppearances() {
        var centerColors: [UInt32] = []
        for dark in [false, true] {
            let app = launchDemo(dark: dark, route: "empty")
            XCTAssertTrue(app.staticTexts["No recent places"].waitForExistence(timeout: 20), app.debugDescription)
            guard let image = app.screenshot().image.cgImage else {
                XCTFail("Expected a simulator screenshot to inspect the screen background.")
                app.terminate()
                continue
            }
            let x = image.width / 12
            let top = pixelColor(image, x: x, y: image.height / 5)
            let center = pixelColor(image, x: x, y: image.height / 2)
            let bottom = pixelColor(image, x: x, y: image.height * 4 / 5)
            XCTAssertEqual(top, center, "The history screen should not leave a top letterbox.")
            XCTAssertEqual(bottom, center, "The history screen should not leave a bottom letterbox.")
            centerColors.append(center)
            app.terminate()
        }
        XCTAssertNotEqual(centerColors.first, centerColors.last, "The test should cover both light and dark appearances.")
    }

    func testSleepyPresetAvatarUsesAdaptiveBackingInBothAppearances() {
        let appearances: [(dark: Bool, rgb: [Int])] = [
            (false, [0xFC, 0xFA, 0xF2]),
            (true, [0x33, 0x40, 0x55])
        ]

        for appearance in appearances {
            let app = launchDemo(dark: appearance.dark, route: "you")
            XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
            let editPicture = app.buttons["edit-profile-picture"]
            XCTAssertTrue(scrollYouContent(to: editPicture, direction: .up, in: app))
            editPicture.tap()

            let preview = app.buttons["avatar-photo-options"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            app.buttons["Fox icon"].tap()

            guard let image = app.screenshot().image.cgImage else {
                XCTFail("Expected a simulator screenshot for the profile-picture preview.")
                app.terminate()
                continue
            }
            let scale = CGFloat(image.width) / app.windows.firstMatch.frame.width
            // The transparent sleepy fox leaves a clear part of the adaptive disc at
            // the left midpoint. Sample inside the circle, away from the camera badge.
            let x = Int((preview.frame.minX + preview.frame.width * 0.05) * scale)
            let y = Int(preview.frame.midY * scale)
            let actual = pixelColor(image, x: x, y: y)
            XCTAssertTrue(
                approximatelyMatches(actual, rgb: appearance.rgb),
                "The avatar backing should adapt with the app appearance. Expected RGB \(appearance.rgb), sampled 0x\(String(actual, radix: 16))."
            )
            app.terminate()
        }
    }

    func testPauseResumeOffAndRemoveAreSeparateActions() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()

        app.buttons["sharing-actions-maya"].tap()
        let pause = app.buttons["pause-sharing-maya"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        tapVisibleMenuOption(pause, in: app)
        let pauseMenuDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: pause)
        XCTAssertEqual(XCTWaiter.wait(for: [pauseMenuDismissed], timeout: 5), .completed)
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
        let locationSheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["location-permission-status"])
        XCTAssertEqual(XCTWaiter.wait(for: [locationSheetDismissed], timeout: 5), .completed)
        let editProfilePicture = app.buttons["edit-profile-picture"]
        XCTAssertTrue(scrollYouContent(to: editProfilePicture, direction: .up, in: app), "The profile picture control should be hittable after the location sheet closes.")
        editProfilePicture.tap()
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
            XCTAssertTrue(scrollYouContent(to: picker, direction: .down, in: app), "The appearance picker should be hittable after scrolling down in You.")
            picker.tap()
            let choice = app.buttons[option]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "The picker should offer the \(option) appearance.")
            tapVisibleMenuOption(choice, in: app)

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
            XCTAssertTrue(scrollYouContent(to: relaunchedPicker, direction: .down, in: app), "The relaunched appearance picker should be hittable after scrolling down in You.")
            let preferenceRestored = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", option),
                object: relaunchedPicker)
            XCTAssertEqual(
                XCTWaiter.wait(for: [preferenceRestored], timeout: 5),
                .completed,
                "\(option) should persist after restarting the app.")
        }

        let picker = app.descendants(matching: .any)["appearance-preference"]
        XCTAssertTrue(scrollYouContent(to: picker, direction: .down, in: app))
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        tapVisibleMenuOption(app.buttons["System"], in: app)
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
        XCTAssertTrue(scrollYouContent(to: restoredPicker, direction: .down, in: app), "The restored appearance picker should be hittable after scrolling down in You.")
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
        tapVisibleMenuOption(french, in: app)
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

    func testAddPersonControlsRemainReachableWithAccessibilityText() {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchEnvironment["TRUST_DEMO"] = "1"
            app.launchEnvironment["TRUST_UI_TEST"] = "1"
            app.launchArguments += ["-appearancePreference", dark ? "dark" : "light",
                                    "-trust.appLanguage", "en",
                                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
            app.buttons["tab-sharing"].tap()
            let sharing = XCTAttachment(screenshot: app.screenshot())
            sharing.name = "Accessibility text - Sharing - \(dark ? "dark" : "light")"
            sharing.lifetime = .keepAlways
            add(sharing)
            app.buttons["add-someone-button"].tap()
            let field = app.textFields["connection-handle"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("abc")
            let clear = app.buttons["clear-connection-lookup"]
            XCTAssertTrue(clear.isHittable)
            XCTAssertGreaterThanOrEqual(clear.frame.width, 43.99)
            XCTAssertGreaterThanOrEqual(clear.frame.height, 43.99)
            let close = app.buttons["cancel-add-person"]
            XCTAssertTrue(close.isHittable)
            XCTAssertGreaterThanOrEqual(close.frame.height, 43.99)
            let lookup = XCTAttachment(screenshot: app.screenshot())
            lookup.name = "Accessibility text - Add keyboard - \(dark ? "dark" : "light")"
            lookup.lifetime = .keepAlways
            add(lookup)
            clear.tap()
            XCTAssertEqual(field.value as? String, "Handle or phone number")
            close.tap()
            XCTAssertTrue(app.buttons["add-someone-button"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    private func launchDemo(dark: Bool? = nil, route: String? = nil, forceEnglish: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        if let route { app.launchEnvironment["TRUST_SCREENSHOT"] = route }
        if let dark { app.launchArguments += ["-appearancePreference", dark ? "dark" : "light"] }
        // Demo tests assert English copy. The argument-domain override makes each launch
        // independent of the persistent language preference left by other simulator runs.
        if forceEnglish { app.launchArguments += ["-trust.appLanguage", "en"] }
        app.launch()
        return app
    }

    private func pixelColor(_ image: CGImage, x: Int, y: Int) -> UInt32 {
        guard image.bitsPerPixel == 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            XCTFail("Expected a 32-bit simulator screenshot.")
            return 0
        }
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        return UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private func approximatelyMatches(_ packed: UInt32, rgb expected: [Int]) -> Bool {
        let bytes = [
            Int((packed >> 24) & 0xFF),
            Int((packed >> 16) & 0xFF),
            Int((packed >> 8) & 0xFF),
            Int(packed & 0xFF)
        ]
        let channelOrders = [Array(bytes.prefix(3)), Array(bytes.dropFirst().prefix(3))]
        return channelOrders.contains { channels in
            [channels, channels.reversed()].contains { ordered in
                zip(ordered, expected).allSatisfy { abs($0 - $1) <= 12 }
            }
        }
    }

    private func selectSystemLanguage(in app: XCUIApplication) {
        let picker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        let systemOption = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "iPhone")
        ).firstMatch
        XCTAssertTrue(systemOption.waitForExistence(timeout: 5), "The language menu should offer the system-language option.")
        tapVisibleMenuOption(systemOption, in: app)
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

    /// Scrolls the You tab a few times and confirms the requested control is ready for input.
    /// Starting at the control's known side of the page also handles XCUI frames that are
    /// temporarily invalid while the control is outside the ScrollView viewport.
    private func scrollYouContent(to element: XCUIElement, direction: ScrollDirection, in app: XCUIApplication) -> Bool {
        let scrollView = app.scrollViews.firstMatch
        guard scrollView.waitForExistence(timeout: 5) else { return false }
        for _ in 0..<6 {
            if element.isHittable { return true }
            switch direction {
            case .up: scrollView.swipeDown()
            case .down: scrollView.swipeUp()
            }
        }
        return element.isHittable
    }

    private enum ScrollDirection {
        case up
        case down
    }

    /// CI recordings showed element.tap() leaving both Picker and Menu rows open.
    /// Wait for a stable visible row, then send one tap at its observed center;
    /// this does not assume a cause for the earlier undelivered selections.
    /// Never retry the action: callers must still prove the value or sheet changed.
    private func tapVisibleMenuOption(_ option: XCUIElement, in app: XCUIApplication) {
        var previousFrame: CGRect?
        var stableSince: Date?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard option.exists, option.isEnabled, option.isHittable else {
                previousFrame = nil
                stableSince = nil
                return false
            }
            let frame = option.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0,
                  center.x.isFinite, center.y.isFinite,
                  app.frame.contains(center) else { return false }
            if previousFrame != frame {
                previousFrame = frame
                stableSince = Date()
                return false
            }
            return stableSince.map { Date().timeIntervalSince($0) >= 0.35 } ?? false
        }, object: option)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed,
              let frame = previousFrame else {
            add(XCTAttachment(screenshot: app.screenshot()))
            XCTFail("The menu option did not settle into an enabled, hittable row. \(option.debugDescription)")
            return
        }
        let screen = app.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - screen.minX, dy: frame.midY - screen.minY))
            .tap()
    }
}
