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
              ["hero-live", "look-expanded"].contains(selected) else {
            throw XCTSkip("Set TRUST_STORE_CAPTURE_DIR and TRUST_STORE_CAPTURE_SCENARIO to an approved capture scenario.")
        }
        scenario = selected
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
        let peopleTab = app.buttons["tab-circle"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: 15))
        peopleTab.tap()
        XCTAssertTrue(peopleTab.isSelected)
        let header = app.descendants(matching: .any)["people-map-header"]
        if !header.waitForExistence(timeout: 10) {
            let sharingTab = app.buttons["tab-sharing"]
            if !header.exists && sharingTab.exists && sharingTab.isSelected && peopleTab.isHittable {
                peopleTab.tap()
            }
        }
        XCTAssertTrue(header.waitForExistence(timeout: 10), app.debugDescription)
        let leo = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "people-map-pin-", "Leo Park")).firstMatch
        let eli = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "people-map-pin-", "Eli Brooks")).firstMatch
        XCTAssertTrue(leo.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(eli.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(leo.isHittable && eli.isHittable)
        try publishAndWait(app, payload: ["scene": "People", "window": rect(app.windows.firstMatch.frame),
            "leo": element(leo), "eli": element(eli), "peopleHeader": element(header)])
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

    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.collapsetechnologies.trust")
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_SCREENSHOT"] = route
        app.launchArguments += ["-trust.appLanguage", "en"]
        app.launch()
        return app
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

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline { if condition() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
        return condition()
    }

    private func rect(_ r: CGRect) -> [String: Double] { ["x": Double(r.minX), "y": Double(r.minY), "width": Double(r.width), "height": Double(r.height)] }
    private func element(_ e: XCUIElement) -> [String: Any] { ["label": e.label, "identifier": e.identifier, "frame": rect(e.frame)] }
}
