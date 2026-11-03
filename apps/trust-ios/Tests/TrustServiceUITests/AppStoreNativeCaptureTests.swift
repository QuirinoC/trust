import Foundation
import UIKit
import XCTest

/// Host-coordinated physical-display captures of existing demo routes. No app action is submitted.
final class AppStoreNativeCaptureTests: XCTestCase {
    private var captureURL: URL!
    private var continueURL: URL!
    private var scenario: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["TRUST_STORE_CAPTURE_DIR"], !dir.isEmpty,
              let selected = env["TRUST_STORE_CAPTURE_SCENARIO"],
              ["hero-live", "look-expanded", "paywall-real-catalog", "tall-map-fallback",
               "gps-map-camera", "denied-map-recenter"].contains(selected) else {
            throw XCTSkip("Set TRUST_STORE_CAPTURE_DIR and TRUST_STORE_CAPTURE_SCENARIO to an approved capture scenario.")
        }
        scenario = selected
        if let orientationName = env["TRUST_STORE_CAPTURE_ORIENTATION"] {
            let requestedOrientation: UIDeviceOrientation
            switch orientationName {
            case "portrait": requestedOrientation = .portrait
            case "landscapeLeft": requestedOrientation = .landscapeLeft
            default:
                throw NSError(domain: "AppStoreNativeCaptureTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Unsupported TRUST_STORE_CAPTURE_ORIENTATION: \(orientationName)."])
            }
            let device = XCUIDevice.shared
            if device.orientation != requestedOrientation {
                device.orientation = requestedOrientation
            }
            XCTAssertTrue(waitUntil(10) { device.orientation == requestedOrientation },
                          "Simulator orientation must settle to \(orientationName) before the app launches.")
        }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        captureURL = folder.appendingPathComponent("ready.json")
        continueURL = folder.appendingPathComponent("continue")
        try? FileManager.default.removeItem(at: captureURL)
        try? FileManager.default.removeItem(at: continueURL)
    }

    func testHeroLivePeople() throws {
        guard scenario == "hero-live" else { throw XCTSkip("Selected capture scenario is not hero-live.") }
        let app = launch(route: "share")
        navigateToPeople(app)
        let header = app.descendants(matching: .any)["people-map-header"]
        let peopleList = app.scrollViews["people-list"]
        let peopleHeading = app.staticTexts.matching(NSPredicate(format: "label == %@", "People")).firstMatch
        let mapCanvas = app.descendants(matching: .any)["people-map-canvas"]
        let isWideLayout = app.windows.firstMatch.frame.width >= 650
        let peopleLayoutReady = {
            isWideLayout
                ? peopleList.exists && peopleHeading.exists && mapCanvas.exists
                : header.exists
        }
        XCTAssertTrue(waitUntil(10, peopleLayoutReady), app.debugDescription)
        let leo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "people-map-pin-", "Leo Park")).firstMatch
        let eli = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "people-map-pin-", "Eli Brooks")).firstMatch
        XCTAssertTrue(leo.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(8) { mapCanvas.frame.width > 0 && mapCanvas.frame.height > 0 }, app.debugDescription)
        let isTallWideMap = isWideLayout && mapCanvas.frame.height / max(mapCanvas.frame.width, 1) > 1.5
        assertLivePinMetadata(leo, person: "Leo Park")
        XCTAssertTrue(waitUntil(10) { isFullyVisible(leo.frame, in: mapCanvas.frame) && leo.isHittable }, app.debugDescription)
        assertPin(leo, fullyInside: mapCanvas, description: "Leo's complete live pin must be inside the People map.")
        XCTAssertTrue(leo.isHittable, "Leo's live pin must be hittable.")
        var payload: [String: Any] = ["scene": "People", "window": rect(app.windows.firstMatch.frame),
            "leo": element(leo)]
        if isWideLayout {
            payload["peopleHeading"] = element(peopleHeading)
            payload["peopleList"] = element(peopleList)
            payload["peopleMapCanvas"] = element(mapCanvas)
            payload["tallMap"] = isTallWideMap
        } else {
            payload["peopleHeader"] = element(header)
        }
        if isTallWideMap {
            let eliRow = app.buttons["person-row-eli"]
            let eliView = app.buttons["person-peek-eli"]
            XCTAssertTrue(eliRow.waitForExistence(timeout: 8), app.debugDescription)
            XCTAssertTrue(eliView.waitForExistence(timeout: 8), app.debugDescription)
            assertRowMetadata(eliRow, person: "Eli Brooks")
            XCTAssertTrue(eliRow.isHittable && eliView.isHittable, "Eli's People row and View action must remain visible and hittable in the tall wide layout.")
            XCTAssertTrue(isFullyVisible(eliRow.frame, in: app.windows.firstMatch.frame), "Eli's row must be fully visible in the window.")
            XCTAssertTrue(eliView.label.localizedCaseInsensitiveContains("View Eli"), "Eli's View action must name him.")
            payload["eliRow"] = element(eliRow)
            payload["eliViewAction"] = element(eliView)
            if eli.exists && isFullyVisible(eli.frame, in: mapCanvas.frame) {
                payload["eliPin"] = element(eli)
            }
        } else {
            XCTAssertTrue(eli.waitForExistence(timeout: 10), app.debugDescription)
            assertLivePinMetadata(eli, person: "Eli Brooks")
            assertPin(eli, fullyInside: mapCanvas, description: "Eli's complete live pin must be inside the People map.")
            XCTAssertTrue(eli.isHittable, "Eli's live pin must remain hittable in non-tall layouts.")
            payload["eli"] = element(eli)
        }
        try publishAndWait(app, payload: payload)
    }

    func testTallMapFallbackPreservesPersonNavigationAndActions() throws {
        guard scenario == "tall-map-fallback" else { throw XCTSkip("Selected capture scenario is not tall-map-fallback.") }
        let app = launch(route: "share")
        navigateToPeople(app)

        let mapCanvas = app.descendants(matching: .any)["people-map-canvas"]
        XCTAssertTrue(mapCanvas.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(8) { mapCanvas.frame.width > 0 && mapCanvas.frame.height > 0 })
        XCTAssertGreaterThanOrEqual(app.windows.firstMatch.frame.width, 650, "This acceptance case requires the wide People layout.")
        XCTAssertGreaterThan(mapCanvas.frame.height / max(mapCanvas.frame.width, 1), 1.5, "This acceptance case requires the tall leading map pane.")

        let leoPin = livePin(in: app, named: "Leo Park")
        XCTAssertTrue(leoPin.waitForExistence(timeout: 10), app.debugDescription)
        assertLivePinMetadata(leoPin, person: "Leo Park")
        XCTAssertTrue(waitUntil(10) { isFullyVisible(leoPin.frame, in: mapCanvas.frame) && leoPin.isHittable }, app.debugDescription)
        assertPin(leoPin, fullyInside: mapCanvas, description: "Leo's complete live pin and freshness label must fit inside the tall map pane.")
        XCTAssertTrue(leoPin.isHittable, "Leo's complete live pin must be hittable in the tall map pane.")
        let leoFreshness = freshnessPhrase(in: leoPin.label)
        XCTAssertNotNil(leoFreshness)

        // A single normal UI tap on the native pin opens the real Leo View,
        // without a route shortcut or repeat tap.
        leoPin.tap()
        let directions = app.staticTexts["person-sharing-directions"]
        XCTAssertTrue(directions.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Leo"].waitForExistence(timeout: 5), "The pin must open Leo's real View.")
        let freshness = app.staticTexts["view-location-freshness"]
        XCTAssertTrue(freshness.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(freshnessPhraseMatches(freshness.label, expected: leoFreshness), "Leo's View must show the same live freshness metadata as his pin.")

        let back = app.buttons["circle-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        let eliRow = app.buttons["person-row-eli"]
        let eliView = app.buttons["person-peek-eli"]
        XCTAssertTrue(eliRow.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(eliView.waitForExistence(timeout: 8), app.debugDescription)
        assertRowMetadata(eliRow, person: "Eli Brooks")
        XCTAssertTrue(eliRow.isHittable && eliView.isHittable, "Eli's row and View action must remain visible and hittable.")
        XCTAssertTrue(eliView.label.localizedCaseInsensitiveContains("View Eli"), "The action must identify Eli.")
        let eliRowFrame = rect(eliRow.frame)
        let eliViewActionFrame = rect(eliView.frame)
        eliView.tap()

        XCTAssertTrue(directions.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Eli"].waitForExistence(timeout: 5), "Eli's row action must open Eli's real View.")
        XCTAssertTrue(freshness.waitForExistence(timeout: 8), app.debugDescription)
        let eliPin = livePin(in: app, named: "Eli Brooks")
        XCTAssertTrue(eliPin.waitForExistence(timeout: 8), "Eli's current live pin must remain on the leading map while his View is selected.\n\(app.debugDescription)")
        assertLivePinMetadata(eliPin, person: "Eli Brooks")
        XCTAssertTrue(waitUntil(10) { isFullyVisible(eliPin.frame, in: mapCanvas.frame) && eliPin.isHittable }, app.debugDescription)
        assertPin(eliPin, fullyInside: mapCanvas, description: "Eli's complete live pin must fit inside the leading map while his View is selected.")
        XCTAssertTrue(eliPin.isHittable, "Eli's live pin must remain hittable while his View is selected.")
        let eliFreshness = freshnessPhrase(in: eliPin.label)
        XCTAssertNotNil(eliFreshness)
        XCTAssertTrue(freshnessPhraseMatches(freshness.label, expected: eliFreshness), "Eli's View must show the same live freshness metadata as his pin.")

        let witness = XCTAttachment(screenshot: app.screenshot())
        witness.name = "Tall People map fallback - Eli View with complete leading-map pin"
        witness.lifetime = .keepAlways
        add(witness)
        let geometry = XCTAttachment(string: "mapCanvas=\(rect(mapCanvas.frame)); Eli pin=\(rect(eliPin.frame)); Eli row=\(eliRowFrame); Eli View action=\(eliViewActionFrame); Eli pin label=\(eliPin.label); View freshness=\(freshness.label)")
        geometry.name = "Tall People map fallback geometry and freshness"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    func testGPSMapCameraKeepsPinsVisibleAndPreservesManualPan() throws {
        guard scenario == "gps-map-camera" else { throw XCTSkip("Selected scenario is not gps-map-camera.") }
        // The host runner owns setup: tall iPad, San Francisco simulated fix, and pre-granted location.
        let app = launch(route: "share")
        navigateToPeople(app)

        let window = app.windows.firstMatch
        let mapCanvas = app.descendants(matching: .any)["people-map-canvas"]
        XCTAssertTrue(mapCanvas.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(8) { mapCanvas.frame.width > 0 && mapCanvas.frame.height > 0 })
        attachMapEvidence("GPS map camera - initial viewport", app: app, mapCanvas: mapCanvas, pins: [])
        XCTAssertEqual(window.frame.width, 1032, accuracy: 2, "Run this case on the tall iPad simulator.")
        XCTAssertEqual(window.frame.height, 1376, accuracy: 2, "Run this case on the tall iPad simulator.")
        XCTAssertEqual(mapCanvas.frame.width, 660, accuracy: 3, "The leading People map should use the tall iPad viewport.")
        XCTAssertEqual(mapCanvas.frame.height, 1288, accuracy: 3, "The leading People map should use the tall iPad viewport.")

        let leo = livePin(in: app, named: "Leo Park")
        let eli = livePin(in: app, named: "Eli Brooks")
        XCTAssertTrue(leo.waitForExistence(timeout: 10), app.debugDescription)
        assertLivePinMetadata(leo, person: "Leo Park")
        XCTAssertTrue(waitUntil(10) { isFullyVisible(leo.frame, in: mapCanvas.frame) && leo.isHittable }, app.debugDescription)
        assertPin(leo, fullyInside: mapCanvas, description: "Leo's full live pin and freshness label must fit the 660×1288 map.")
        XCTAssertEqual(pinMatches(in: app, named: "Leo Park").count, 1, "There must be one Leo pin before the native pin tap.")
        attachMapEvidence("GPS map camera - initial San Francisco fix", app: app, mapCanvas: mapCanvas, pins: [leo, eli])
        var initialPayload: [String: Any] = ["scene": "GPS People map", "window": rect(window.frame),
            "mapCanvas": rect(mapCanvas.frame), "leo": element(leo)]
        if eli.exists { initialPayload["eli"] = element(eli) }
        try publishAndWait(app, payload: initialPayload)

        // A single native pin tap must open the actual selected person's View.
        leo.tap()
        let directions = app.staticTexts["person-sharing-directions"]
        let freshness = app.staticTexts["view-location-freshness"]
        XCTAssertTrue(directions.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Leo"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(freshness.waitForExistence(timeout: 8), app.debugDescription)
        let leoFreshness = freshnessPhrase(in: leo.label)
        XCTAssertNotNil(leoFreshness)
        XCTAssertTrue(freshnessPhraseMatches(freshness.label, expected: leoFreshness), "Leo's View must retain the live freshness shown on his pin.")
        attachMapEvidence("GPS map camera - Leo View", app: app, mapCanvas: mapCanvas, pins: [leo, eli])
        app.buttons["circle-back"].tap()

        let eliRow = app.buttons["person-row-eli"]
        let eliView = app.buttons["person-peek-eli"]
        XCTAssertTrue(eliRow.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(eliView.waitForExistence(timeout: 8), app.debugDescription)
        assertRowMetadata(eliRow, person: "Eli Brooks")
        XCTAssertTrue(eliRow.isHittable && eliView.isHittable, app.debugDescription)
        eliView.tap()
        XCTAssertTrue(directions.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Eli"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(freshness.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(waitUntil(10) { isFullyVisible(eli.frame, in: mapCanvas.frame) && eli.isHittable }, app.debugDescription)
        assertLivePinMetadata(eli, person: "Eli Brooks")
        let eliFreshness = freshnessPhrase(in: eli.label)
        XCTAssertNotNil(eliFreshness)
        XCTAssertTrue(freshnessPhraseMatches(freshness.label, expected: eliFreshness), "Eli's View must retain the live freshness shown on his pin.")
        attachMapEvidence("GPS map camera - Eli View", app: app, mapCanvas: mapCanvas, pins: [leo, eli])
        app.buttons["circle-back"].tap()

        let myLocation = nativeUserLocation(in: mapCanvas)
        try hostGPSStage("gps-nearby", app: app, mapCanvas: mapCanvas, pins: [leo, eli], myLocation: myLocation)
        XCTAssertTrue(waitUntil(12) {
            myLocation.exists && isFullyVisible(myLocation.frame, in: mapCanvas.frame)
                && isFullyVisible(leo.frame, in: mapCanvas.frame) && leo.isHittable
        }, "After the host moves the simulated fix to Seattle, MapKit's native My Location and Leo's complete pin must both fit inside the map.\n\(app.debugDescription)")
        assertLivePinMetadata(leo, person: "Leo Park")
        assertPin(leo, fullyInside: mapCanvas, description: "Leo must remain complete and hittable after the host moves this iPad's simulated fix to Seattle.")

        let recenter = app.buttons.matching(NSPredicate(format: "label == %@", "Recenter map")).firstMatch
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "The map's current Recenter map control must be available.\n\(app.debugDescription)")
        XCTAssertTrue(waitForRecenterHittable(recenter, app: app, mapCanvas: mapCanvas,
                                               checkpoint: "Seattle nearby recovery"), app.debugDescription)
        recenter.tap()
        XCTAssertTrue(waitForStableVisibleFrame(leo, within: mapCanvas, timeout: 12, stableDuration: 0.6) {
            myLocation.exists && self.isFullyVisible(myLocation.frame, in: mapCanvas.frame)
        }, "Recenter with the nearby Seattle fix must retain both MapKit's own-location marker and Leo's complete pin, with Leo's frame settled.\n\(app.debugDescription)")
        assertPin(leo, fullyInside: mapCanvas, description: "Recenter with the nearby Seattle fix must keep Leo's complete live pin visible.")
        attachMapEvidence("GPS map camera - Seattle fix and public Recenter", app: app, mapCanvas: mapCanvas, pins: [leo, eli, myLocation])

        let leoBeforePan = leo.frame
        let panStart = mapCanvas.coordinate(withNormalizedOffset: CGVector(dx: 0.24, dy: 0.32))
        let panEnd = mapCanvas.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.34))
        panStart.press(forDuration: 0.1, thenDragTo: panEnd)
        var settledPanFrame: CGRect?
        var panFrameStableSince: Date?
        XCTAssertTrue(waitUntil(8) {
            guard isFullyVisible(leo.frame, in: mapCanvas.frame), leo.isHittable,
                  frameDistance(leo.frame, before: leoBeforePan) > 8,
                  myLocation.exists, isFullyVisible(myLocation.frame, in: mapCanvas.frame) else {
                settledPanFrame = nil
                panFrameStableSince = nil
                return false
            }
            let currentFrame = leo.frame
            if let previousFrame = settledPanFrame,
               frameDistance(currentFrame, before: previousFrame) <= 1,
               let stableSince = panFrameStableSince {
                return Date().timeIntervalSince(stableSince) >= 0.6
            }
            settledPanFrame = currentFrame
            panFrameStableSince = Date()
            return false
        }, "The native pan must move Leo while keeping MapKit's own-location marker visible, then settle for 0.6 seconds before recording its frame.\n\(app.debugDescription)")
        let leoAfterPan = leo.frame
        XCTAssertGreaterThan(frameDistance(leoAfterPan, before: leoBeforePan), 8,
                             "A native map pan must move Leo's screen position before testing pan preservation.")
        attachMapEvidence("GPS map camera - after manual pan", app: app, mapCanvas: mapCanvas, pins: [leo, eli, myLocation])

        let locationBeforePanStage = myLocation.frame
        try hostGPSStage("gps-far", app: app, mapCanvas: mapCanvas, pins: [leo, eli], myLocation: myLocation)
        XCTAssertTrue(waitUntil(12) {
            (!myLocation.exists || frameDistance(myLocation.frame, before: locationBeforePanStage) >= 12)
                && isFullyVisible(leo.frame, in: mapCanvas.frame)
                && frameDistance(leo.frame, before: leoAfterPan) <= 5
        }, "After the host restores the far San Francisco fix, the manually panned map must keep Leo at the same screen position while MapKit moves or removes its off-screen native location marker.\n\(app.debugDescription)")
        XCTAssertTrue(leo.isHittable)
        attachMapEvidence("GPS map camera - manual pan retained after far fix", app: app, mapCanvas: mapCanvas, pins: [leo, eli, myLocation])

        recenter.tap()
        XCTAssertTrue(waitUntil(12) {
            myLocation.exists && isFullyVisible(myLocation.frame, in: mapCanvas.frame)
        }, "Public Recenter must bring MapKit's actual My Location annotation into the People map after the far fix.\n\(app.debugDescription)")
        attachMapEvidence("GPS map camera - native My Location after far Recenter", app: app, mapCanvas: mapCanvas, pins: [leo, eli, myLocation])
    }

    func testDeniedMapRecenterPreservesPeoplePinNavigation() throws {
        guard scenario == "denied-map-recenter" else { throw XCTSkip("Selected scenario is not denied-map-recenter.") }
        let app = launch(route: "share")
        navigateToPeople(app)
        let window = app.windows.firstMatch
        let mapCanvas = app.descendants(matching: .any)["people-map-canvas"]
        XCTAssertTrue(mapCanvas.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitUntil(8) { mapCanvas.frame.width > 0 && mapCanvas.frame.height > 0 })
        attachMapEvidence("Denied location - initial People map", app: app, mapCanvas: mapCanvas, pins: [])
        XCTAssertGreaterThanOrEqual(window.frame.width, 650, "Run this case on the tall leading-map layout.")
        XCTAssertGreaterThan(mapCanvas.frame.height / max(mapCanvas.frame.width, 1), 1.5,
                             "Run this case on the tall leading-map layout.")

        let leo = livePin(in: app, named: "Leo Park")
        XCTAssertTrue(leo.waitForExistence(timeout: 10), app.debugDescription)
        assertLivePinMetadata(leo, person: "Leo Park")
        XCTAssertTrue(waitUntil(10) { isFullyVisible(leo.frame, in: mapCanvas.frame) && leo.isHittable }, app.debugDescription)
        XCTAssertEqual(pinMatches(in: app, named: "Leo Park").count, 1, "There must be one Leo pin before Recenter.")

        let recenter = app.buttons.matching(NSPredicate(format: "label == %@", "Recenter map")).firstMatch
        XCTAssertTrue(recenter.waitForExistence(timeout: 5), "The map's current Recenter map control must be available.\n\(app.debugDescription)")
        XCTAssertTrue(waitForRecenterHittable(recenter, app: app, mapCanvas: mapCanvas,
                                               checkpoint: "Denied location"), app.debugDescription)
        recenter.tap()
        XCTAssertTrue(waitForStableVisibleFrame(leo, within: mapCanvas, timeout: 10, stableDuration: 0.6),
                      "Denied location must not displace the authorized Leo pin after Recenter, and Leo's frame must settle before the pin tap.\n\(app.debugDescription)")
        assertPin(leo, fullyInside: mapCanvas, description: "The complete Leo pin must remain on the People map when own location is denied.")
        attachMapEvidence("Denied location - map after Recenter", app: app, mapCanvas: mapCanvas, pins: [leo])

        leo.tap()
        XCTAssertTrue(app.staticTexts["person-sharing-directions"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Leo"].waitForExistence(timeout: 5), "One native pin tap must open Leo's real View.\n\(app.debugDescription)")
        try publishAndWait(app, payload: ["scene": "Denied location Recenter preserves People navigation",
            "window": rect(window.frame), "mapCanvas": rect(mapCanvas.frame)])
    }

    func testLookExpandedConsentSheet() throws {
        guard scenario == "look-expanded" else { throw XCTSkip("Selected capture scenario is not look-expanded.") }
        let app = launch(route: "look")
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Trust records this Look")).firstMatch
        let action = app.buttons["confirm-look-notify"]
        let cancel = app.buttons["cancel-look"]
        let heading = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Look at")).firstMatch
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Close")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(action.waitForExistence(timeout: 5) && cancel.exists && heading.exists && close.exists, app.debugDescription)
        let windowElement = app.windows.firstMatch
        let window = windowElement.frame
        guard let textScrollView = textViewport(in: app, containing: note) else {
            XCTFail("The consent text must belong to a visible scroll viewport.")
            return
        }
        if !fullyAboveActions(note, heading: heading, action: action, cancel: cancel,
                              viewport: textScrollView.frame, window: window) {
            let dy = max(0.05, min(0.95, (close.frame.minY - window.minY - 8) / window.height))
            let start = windowElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy))
            let top = windowElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03))
            start.press(forDuration: 0.1, thenDragTo: top)
        }
        XCTAssertTrue(waitUntil(8) { fullyAboveActions(note, heading: heading, action: action, cancel: cancel,
            viewport: textScrollView.frame, window: windowElement.frame) },
                      "The consent heading and full note must be visible above the fixed actions.")
        XCTAssertTrue(action.isHittable && cancel.isHittable)
        XCTAssertTrue(action.exists, "Capture must not submit the Look action.")
        try publishAndWait(app, payload: ["scene": "Look confirmation", "window": rect(app.windows.firstMatch.frame),
            "textViewport": rect(textScrollView.frame),
            "heading": element(heading), "note": element(note), "confirmAction": element(action), "cancelAction": element(cancel)])
    }

    func testPaywallRealCatalog() throws {
        guard scenario == "paywall-real-catalog" else { throw XCTSkip("Selected capture scenario is not paywall-real-catalog.") }
        let app = launch(route: "paywall")
        let store = app.descendants(matching: .any)["plus-subscription-store"]
        let close = app.buttons["plus-close"]
        var monthly: XCUIElement?
        var annual: XCUIElement?
        let catalogReady = waitUntil(30) {
            monthly = priceBearingOption(in: app, period: .monthly)
            annual = priceBearingOption(in: app, period: .annual)
            return store.exists && close.exists && close.isHittable
                && monthly?.isHittable == true && annual?.isHittable == true
        }
        XCTAssertTrue(catalogReady, app.debugDescription)
        guard let monthly, let annual else { return }
        try publishAndWait(app, payload: ["scene": "Trust Plus", "window": rect(app.windows.firstMatch.frame),
            "subscriptionStore": element(store), "monthlyOption": element(monthly),
            "annualOption": element(annual), "close": element(close)])
    }

    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.collapsetechnologies.trust")
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_SCREENSHOT"] = route
        app.launchArguments += ["-trust.appLanguage", "en"]
        app.launch()
        return app
    }

    private func navigateToPeople(_ app: XCUIApplication) {
        let sharingTab = app.buttons["tab-sharing"]
        let peopleTab = app.buttons["tab-circle"]
        let sharingBody = app.scrollViews["sharing-scroll"]
        let sharingIntro = app.staticTexts["sharing-intro"]
        var previousScrollFrame: CGRect?
        var previousIntroFrame: CGRect?
        var stableSince: TimeInterval?
        let sharingRouteReady = waitUntil(15) {
            guard sharingTab.exists && sharingTab.isSelected && sharingTab.isHittable
                    && sharingBody.exists && sharingBody.isHittable
                    && sharingIntro.exists && sharingIntro.isHittable
                    && !sharingBody.frame.isEmpty && !sharingIntro.frame.isEmpty else {
                previousScrollFrame = nil
                previousIntroFrame = nil
                stableSince = nil
                return false
            }
            let scrollFrame = sharingBody.frame
            let introFrame = sharingIntro.frame
            if previousScrollFrame != scrollFrame || previousIntroFrame != introFrame {
                previousScrollFrame = scrollFrame
                previousIntroFrame = introFrame
                stableSince = ProcessInfo.processInfo.systemUptime
                return false
            }
            return ProcessInfo.processInfo.systemUptime - (stableSince ?? ProcessInfo.processInfo.systemUptime) >= 0.4
        }
        XCTAssertTrue(sharingRouteReady, "The launch-requested Sharing screen must be selected and stable before navigation.\n\(app.debugDescription)")

        let mapCanvas = app.descendants(matching: .any)["people-map-canvas"]
        let header = app.descendants(matching: .any)["people-map-header"]
        let peopleList = app.scrollViews["people-list"]
        let peopleHeading = app.staticTexts.matching(NSPredicate(format: "label == %@", "People")).firstMatch
        let isWideLayout = app.windows.firstMatch.frame.width >= 650
        let peopleBodyReady = {
            guard peopleTab.exists && peopleTab.isSelected && peopleTab.isHittable
                    && mapCanvas.exists && mapCanvas.isHittable else { return false }
            return isWideLayout
                ? peopleList.exists && peopleList.isHittable && peopleHeading.exists && peopleHeading.isHittable
                : header.exists && header.isHittable
        }

        XCTAssertTrue(waitUntil(5, { peopleTab.exists && peopleTab.isHittable }), app.debugDescription)
        peopleTab.tap()
        var ready = waitUntil(10, peopleBodyReady)
        if !ready && sharingTab.exists && sharingTab.isSelected && sharingTab.isHittable
                && sharingBody.exists && sharingBody.isHittable && peopleTab.isHittable {
            peopleTab.tap()
            ready = waitUntil(10, peopleBodyReady)
        }
        XCTAssertTrue(ready, "People navigation must settle on its visible native layout.\n\(app.debugDescription)")
    }

    private func livePin(in app: XCUIApplication, named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "people-map-pin-", name
        )).firstMatch
    }

    private func pinMatches(in app: XCUIApplication, named name: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@",
            "people-map-pin-", name
        ))
    }

    private func nativeUserLocation(in mapCanvas: XCUIElement) -> XCUIElement {
        // This is MapKit's UserAnnotation label, observed in native accessibility output.
        mapCanvas.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "My Location")).firstMatch
    }

    private func hostGPSStage(_ name: String, app: XCUIApplication, mapCanvas: XCUIElement,
                              pins: [XCUIElement], myLocation: XCUIElement? = nil) throws {
        let markerDirectory = captureURL.deletingLastPathComponent()
        let ready = markerDirectory.appendingPathComponent("\(name).ready")
        let proceed = markerDirectory.appendingPathComponent("\(name).continue")
        try? FileManager.default.removeItem(at: ready)
        try? FileManager.default.removeItem(at: proceed)
        var payload: [String: Any] = ["stage": name, "window": rect(app.windows.firstMatch.frame),
            "mapCanvas": rect(mapCanvas.frame), "pins": pins.filter { $0.exists }.map { element($0) }]
        if let myLocation, myLocation.exists { payload["nativeUserLocation"] = element(myLocation) }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: ready, options: .atomic)
        XCTAssertTrue(waitUntil(35) { FileManager.default.fileExists(atPath: proceed.path) },
                      "Host did not apply the requested simulated GPS update for \(name) within 35 seconds.\n\(app.debugDescription)")
    }

    private func attachMapEvidence(_ name: String, app: XCUIApplication, mapCanvas: XCUIElement,
                                   pins: [XCUIElement]) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        var lines = ["window=\(rect(app.windows.firstMatch.frame))", "mapCanvas=\(rect(mapCanvas.frame))"]
        for pin in pins where pin.exists {
            lines.append("element=\(pin.identifier) frame=\(rect(pin.frame)) label=\(pin.label)")
        }
        let geometry = XCTAttachment(string: lines.joined(separator: "\n"))
        geometry.name = "\(name) geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func waitForRecenterHittable(_ recenter: XCUIElement, app: XCUIApplication,
                                         mapCanvas: XCUIElement, checkpoint: String) -> Bool {
        guard waitUntil(5, { recenter.exists && recenter.isHittable }) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(checkpoint) - Recenter not hittable"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let controls = app.buttons.matching(NSPredicate(format: "label == %@", "Recenter map"))
            var lines = ["checkpoint=\(checkpoint)", "window=\(rect(app.windows.firstMatch.frame))",
                         "mapCanvas=\(rect(mapCanvas.frame))"]
            for (index, control) in controls.allElementsBoundByIndex.enumerated() {
                lines.append("recenter[\(index)] exists=\(control.exists) enabled=\(control.isEnabled) hittable=\(control.isHittable) frame=\(rect(control.frame)) label=\(control.label) identifier=\(control.identifier)")
            }
            lines.append("matchingRecenterCount=\(controls.count)")
            let geometry = XCTAttachment(string: lines.joined(separator: "\n"))
            geometry.name = "\(checkpoint) - Recenter control geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
            return false
        }
        return true
    }

    private func waitForStableVisibleFrame(_ element: XCUIElement, within container: XCUIElement,
                                           timeout: TimeInterval, stableDuration: TimeInterval,
                                           additionalCondition: (() -> Bool)? = nil) -> Bool {
        var previousFrame: CGRect?
        var stableSince: Date?
        return waitUntil(timeout) {
            guard (additionalCondition?() ?? true),
                  isFullyVisible(element.frame, in: container.frame), element.isHittable else {
                previousFrame = nil
                stableSince = nil
                return false
            }
            let currentFrame = element.frame
            if let previousFrame,
               frameDistance(currentFrame, before: previousFrame) <= 1,
               let stableSince {
                return Date().timeIntervalSince(stableSince) >= stableDuration
            }
            previousFrame = currentFrame
            stableSince = Date()
            return false
        }
    }

    private func frameDistance(_ frame: CGRect, before previous: CGRect) -> CGFloat {
        hypot(frame.midX - previous.midX, frame.midY - previous.midY)
    }

    private func assertLivePinMetadata(_ pin: XCUIElement, person: String,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pin.label.localizedCaseInsensitiveContains(person), "Live pin must identify \(person).", file: file, line: line)
        XCTAssertNotNil(freshnessPhrase(in: pin.label), "Live pin must expose current freshness metadata: \(pin.label)", file: file, line: line)
    }

    private func assertRowMetadata(_ row: XCUIElement, person: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(row.label.localizedCaseInsensitiveContains(person), "People row must identify \(person).", file: file, line: line)
        XCTAssertTrue(row.label.contains("Updated") || row.label.contains("May be out of date"),
                      "People row must expose the live location freshness metadata: \(row.label)", file: file, line: line)
    }

    private func assertPin(_ pin: XCUIElement, fullyInside map: XCUIElement, description: String,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(isFullyVisible(pin.frame, in: map.frame),
                      "\(description) pin=\(rect(pin.frame)); map=\(rect(map.frame))",
                      file: file, line: line)
    }

    private func isFullyVisible(_ item: CGRect, in container: CGRect) -> Bool {
        !item.isEmpty && !container.isEmpty
            && item.minX >= container.minX - 1 && item.maxX <= container.maxX + 1
            && item.minY >= container.minY - 1 && item.maxY <= container.maxY + 1
    }

    private func freshnessPhrase(in label: String) -> String? {
        guard let comma = label.firstIndex(of: ",") else { return nil }
        let phrase = label[label.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard phrase.contains("Updated") || phrase.contains("May be out of date") else { return nil }
        return phrase
    }

    private func freshnessPhraseMatches(_ label: String, expected: String?) -> Bool {
        guard let expected else { return false }
        return label.localizedCaseInsensitiveContains(expected)
    }

    private func publishAndWait(_ app: XCUIApplication, payload: [String: Any]) throws {
        var ready = payload
        ready["scenario"] = scenario
        ready["appFrame"] = rect(app.frame)
        try JSONSerialization.data(withJSONObject: ready, options: [.sortedKeys]).write(to: captureURL, options: .atomic)
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline && !FileManager.default.fileExists(atPath: continueURL.path) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: continueURL.path), "Host capture did not signal continue within 40 seconds.")
    }

    private func textViewport(in app: XCUIApplication, containing note: XCUIElement) -> XCUIElement? {
        app.scrollViews.allElementsBoundByIndex
            .filter { $0.frame.contains(CGPoint(x: note.frame.midX, y: note.frame.midY)) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    private func fullyAboveActions(_ note: XCUIElement, heading: XCUIElement, action: XCUIElement,
                                   cancel: XCUIElement, viewport: CGRect, window: CGRect) -> Bool {
        let visible = viewport.intersection(window)
        func fullyVisible(_ frame: CGRect) -> Bool {
            !visible.isNull && frame.minX >= visible.minX && frame.maxX <= visible.maxX
                && frame.minY >= visible.minY && frame.maxY <= visible.maxY
        }
        return note.exists && heading.exists && action.exists && cancel.exists
            && fullyVisible(heading.frame) && fullyVisible(note.frame) && note.isHittable && heading.isHittable
            && action.isHittable && cancel.isHittable && note.frame.maxY <= action.frame.minY
            && action.frame.maxY <= cancel.frame.minY
    }

    private enum SubscriptionPeriod {
        case monthly
        case annual
    }

    private func priceBearingOption(in app: XCUIApplication, period: SubscriptionPeriod) -> XCUIElement? {
        app.buttons.allElementsBoundByIndex.first { button in
            guard button.exists, button.isHittable, hasStorePrice(button.label) else { return false }
            let label = button.label.lowercased()
            switch period {
            case .monthly: return label.contains("month")
            case .annual: return label.contains("year") || label.contains("annual")
            }
        }
    }

    private func hasStorePrice(_ label: String) -> Bool {
        let hasAmount = label.range(of: #"\d+(?:[.,]\d{1,2})?"#, options: .regularExpression) != nil
        let hasCurrencySymbol = label.range(of: #"\p{Sc}"#, options: .regularExpression) != nil
        let hasCurrencyCode = label.range(of: #"\b[A-Z]{3}\b"#, options: .regularExpression) != nil
        return hasAmount && (hasCurrencySymbol || hasCurrencyCode)
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { if condition() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return condition()
    }

    private func rect(_ r: CGRect) -> [String: Double] { ["x": Double(r.minX), "y": Double(r.minY), "width": Double(r.width), "height": Double(r.height)] }
    private func element(_ e: XCUIElement) -> [String: Any] { ["label": e.label, "identifier": e.identifier, "frame": rect(e.frame)] }
}
