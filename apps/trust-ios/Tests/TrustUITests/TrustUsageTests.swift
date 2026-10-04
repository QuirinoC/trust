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
        // XCTest can end a failing test before Swift defer executes. Register
        // cleanup with XCTest; separate termination still runs if restoration fails.
        addTeardownBlock { app.terminate() }
        addTeardownBlock { [self] in
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
            app.buttons["tab-you"].tap()
            selectSystemLanguage(in: app)
        }
        func selectLanguage(_ title: String) {
            let picker = app.descendants(matching: .any)["language-preference"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.tap()
            let option = app.buttons[title]
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            tapVisibleMenuOption(option, in: app)
            let selected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", title), object: picker)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        }
        func assertTabLabels(_ labels: [String]) {
            let identifiers = ["tab-circle", "tab-sharing", "tab-log", "tab-you"]
            let expectations = zip(identifiers, labels).map { identifier, label in
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@", label),
                    object: app.buttons[identifier])
            }
            XCTAssertEqual(XCTWaiter.wait(for: expectations, timeout: 5), .completed,
                           "Changing language should update every tab immediately.")
        }
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        selectLanguage("English")
        assertTabLabels(["People", "Sharing", "Activity", "You"])
        selectLanguage("Français")
        assertTabLabels(["Personnes", "Partage", "Activité", "Toi"])
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "French settings and all four tabs"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        let restoredPicker = app.descendants(matching: .any)["language-preference"]
        XCTAssertTrue(restoredPicker.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredPicker.value as? String, "Français")
        assertTabLabels(["Personnes", "Partage", "Activité", "Toi"])
        selectLanguage("English")
        assertTabLabels(["People", "Sharing", "Activity", "You"])
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

    func testWideWindowKeepsPeopleToTheRightOfTheMap() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchArguments = ["-trust.appLanguage", "en", "-appearancePreference", "light"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // CI runs this exact test separately on a wide iPad window and requires a
        // passing result there. Compact windows exercise the phone layout instead.
        guard window.frame.width >= 760 else {
            throw XCTSkip("The wide People layout requires a window at least 760 points wide; CI covers it in the dedicated iPad lane.")
        }
        let list = app.descendants(matching: .any)["people-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 8), app.debugDescription)
        let note = XCTAttachment(string: "window \(window.frame) people-list \(list.frame)")
        note.lifetime = .keepAlways
        add(note)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Duo People layout"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertGreaterThanOrEqual(window.frame.width, 760, "A window at least 760 points wide should use the side-by-side layout. Window \(window.frame).")
        XCTAssertGreaterThan(list.frame.minX, window.frame.width * 0.45, "People should stay to the right of the map. List \(list.frame), window \(window.frame).")
        XCTAssertLessThan(list.frame.width, window.frame.width * 0.55, "The people panel should not cover the map. List \(list.frame), window \(window.frame).")
    }

    func testMaximumTextSizeKeepsConnectedSharingControlsReachable() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchArguments = ["-appearancePreference", "light", "-trust.appLanguage", "en",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()
        let window = app.windows.firstMatch
        let tabBarTop = app.buttons["tab-circle"].frame.minY
        let sharingScroll = app.scrollViews.firstMatch
        XCTAssertTrue(sharingScroll.waitForExistence(timeout: 8))
        func isFullyReachable(_ control: XCUIElement) -> Bool {
            control.isHittable
                && control.frame.minY >= sharingScroll.frame.minY
                && control.frame.maxY <= min(sharingScroll.frame.maxY, tabBarTop) + 0.5
        }
        func nudge(_ control: XCUIElement) {
            let above = control.frame.midY < 180
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.42 : 0.62))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.62 : 0.46))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        for identifier in ["sharing-mode-off-maya", "sharing-mode-sealed-maya", "sharing-mode-always-maya", "sharing-actions-maya"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
            var reachable = isFullyReachable(control)
            for _ in 0..<8 where !reachable {
                nudge(control)
                reachable = isFullyReachable(control)
            }
            XCTAssertTrue(reachable, "\(identifier) should stay reachable at the largest text size. Frame \(control.frame).\n\(app.debugDescription)")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, identifier)
            XCTAssertGreaterThanOrEqual(control.frame.minY, sharingScroll.frame.minY, identifier)
            XCTAssertLessThanOrEqual(control.frame.maxY, sharingScroll.frame.maxY + 0.5, identifier)
            XCTAssertGreaterThanOrEqual(control.frame.minX, 0, identifier)
            XCTAssertLessThanOrEqual(control.frame.maxX, window.frame.maxX + 1, identifier)
            XCTAssertLessThanOrEqual(control.frame.maxY, tabBarTop + 1, "\(identifier) overlaps the tab bar. Control \(control.frame), tabs start at \(tabBarTop).")
        }

        let off = app.buttons["sharing-mode-off-maya"]
        let sealed = app.buttons["sharing-mode-sealed-maya"]
        let always = app.buttons["sharing-mode-always-maya"]
        XCTAssertLessThan(off.frame.midY, sealed.frame.midY, "Accessibility-size sharing modes should stack vertically.")
        XCTAssertLessThan(sealed.frame.midY, always.frame.midY, "Accessibility-size sharing modes should stack vertically.")
        for mode in [off, sealed, always] {
            XCTAssertGreaterThanOrEqual(mode.frame.width, window.frame.width * 0.7, "Mode labels need enough width to remain readable at the largest text size. Frame \(mode.frame).")
        }

        let tabNames = [
            ("tab-circle", "People"),
            ("tab-sharing", "Sharing"),
            ("tab-log", "Activity"),
            ("tab-you", "You")
        ]
        let tabs = tabNames.map { (app.buttons[$0.0], $0.1) }
        for (tab, name) in tabs {
            XCTAssertTrue(tab.isHittable, "\(name) navigation should remain reachable at the largest text size.")
            XCTAssertTrue(tab.label.contains(name), "Navigation should retain the complete tab name. Found \(tab.label).")
            XCTAssertGreaterThanOrEqual(tab.frame.width, window.frame.width * 0.4, "Each accessibility navigation cell should have room for its label.")
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44, "Each navigation cell should retain a 44pt tap target.")
        }
        XCTAssertLessThan(tabs[0].0.frame.midY, tabs[2].0.frame.midY, "Accessibility navigation should use two rows.")
        XCTAssertLessThan(tabs[1].0.frame.midY, tabs[3].0.frame.midY, "Accessibility navigation should use two rows.")
        XCTAssertLessThan(tabs[0].0.frame.midX, tabs[1].0.frame.midX, "The first navigation row should use two columns.")
        XCTAssertLessThan(tabs[2].0.frame.midX, tabs[3].0.frame.midX, "The second navigation row should use two columns.")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Maximum text - connected Sharing"
        shot.lifetime = .keepAlways
        add(shot)
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
            XCTAssertTrue(app.staticTexts["sharing-intro"].waitForExistence(timeout: 8), "Sharing content should load after the tab tap.")
            let demoBanner = app.staticTexts["Nine fictional people. Offline — no Sign in with Apple, nothing is sent."]
            let demoBannerDisappeared = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: demoBanner
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [demoBannerDisappeared], timeout: 10),
                .completed,
                "Wait for the demo toast to disappear naturally before tapping Add someone."
            )

            let addButton = app.buttons["add-someone-button"]
            XCTAssertTrue(addButton.waitForExistence(timeout: 8), "The Add someone action should exist before measuring reachability.")
            let sharingScroll = app.scrollViews.firstMatch
            XCTAssertTrue(sharingScroll.waitForExistence(timeout: 5), "Sharing content should remain inside its scroll view.")
            let sharingTab = app.buttons["tab-sharing"]

            func addButtonIsFullyReachable() -> Bool {
                let buttonFrame = addButton.frame
                let scrollFrame = sharingScroll.frame
                let visibleBottom = min(scrollFrame.maxY, sharingTab.frame.minY)
                return addButton.exists
                    && addButton.isHittable
                    && buttonFrame.width > 0
                    && buttonFrame.minY >= scrollFrame.minY
                    && buttonFrame.maxY <= visibleBottom
            }

            for _ in 0..<4 where !addButtonIsFullyReachable() {
                let start = sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                let end = sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.73))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            XCTAssertTrue(addButton.isHittable, "Add someone should be hittable after bounded scroll nudges.")
            XCTAssertGreaterThan(addButton.frame.width, 0)
            XCTAssertGreaterThanOrEqual(addButton.frame.height, 44, "Add someone should retain a 44-point hit target.")
            XCTAssertGreaterThanOrEqual(addButton.frame.minY, sharingScroll.frame.minY, "Add someone should be fully inside the Sharing scroll view.")
            XCTAssertLessThanOrEqual(addButton.frame.maxY, min(sharingScroll.frame.maxY, sharingTab.frame.minY), "Add someone should be fully above the tab bar.")

            let sharing = XCTAttachment(screenshot: app.screenshot())
            sharing.name = "Accessibility text - Sharing - \(dark ? "dark" : "light")"
            sharing.lifetime = .keepAlways
            add(sharing)
            addButton.tap()
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

    func testPeopleSheetDetentSurvivesTabChanges() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
        dismissDemoBanner(app)

        let detent = app.buttons["people-sheet-detent"]
        XCTAssertTrue(detent.waitForExistence(timeout: 8))
        XCTAssertEqual(detent.value as? String, "Half height")
        detent.tap()
        XCTAssertTrue(waitForValue("Expanded", on: detent), "The People sheet should expand before changing tabs.")

        app.buttons["tab-sharing"].tap()
        XCTAssertTrue(app.staticTexts["sharing-intro"].waitForExistence(timeout: 8))
        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: 8))
        app.buttons["tab-circle"].tap()

        XCTAssertTrue(detent.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue("Expanded", on: detent), "The People sheet should keep its expanded detent after visiting other tabs.")
    }

    func testMainTabsPassAccessibilityAudit() throws {
        var failures: [String] = []
        var ignoredIssues: [String] = []
        let previousContinueAfterFailure = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = previousContinueAfterFailure }
        for dark in [false, true] {
            let appearance = dark ? "dark" : "light"
            let app = launchDemo(dark: dark)
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
            dismissDemoBanner(app)
            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            let windowFrame = window.frame
            for tab in ["tab-circle", "tab-sharing", "tab-log", "tab-you"] {
                app.buttons[tab].tap()
                let contentReady: XCUIElement
                switch tab {
                case "tab-circle": contentReady = app.buttons["people-sheet-detent"]
                case "tab-sharing": contentReady = app.staticTexts["sharing-intro"]
                case "tab-log": contentReady = app.staticTexts["Activity"].firstMatch
                default: contentReady = app.buttons["edit-profile-picture"]
                }
                XCTAssertTrue(contentReady.waitForExistence(timeout: 8), "Selected content should load before auditing \(tab).")
                if tab == "tab-you" {
                    // The profile and personal-location card should both be fully
                    // visible. A partially scrolled label at the pinned legal footer
                    // is not a useful contrast sample of the label's actual colors.
                    let scroll = app.scrollViews["you-content"]
                    let location = app.buttons["my-location"]
                    XCTAssertTrue(scroll.waitForExistence(timeout: 8))
                    XCTAssertTrue(location.waitForExistence(timeout: 8))
                    for _ in 0..<4 {
                        if location.frame.minY >= scroll.frame.minY,
                           location.frame.maxY <= scroll.frame.maxY { break }
                        let distance = max(20, location.frame.maxY - scroll.frame.maxY + 12)
                        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                        let end = start.withOffset(CGVector(dx: 0, dy: -min(distance, scroll.frame.height * 0.3)))
                        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
                    }
                    XCTAssertTrue(location.isHittable)
                    XCTAssertGreaterThanOrEqual(location.frame.minY, scroll.frame.minY)
                    XCTAssertLessThanOrEqual(location.frame.maxY, scroll.frame.maxY)
                    XCTAssertGreaterThanOrEqual(contentReady.frame.minY, scroll.frame.minY, "The profile remains visible in this audit state.")
                    XCTAssertLessThanOrEqual(contentReady.frame.maxY, scroll.frame.maxY)
                }
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Accessibility audit - \(tab) - \(appearance)"
                shot.lifetime = .keepAlways
                add(shot)
                let audit = recordAccessibilityAudit(
                    app: app,
                    context: "\(tab) - \(appearance)",
                    windowFrame: windowFrame
                )
                failures.append(contentsOf: audit.failures)
                ignoredIssues.append(contentsOf: audit.ignoredIssues)
            }

            // Score the final People row while it is visible inside the expanded list.
            app.buttons["tab-circle"].tap()
            let detent = app.buttons["people-sheet-detent"]
            XCTAssertTrue(detent.waitForExistence(timeout: 8))
            if (detent.value as? String) != "Expanded" { detent.tap() }
            XCTAssertTrue(waitForValue("Expanded", on: detent))
            let peopleList = app.scrollViews["people-list"]
            let noah = app.buttons["person-row-noah"]
            XCTAssertTrue(peopleList.waitForExistence(timeout: 8))
            XCTAssertTrue(noah.waitForExistence(timeout: 8))
            for _ in 0..<8 {
                if noah.isHittable,
                   noah.frame.minY >= peopleList.frame.minY,
                   noah.frame.maxY <= peopleList.frame.maxY {
                    break
                }
                peopleList.swipeUp()
            }
            XCTAssertTrue(noah.isHittable, "The final People row should be visible before auditing the expanded list.")
            XCTAssertGreaterThanOrEqual(noah.frame.minY, peopleList.frame.minY)
            XCTAssertLessThanOrEqual(noah.frame.maxY, peopleList.frame.maxY)
            let peopleAudit = recordAccessibilityAudit(
                app: app,
                context: "People expanded - last row - \(appearance)",
                windowFrame: windowFrame
            )
            failures.append(contentsOf: peopleAudit.failures)
            ignoredIssues.append(contentsOf: peopleAudit.ignoredIssues)

            // Score the bottom of You as well, where account controls enter the viewport.
            app.buttons["tab-you"].tap()
            XCTAssertTrue(app.buttons["edit-profile-picture"].waitForExistence(timeout: 8))
            let youScrollView = app.scrollViews["you-content"]
            XCTAssertTrue(youScrollView.waitForExistence(timeout: 8))
            let deleteAccount = app.buttons["delete-account"]
            for _ in 0..<8 {
                if deleteAccount.isHittable,
                   deleteAccount.frame.minY >= youScrollView.frame.minY,
                   deleteAccount.frame.maxY <= youScrollView.frame.maxY { break }
                youScrollView.swipeUp()
            }
            XCTAssertTrue(deleteAccount.isHittable, "The bottom account action should be visible before auditing You.")
            XCTAssertGreaterThanOrEqual(deleteAccount.frame.minY, youScrollView.frame.minY)
            XCTAssertLessThanOrEqual(deleteAccount.frame.maxY, youScrollView.frame.maxY)
            let youAudit = recordAccessibilityAudit(
                app: app,
                context: "You bottom - \(appearance)",
                windowFrame: windowFrame
            )
            failures.append(contentsOf: youAudit.failures)
            ignoredIssues.append(contentsOf: youAudit.ignoredIssues)
        }
        print("Ignored accessibility audit issues (\(ignoredIssues.count)): \(ignoredIssues.joined(separator: "\n"))")
        XCTAssertTrue(failures.isEmpty, "Accessibility audit:\n\(failures.joined(separator: "\n"))")
    }

    private func recordAccessibilityAudit(
        app: XCUIApplication,
        context: String,
        windowFrame: CGRect
    ) -> (failures: [String], ignoredIssues: [String]) {
        // The tab bar stays visible and participates in every screen audit. Only the
        // exact MapKit Legal control, its identified canvas, and proven empty layout
        // artifacts can be ignored; clipped visible text and controls remain scored.
        var failures: [String] = []
        var ignoredIssues: [String] = []
        // Run every iOS audit type independently so a framework error in one check
        // does not prevent the remaining checks, screens, or appearance from running.
        let auditTypes: [(String, XCUIAccessibilityAuditType)] = [
            ("contrast", .contrast),
            ("elementDetection", .elementDetection),
            ("hitRegion", .hitRegion),
            ("sufficientElementDescription", .sufficientElementDescription),
            ("dynamicType", .dynamicType),
            ("textClipped", .textClipped),
            ("trait", .trait)
        ]
        for (auditName, auditType) in auditTypes {
            print("Accessibility check: \(context) | \(auditName)")
            let failureCount = failures.count
            do {
                try app.performAccessibilityAudit(for: auditType) { issue in
                    let element = issue.element
                    let label = element?.label ?? ""
                    let identifier = element?.identifier ?? ""
                    let elementType = element?.elementType
                    let frame = element?.frame
                    let summary = "\(context) | \(auditName) | \(identifier) | \(label) | \(issue.compactDescription) | \(issue.detailedDescription) | \(String(describing: elementType)) | \(String(describing: frame))"
                    let mapKitLegalControl = identifier.isEmpty && label == "Legal"
                    // This exact identifier marks the decorative MapKit canvas, whose rendered
                    // tiles are not Trust-authored accessibility controls.
                    let mapCanvas = identifier == "map-screen-canvas"
                    // Require an empty, unidentified container: zero-frame text is still scored.
                    let zeroFrameLayoutNode = elementType == .other
                        && identifier.isEmpty
                        && label.isEmpty
                        && frame.map { $0.width <= 0 || $0.height <= 0 } == true
                    let outsideWindow = frame.map { frame in
                        let hasFinitePositiveArea = frame.origin.x.isFinite
                            && frame.origin.y.isFinite
                            && frame.width.isFinite
                            && frame.height.isFinite
                            && frame.maxX.isFinite
                            && frame.maxY.isFinite
                            && frame.width > 0
                            && frame.height > 0
                        return hasFinitePositiveArea && (
                            frame.maxX <= windowFrame.minX || frame.minX >= windowFrame.maxX
                                || frame.maxY <= windowFrame.minY || frame.minY >= windowFrame.maxY
                        )
                    } ?? false
                    // SwiftUI retains offscreen row nodes in the AX tree. Require the
                    // exact node to belong to an explicitly clipped Trust ScrollView
                    // and lie wholly outside its viewport. Partly visible text is scored.
                    let outsideClippedViewport: Bool
                    var viewportIdentityEvidence: String?
                    let hasFinitePositiveBounds: (CGRect) -> Bool = { candidateFrame in
                        candidateFrame.minX.isFinite
                            && candidateFrame.minY.isFinite
                            && candidateFrame.width.isFinite
                            && candidateFrame.height.isFinite
                            && candidateFrame.maxX.isFinite
                            && candidateFrame.maxY.isFinite
                            && candidateFrame.width > 0
                            && candidateFrame.height > 0
                    }
                    let isWhollyOutsideViewport: (CGRect, CGRect) -> Bool = { candidateFrame, viewportFrame in
                        hasFinitePositiveBounds(candidateFrame)
                            && hasFinitePositiveBounds(viewportFrame)
                            && !viewportFrame.intersects(candidateFrame)
                    }
                    if let frame, !label.isEmpty,
                       hasFinitePositiveBounds(frame), let elementType {
                        outsideClippedViewport = ["people-list", "you-content"].contains { scrollIdentifier in
                            let scroll = app.scrollViews[scrollIdentifier]
                            guard scroll.exists else { return false }
                            let viewportFrame = scroll.frame
                            guard hasFinitePositiveBounds(viewportFrame),
                                  isWhollyOutsideViewport(frame, viewportFrame) else { return false }
                            let matches = scroll.descendants(matching: .any)
                                .matching(NSPredicate(format: "label == %@", label))
                                .allElementsBoundByIndex
                                .filter { candidate in
                                    candidate.identifier == identifier
                                        && candidate.label == label
                                        && candidate.elementType == elementType
                                }
                            let sameFrameMatch = matches.contains { candidate in
                                let candidateFrame = candidate.frame
                                return isWhollyOutsideViewport(candidateFrame, viewportFrame)
                                    && abs(candidateFrame.minX - frame.minX) < 0.5
                                    && abs(candidateFrame.minY - frame.minY) < 0.5
                                    && abs(candidateFrame.width - frame.width) < 0.5
                                    && abs(candidateFrame.height - frame.height) < 0.5
                            }
                            if sameFrameMatch { return true }

                            guard identifier.hasPrefix("avatar-initials-"),
                                  identifier.count > "avatar-initials-".count,
                                  matches.count == 1,
                                  let candidate = matches.first else { return false }
                            let candidateFrame = candidate.frame
                            guard isWhollyOutsideViewport(candidateFrame, viewportFrame) else { return false }
                            viewportIdentityEvidence = "matched stable clipped avatar identity \(identifier), label \(label), type \(elementType), issue frame \(frame), candidate frame \(candidateFrame), viewport \(scrollIdentifier) \(viewportFrame)"
                            return true
                        }
                    } else {
                        outsideClippedViewport = false
                    }
                    if mapKitLegalControl || mapCanvas || zeroFrameLayoutNode || outsideWindow || outsideClippedViewport {
                        let recordedIssue = summary + (viewportIdentityEvidence.map { " | \($0)" } ?? "")
                        ignoredIssues.append(recordedIssue)
                        print("Ignored audit issue: \(recordedIssue)")
                        return true
                    }
                    failures.append(summary)
                    print("Audit issue: \(summary)")
                    return false
                }
            } catch {
                let summary = "\(context) | \(auditName) | Audit could not complete: \(error)"
                failures.append(summary)
                print(summary)
            }
            if failures.count > failureCount {
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "Accessibility failure tree - \(context) - \(auditName)"
                tree.lifetime = .keepAlways
                add(tree)
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Accessibility failure - \(context) - \(auditName)"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
        return (failures, ignoredIssues)
    }

    private func waitForValue(_ value: String, on element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func dismissDemoBanner(_ app: XCUIApplication) {
        let banner = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "fictional")).firstMatch
        guard banner.waitForExistence(timeout: 2) else { return }
        if banner.isHittable {
            banner.tap()
        }
        XCTAssertTrue(banner.waitForNonExistence(timeout: 6))
    }

    func testLastPersonRowScrollsClearOfTheTabBar() {
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
        dismissDemoBanner(app)
        let list = app.scrollViews["people-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 8))
        let noah = app.buttons["person-row-noah"]
        let tabTop = { app.buttons["tab-circle"].frame.minY }
        for _ in 0..<6 {
            if noah.exists, noah.isHittable, noah.frame.maxY <= tabTop() - 1, noah.frame.height >= 44 {
                break
            }
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(noah.exists, "Noah should be in the People list.")
        XCTAssertLessThanOrEqual(
            noah.frame.maxY,
            tabTop() + 0.5,
            "The last person must sit fully above the tab bar. row \(noah.frame) tab \(tabTop())"
        )
        XCTAssertGreaterThanOrEqual(noah.frame.height, 44)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Last person above the tab bar"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Spoken VoiceOver on iOS 27. The service reads the focused element; this walks People
    /// and Sharing and checks the names a person would hear.
    func testVoiceOverSpeaksPeopleAndSharing() throws {
#if compiler(>=6.4)
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("Spoken VoiceOver control requires iOS 27.")
        }
        let app = launchDemo()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 20))
        let service = XCUIDevice.shared.voiceOverService
        addTeardownBlock {
            if #available(iOS 27.0, *), service.isEnabled {
                try? service.disable()
            }
        }
        try service.enable()
        XCTAssertTrue(service.isEnabled)

        var spoken = try voiceOverUtterances(service, limit: 24)
        app.buttons["tab-sharing"].tap()
        spoken += try voiceOverUtterances(service, limit: 24)
        let transcript = spoken.joined(separator: "\n")
        let attachment = XCTAttachment(string: transcript)
        attachment.name = "VoiceOver transcript"
        attachment.lifetime = .keepAlways
        add(attachment)

        let heard = transcript.lowercased()
        XCTAssertTrue(heard.contains("people"), transcript)
        XCTAssertTrue(heard.contains("maya"), transcript)
        XCTAssertTrue(heard.contains("sharing"), transcript)
        XCTAssertFalse(heard.contains("presence hidden"), transcript)
        try service.disable()
#else
        throw XCTSkip("Spoken VoiceOver requires the Xcode 27 SDK and iOS 27.")
#endif
    }

