import UIKit
import XCTest

/// Safe, fixture-backed app use. These flows stay inside the DEBUG demo and never send SMS,
/// change a live account, or open StoreKit purchase confirmation.
final class TrustUsageTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPeopleMapPinRemainsAboveListAtEveryDetent() {
        let variants = [(false, "UICTContentSizeCategoryL"),
                        (true, "UICTContentSizeCategoryL"),
                        (false, "UICTContentSizeCategoryAccessibilityXXXL")]
        for (dark, textSize) in variants {
            let app = launchDemo(dark: dark, route: "circle", contentSize: textSize)
            let handle = app.buttons["people-sheet-detent"]
            let header = app.otherElements["people-map-header"]
            let pin = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "people-map-pin-")
            ).firstMatch
            XCTAssertTrue(handle.waitForExistence(timeout: 20))
            XCTAssertTrue(header.waitForExistence(timeout: 5))
            XCTAssertTrue(pin.waitForExistence(timeout: 10), "The fixture must expose a location pin.")

            // Expand by tapping, then drag down to the compact detent. Check the real
            // annotation hit region, not a duplicated camera calculation.
            for (index, detent) in ["Half height", "Expanded", "Compact"].enumerated() {
                let selected = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", detent), object: handle)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
                var visibleSince: TimeInterval?
                let unobscured = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    let now = ProcessInfo.processInfo.systemUptime
                    let frame = pin.frame
                    let sheet = handle.frame
                    let window = app.windows.firstMatch.frame
                    let visible = pin.exists && !frame.isEmpty
                        && frame.maxY <= sheet.minY + 1
                        && frame.minX >= window.minX && frame.maxX <= window.maxX
                        && frame.minY >= header.frame.maxY - 1
                    if !visible { visibleSince = nil; return false }
                    if visibleSince == nil { visibleSince = now }
                    return now - (visibleSince ?? now) >= 0.5
                }, object: nil)
                let viewportResult = XCTWaiter.wait(for: [unobscured], timeout: 10)
                if viewportResult != .completed {
                    add(XCTAttachment(screenshot: app.screenshot()))
                    add(XCTAttachment(string: "Pin: \(pin.frame); header: \(header.frame); panel: \(handle.frame)"))
                }
                XCTAssertEqual(viewportResult, .completed,
                               "The entire pin must remain above the People panel at \(detent).")
                XCTAssertGreaterThanOrEqual(
                    handle.frame.height, 43.99,
                    "The detent control should meet its 44-point target within frame rounding."
                )
                let capture = XCTAttachment(screenshot: app.screenshot())
                capture.name = "People viewport - \(detent) - \(dark ? "dark" : "light") - \(textSize)"
                capture.lifetime = .keepAlways
                add(capture)
                if index == 0 {
                    handle.tap()
                } else if index == 1 {
                    handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        .press(forDuration: 0.15, thenDragTo: app.coordinate(
                            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
                }
            }
            pin.tap()
            XCTAssertTrue(app.staticTexts["person-sharing-directions"].waitForExistence(timeout: 5),
                          "The visible pin must remain actionable after resizing the panel.")
            app.terminate()
        }
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

    func testSharingCompactRowGeometryAtStandardTextAcrossShippedLocales() {
        let variants: [(language: String, labels: [String], dark: Bool)] = [
            ("en", ["Off", "Sealed", "Always"], false),
            ("de", ["Aus", "Versiegelt", "Immer"], false),
            ("fr", ["Désactivé", "Scellé", "Toujours"], false),
            ("ja", ["オフ", "封印", "常時"], false),
            ("pt-BR", ["Desativado", "Lacrado", "Sempre"], false),
            ("zh-Hans", ["离开", "密封的", "总是"], false),
            ("en", ["Off", "Sealed", "Always"], true)
        ]

        for variant in variants {
            let app = XCUIApplication()
            app.launchEnvironment["TRUST_DEMO"] = "1"
            app.launchEnvironment["TRUST_UI_TEST"] = "1"
            app.launchEnvironment["TRUST_SCREENSHOT"] = "share"
            app.launchArguments += [
                "-appearancePreference", variant.dark ? "dark" : "light",
                "-trust.appLanguage", variant.language,
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
            ]
            app.launch()
            XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
            app.buttons["tab-sharing"].tap()

            let viewport = app.scrollViews["sharing-scroll"]
            let row = app.descendants(matching: .any)["sharing-mode-group-maya"]
            let name = row.staticTexts.matching(NSPredicate(format: "label == %@", "Maya Chen")).firstMatch
            let off = app.buttons["sharing-mode-off-maya"]
            let sealed = app.buttons["sharing-mode-sealed-maya"]
            let always = app.buttons["sharing-mode-always-maya"]
            let actions = app.buttons["sharing-actions-maya"]
            XCTAssertTrue(viewport.waitForExistence(timeout: 5))
            XCTAssertTrue(row.waitForExistence(timeout: 8), "Maya's row should be present in \(variant.language).")

            for _ in 0..<8 where !row.isHittable {
                viewport.swipeUp()
            }
            XCTAssertTrue(name.waitForExistence(timeout: 5), "The row must retain Maya's identity.")
            let controls = [row, name, off, sealed, always, actions]
            guard let frames = steadyVisibleFrames(controls, in: viewport, app: app) else {
                XCTFail("Sharing row geometry did not remain steady and visible in \(variant.language).")
                add(XCTAttachment(screenshot: app.screenshot()))
                app.terminate()
                continue
            }

            let rowFrame = frames[0]
            let nameFrame = frames[1]
            let offFrame = frames[2]
            let sealedFrame = frames[3]
            let alwaysFrame = frames[4]
            let actionsFrame = frames[5]
            let screen = app.frame
            let epsilon: CGFloat = 1
            XCTAssertGreaterThan(min(nameFrame.maxY, offFrame.maxY) - max(nameFrame.minY, offFrame.minY), 0,
                                 "The name and mode controls must share one horizontal row.")
            XCTAssertGreaterThan(min(offFrame.maxY, sealedFrame.maxY) - max(offFrame.minY, sealedFrame.minY), 0)
            XCTAssertGreaterThan(min(sealedFrame.maxY, alwaysFrame.maxY) - max(sealedFrame.minY, alwaysFrame.minY), 0)
            XCTAssertGreaterThan(min(alwaysFrame.maxY, actionsFrame.maxY) - max(alwaysFrame.minY, actionsFrame.minY), 0)
            XCTAssertLessThanOrEqual(nameFrame.maxX, offFrame.minX + epsilon)
            XCTAssertLessThanOrEqual(offFrame.maxX + 3, sealedFrame.minX,
                                     "Localized labels need visible separation inside the segmented control.")
            XCTAssertLessThanOrEqual(sealedFrame.maxX + 3, alwaysFrame.minX,
                                     "Localized labels need visible separation inside the segmented control.")
            XCTAssertLessThanOrEqual(alwaysFrame.maxX, actionsFrame.minX + epsilon)
            for frame in [nameFrame, offFrame, sealedFrame, alwaysFrame, actionsFrame] {
                XCTAssertGreaterThanOrEqual(frame.minX, rowFrame.minX - epsilon)
                XCTAssertLessThanOrEqual(frame.maxX, rowFrame.maxX + epsilon)
                XCTAssertGreaterThanOrEqual(frame.minY, rowFrame.minY - epsilon)
                XCTAssertLessThanOrEqual(frame.maxY, rowFrame.maxY + epsilon)
                XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - epsilon)
                XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + epsilon)
                XCTAssertGreaterThanOrEqual(frame.minY, screen.minY - epsilon)
                XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + epsilon)
                XCTAssertGreaterThanOrEqual(frame.minY, viewport.frame.minY - epsilon)
                XCTAssertLessThanOrEqual(frame.maxY, viewport.frame.maxY + epsilon)
            }
            XCTAssertLessThanOrEqual(rowFrame.height, 76,
                                     "An unpaused normal-size row must stay compact without a permanent consequence paragraph.")
            XCTAssertFalse(app.staticTexts["sharing-summary-maya"].exists,
                           "An unpaused row should not add a repeated mode explanation.")
            XCTAssertEqual([off.label, sealed.label], Array(variant.labels.prefix(2)),
                           "Each mode button must expose its complete localized label.")
            XCTAssertTrue(always.label.hasPrefix(variant.labels[2]),
                          "The Always button must expose its complete localized label, with any access note after it.")
            for button in [off, sealed, always, actions] {
                XCTAssertGreaterThanOrEqual(button.frame.width, 43.99)
                XCTAssertGreaterThanOrEqual(button.frame.height, 43.99)
                XCTAssertTrue(button.isHittable)
            }
            XCTAssertTrue(name.isHittable)
            let geometry = XCTAttachment(string: "language=\(variant.language) dark=\(variant.dark) category=Large screen=\(screen) row=\(rowFrame) name=\(nameFrame) Off=\(offFrame) Sealed=\(sealedFrame) Always=\(alwaysFrame) menu=\(actionsFrame)")
            geometry.name = "Sharing compact row geometry - \(variant.language) - \(variant.dark ? "dark" : "light")"
            geometry.lifetime = .keepAlways
            add(geometry)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Sharing compact row - \(variant.language) - \(variant.dark ? "dark" : "light")"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    func testMapSelectionKeepsPersonAndLocationContextTogether() {
        let app = launchDemo(route: "view")
        XCTAssertTrue(app.buttons["circle-back"].waitForExistence(timeout: 20))
        app.buttons["circle-back"].tap()
        let maya = app.buttons["person-row-maya"]
        XCTAssertTrue(maya.waitForExistence(timeout: 8))
        maya.tap()
        let look = app.buttons["person-profile-peek"]
        XCTAssertTrue(look.waitForExistence(timeout: 5))
        look.tap()
        XCTAssertTrue(app.buttons["confirm-look-notify"].waitForExistence(timeout: 5))
        app.buttons["confirm-look-notify"].tap()
        let openMap = app.buttons["view-open-map"]
        XCTAssertTrue(openMap.waitForExistence(timeout: 8))
        openMap.tap()

        let back = app.buttons["map-back-to-people"]
        XCTAssertTrue(back.waitForExistence(timeout: 8))
        let map = app.descendants(matching: .any)["map-screen-canvas"]
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        let showLeo = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Show Leo")).firstMatch
        let showMaya = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Show Maya")).firstMatch
        XCTAssertTrue(showLeo.waitForExistence(timeout: 8), "The Plus demo map should contain Leo's live pin.")
        XCTAssertTrue(showMaya.waitForExistence(timeout: 8), "The confirmed Look should add Maya's snapshot pin.")

        let name = app.descendants(matching: .any)["map-selected-person-name"]
        let time = app.descendants(matching: .any)["map-selected-location-time"]
        let selectedPersonAction = app.buttons["map-view-selected-person"]
        showLeo.tap()
        XCTAssertTrue(waitForSteadyMapDetail(name: name, time: time, expectedName: "Leo Park", expectedContext: "Always"))
        XCTAssertTrue(showLeo.isSelected)
        XCTAssertTrue(selectedPersonAction.label.contains("Leo"))
        showMaya.tap()
        XCTAssertTrue(waitForSteadyMapDetail(name: name, time: time, expectedName: "Maya Chen", expectedContext: "Snapshot"))
        XCTAssertTrue(showMaya.isSelected)
        XCTAssertTrue(selectedPersonAction.label.contains("Maya"))
        showLeo.tap()
        XCTAssertTrue(waitForSteadyMapDetail(name: name, time: time, expectedName: "Leo Park", expectedContext: "Always"))
        XCTAssertTrue(showLeo.isSelected)
        XCTAssertTrue(selectedPersonAction.label.contains("Leo"))
        showMaya.tap()
        XCTAssertTrue(waitForSteadyMapDetail(name: name, time: time, expectedName: "Maya Chen", expectedContext: "Snapshot"))
        XCTAssertTrue(showMaya.isSelected)
        let detailTime = time.label
        let snapshotPrefix = "Snapshot · "
        XCTAssertTrue(detailTime.hasPrefix(snapshotPrefix), "The selected Sealed person must retain the dated one-time snapshot label.")
        let snapshotTime = detailTime.dropFirst(snapshotPrefix.count).components(separatedBy: " · ").first ?? ""
        XCTAssertFalse(snapshotTime.isEmpty)
        XCTAssertEqual(name.label, "Maya Chen")
        XCTAssertTrue(selectedPersonAction.label.contains("Maya"))
        selectedPersonAction.tap()
        let viewedName = app.staticTexts["Maya"]
        XCTAssertTrue(viewedName.waitForExistence(timeout: 8), "Opening the selected map action should keep Maya as the viewed person.")
        let viewedFreshness = app.staticTexts["view-location-freshness"]
        XCTAssertTrue(viewedFreshness.waitForExistence(timeout: 5))
        XCTAssertTrue(viewedFreshness.label.contains(snapshotTime), "The opened View should preserve the selected snapshot time.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Map selection - Maya snapshot beside Leo live pin"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSharingGermanExtraExtraLargeRowBoundary() {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_SCREENSHOT"] = "share"
        app.launchArguments += [
            "-appearancePreference", "light",
            "-trust.appLanguage", "de",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXL"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-sharing"].tap()

        let viewport = app.scrollViews["sharing-scroll"]
        let row = app.descendants(matching: .any)["sharing-mode-group-maya"]
        let name = row.staticTexts.matching(NSPredicate(format: "label == %@", "Maya Chen")).firstMatch
        let off = app.buttons["sharing-mode-off-maya"]
        let sealed = app.buttons["sharing-mode-sealed-maya"]
        let always = app.buttons["sharing-mode-always-maya"]
        let actions = app.buttons["sharing-actions-maya"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        for _ in 0..<8 where !row.isHittable { viewport.swipeUp() }
        guard let frames = steadyVisibleFrames([row, name, off, sealed, always, actions], in: viewport, app: app) else {
            XCTFail("German XXL Sharing controls did not remain steady and visible.")
            add(XCTAttachment(screenshot: app.screenshot()))
            app.terminate()
            return
        }
        let rowFrame = frames[0]
        let nameFrame = frames[1]
        let offFrame = frames[2]
        let sealedFrame = frames[3]
        let alwaysFrame = frames[4]
        let actionsFrame = frames[5]
        XCTAssertGreaterThan(min(nameFrame.maxY, offFrame.maxY) - max(nameFrame.minY, offFrame.minY), 0)
        XCTAssertGreaterThan(min(offFrame.maxY, sealedFrame.maxY) - max(offFrame.minY, sealedFrame.minY), 0)
        XCTAssertGreaterThan(min(sealedFrame.maxY, alwaysFrame.maxY) - max(sealedFrame.minY, alwaysFrame.minY), 0)
        XCTAssertLessThanOrEqual(nameFrame.maxX, offFrame.minX + 1)
        XCTAssertLessThanOrEqual(offFrame.maxX + 3, sealedFrame.minX,
                                 "German XXL labels must not touch inside the segmented control.")
        XCTAssertLessThanOrEqual(sealedFrame.maxX + 3, alwaysFrame.minX,
                                 "German XXL labels must not touch inside the segmented control.")
        XCTAssertLessThanOrEqual(alwaysFrame.maxX, actionsFrame.minX + 1)
        for frame in [nameFrame, offFrame, sealedFrame, alwaysFrame, actionsFrame] {
            XCTAssertGreaterThanOrEqual(frame.minX, rowFrame.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, rowFrame.maxX + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, rowFrame.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, rowFrame.maxY + 1)
            XCTAssertGreaterThanOrEqual(frame.minY, viewport.frame.minY - 1)
            XCTAssertLessThanOrEqual(frame.maxY, viewport.frame.maxY + 1)
        }
        XCTAssertEqual([off.label, sealed.label], ["Aus", "Versiegelt"])
        XCTAssertTrue(always.label.hasPrefix("Immer"), "Always must remain fully localized, with any Plus note after its label.")
        for button in [off, sealed, always, actions] {
            XCTAssertGreaterThanOrEqual(button.frame.width, 43.99)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.99)
            XCTAssertTrue(button.isHittable)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Sharing German XXL boundary - horizontal phone row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
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
        let variants: [(dark: Bool, language: String)] = [
            (false, "en"),
            (true, "en"),
            (false, "de")
        ]
        for variant in variants {
            let dark = variant.dark
            let app = XCUIApplication()
            app.launchEnvironment["TRUST_DEMO"] = "1"
            app.launchEnvironment["TRUST_UI_TEST"] = "1"
            app.launchEnvironment["TRUST_SCREENSHOT"] = "share"
            app.launchArguments += ["-appearancePreference", dark ? "dark" : "light",
                                    "-trust.appLanguage", variant.language,
                                    "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
            app.buttons["tab-sharing"].tap()
            let sharing = XCTAttachment(screenshot: app.screenshot())
            sharing.name = "Accessibility text - Sharing - \(variant.language) - \(dark ? "dark" : "light")"
            sharing.lifetime = .keepAlways
            add(sharing)
            let sharingScroll = app.scrollViews["sharing-scroll"]
            XCTAssertTrue(sharingScroll.waitForExistence(timeout: 5))
            let off = app.buttons["sharing-mode-off-maya"]
            let sealed = app.buttons["sharing-mode-sealed-maya"]
            let always = app.buttons["sharing-mode-always-maya"]
            XCTAssertTrue(off.waitForExistence(timeout: 5))
            XCTAssertTrue(sealed.exists)
            XCTAssertTrue(always.exists)
            func nudgeSharingScroll(forward: Bool) {
                let startY: CGFloat = forward ? 0.78 : 0.30
                let endY: CGFloat = forward ? 0.54 : 0.54
                let start = sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: startY))
                let end = sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: endY))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            for _ in 0..<24 {
                if off.isHittable && sealed.isHittable && always.isHittable { break }
                let controlCenter = (off.frame.midY + always.frame.midY) / 2
                nudgeSharingScroll(forward: controlCenter > sharingScroll.frame.midY)
            }
            XCTAssertTrue(off.isHittable, "Off must remain reachable in the Sharing row.")
            XCTAssertTrue(off.isEnabled, "Off remains an enabled choice alongside Maya's confirmed Sealed state.")
            XCTAssertTrue(sealed.isHittable, "Sealed must remain reachable in the Sharing row.")
            XCTAssertTrue(always.isHittable, "Always must remain reachable in the Sharing row.")
            for control in [off, sealed, always] {
                XCTAssertGreaterThanOrEqual(control.frame.width, 43.99)
                XCTAssertGreaterThanOrEqual(control.frame.height, 43.99)
            }
            XCTAssertTrue(sealed.isSelected, "Maya's initial confirmed mode should remain Sealed while Off remains available.")
            let modes = XCTAttachment(screenshot: app.screenshot())
            modes.name = "Accessibility text - Sharing modes - \(variant.language) - \(dark ? "dark" : "light")"
            modes.lifetime = .keepAlways
            add(modes)
            let addSomeone = app.buttons["add-someone-button"]
            for _ in 0..<24 {
                if addSomeone.isHittable { break }
                nudgeSharingScroll(forward: addSomeone.frame.midY > sharingScroll.frame.midY)
            }
            XCTAssertTrue(addSomeone.isHittable)
            addSomeone.tap()
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
            lookup.name = "Accessibility text - Add keyboard - \(variant.language) - \(dark ? "dark" : "light")"
            lookup.lifetime = .keepAlways
            add(lookup)
            clear.tap()
            XCTAssertEqual(field.value as? String, field.placeholderValue)
            close.tap()
            XCTAssertTrue(app.buttons["add-someone-button"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    private func steadyVisibleFrames(
        _ elements: [XCUIElement],
        in viewport: XCUIElement,
        app: XCUIApplication,
        stableFor: TimeInterval = 0.35,
        timeout: TimeInterval = 20
    ) -> [CGRect]? {
        let start = ProcessInfo.processInfo.systemUptime
        let deadline = start + timeout
        var previous: [CGRect]?
        var stableSince: TimeInterval?
        var samples: [String] = []
        var settled: [CGRect]?

        while ProcessInfo.processInfo.systemUptime < deadline {
            let frames = elements.map(\.frame)
            let screen = app.frame
            let viewportFrame = viewport.frame
            let geometryValid = frames.allSatisfy { frame in
                frame.width > 0 && frame.height > 0
                    && frame.minX >= screen.minX - 1 && frame.maxX <= screen.maxX + 1
                    && frame.minY >= screen.minY - 1 && frame.maxY <= screen.maxY + 1
                    && frame.minX >= viewportFrame.minX - 1 && frame.maxX <= viewportFrame.maxX + 1
                    && frame.minY >= viewportFrame.minY - 1 && frame.maxY <= viewportFrame.maxY + 1
            }
            // Keep the sampling loop to geometry reads. Final button hit tests below
            // cover interactivity without repeated remote accessibility queries here.
            let visible = geometryValid
            let now = ProcessInfo.processInfo.systemUptime
            if visible, let previous, previous == frames {
                if stableSince == nil { stableSince = now }
                if let stableSince, now - stableSince >= stableFor {
                    settled = frames
                    break
                }
            } else if visible {
                previous = frames
                stableSince = now
            } else {
                previous = nil
                stableSince = nil
            }
            samples.append(String(format: "t=%.3f visible=%@ geometry=%@ frames=%@ stable=%.3f",
                                  now - start, String(visible), String(geometryValid),
                                  frames.map { NSCoder.string(for: $0) }.joined(separator: "; "),
                                  stableSince.map { now - $0 } ?? 0))
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(min(0.1, remaining)))
            }
        }

        let witness = XCTAttachment(string: samples.joined(separator: "\n"))
        witness.name = "Stable visible frame witness"
        witness.lifetime = .keepAlways
        add(witness)
        return settled
    }

    private func waitForSteadyMapDetail(
        name: XCUIElement,
        time: XCUIElement,
        expectedName: String,
        expectedContext: String,
        timeout: TimeInterval = 8,
        stableFor: TimeInterval = 0.25
    ) -> Bool {
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + timeout
        var previous: [String]?
        var stableSince: TimeInterval?
        var samples: [String] = []
        var settled = false

        while ProcessInfo.processInfo.systemUptime < deadline {
            let now = ProcessInfo.processInfo.systemUptime
            let values = [name.label, time.label]
            let matches = values[0] == expectedName && values[1].contains(expectedContext)
            if matches, values == previous {
                if stableSince == nil { stableSince = now }
                if let stableSince, now - stableSince >= stableFor {
                    settled = true
                    break
                }
            } else if matches {
                previous = values
                stableSince = now
            } else {
                previous = nil
                stableSince = nil
            }
            samples.append(String(format: "t=%.3f matches=%@ name=%@ time=%@ stable=%.3f",
                                  now - started, String(matches), values[0], values[1],
                                  stableSince.map { now - $0 } ?? 0))
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(min(0.1, remaining)))
            }
        }

        let witness = XCTAttachment(string: samples.joined(separator: "\n"))
        witness.name = "Map selected person and freshness witness"
        witness.lifetime = .keepAlways
        add(witness)
        return settled
    }

    private func launchDemo(dark: Bool? = nil, route: String? = nil, forceEnglish: Bool = true, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        if let route { app.launchEnvironment["TRUST_SCREENSHOT"] = route }
        if let dark { app.launchArguments += ["-appearancePreference", dark ? "dark" : "light"] }
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
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