#if compiler(>=6.4)
    @available(iOS 27.0, *)
    private func voiceOverUtterances(_ service: XCUIVoiceOverService, limit: Int) throws -> [String] {
        var lines: [String] = []
        if let current = try? service.currentSpeech() {
            lines.append(current.utterance)
        }
        for _ in 0..<limit {
            let next: XCUIVoiceOverService.Output
            do {
                next = try service.moveForward()
            } catch {
                break
            }
            if lines.contains(next.utterance), lines.count > 6 { break }
            lines.append(next.utterance)
        }
        return lines
    }
#endif

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

    /// Sample readiness without the predicate waiter's per-failure hierarchy dumps.
    /// CI timed out there before a tap, after costly remote AX reads.
    /// Keep exact frame stability and one contact; result assertions belong to callers.
    private func tapVisibleMenuOption(_ option: XCUIElement, in app: XCUIApplication) {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 10
        var previousFrame: CGRect?
        var stableSince: TimeInterval?
        var settledFrame: CGRect?
        var samples: [String] = []
        while ProcessInfo.processInfo.systemUptime < deadline {
            var hasSnapshot = false
            var enabled = false
            var hittable = false
            var validGeometry = false
            var frame = CGRect.null
            if let snapshot = try? option.snapshot() {
                hasSnapshot = true
                enabled = snapshot.isEnabled
                frame = snapshot.frame
                if enabled { hittable = option.isHittable }
                if hittable {
                    let center = CGPoint(x: frame.midX, y: frame.midY)
                    validGeometry = frame.width.isFinite && frame.height.isFinite
                        && frame.width > 0 && frame.height > 0
                        && center.x.isFinite && center.y.isFinite
                        && app.frame.contains(center)
                }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if hasSnapshot && enabled && hittable && validGeometry {
                if previousFrame != frame {
                    previousFrame = frame
                    stableSince = now
                }
                if let stableSince, now - stableSince >= 0.35, now < deadline {
                    settledFrame = frame
                }
            } else {
                // No ineligible interval may count toward frame stability.
                previousFrame = nil
                stableSince = nil
            }
            samples.append(String(format: "t=%.3f snapshot=%@ enabled=%@ hittable=%@ geometry=%@ frame=%@ stable=%.3f",
                                  now - started, String(hasSnapshot), String(enabled), String(hittable),
                                  String(validGeometry), NSCoder.string(for: frame),
                                  stableSince.map { now - $0 } ?? 0))
            if settledFrame != nil { break }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(min(0.1, remaining)))
            }
        }
        let readiness = XCTAttachment(string: samples.joined(separator: "\n"))
        readiness.name = "Menu readiness samples (no action retries)"
        readiness.lifetime = .keepAlways
        add(readiness)
        guard let frame = settledFrame else {
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
