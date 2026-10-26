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
                XCTAssertGreaterThanOrEqual(handle.frame.height, 44 - 1e-6)
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

    /// Opt-in simulated Duo sweep. A host orchestrator watches the ready files in
    /// TRUST_DUO_SWEEP_DIR, changes the simulator's fold state, then creates the
    /// matching continue file. Files are used instead of timing sleeps so XCTest
    /// samples the real app after the display has settled.
    ///
    /// Protocol: wait for closed.ready, open Duo and create open.continue; wait
    /// for selected.ready, close Duo and create folded.continue; wait for
    /// folded.ready, reopen Duo and create reopened.continue. After the View map
    /// opens, repeat with map-folded.continue/map-reopened.continue. XCTest has
    /// bounded waits at every handoff and leaves geometry/screenshots in failure output.
    func testOptInDuoFoldTransitionPreservesPeopleNavigation() throws {
        guard let directory = ProcessInfo.processInfo.environment["TRUST_DUO_SWEEP_DIR"],
              !directory.isEmpty else {
            throw XCTSkip("Requires TRUST_DUO_SWEEP_DIR and a host fold-state orchestrator.")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for name in ["closed.ready", "open.continue", "selected.ready", "folded.continue",
                     "folded.ready", "reopened.continue", "map-open.ready",
                     "map-folded.continue", "map-folded.ready", "map-reopened.continue"] {
            try? fileManager.removeItem(atPath: URL(fileURLWithPath: directory).appendingPathComponent(name).path)
        }

        func mark(_ name: String, app: XCUIApplication) throws {
            let map = app.descendants(matching: .any)["people-map-canvas"]
            let detail = app.staticTexts["person-sharing-directions"]
            let row = app.buttons["person-row-maya"]
            func frameDescription(_ element: XCUIElement) -> String {
                element.exists ? String(describing: element.frame) : "<absent>"
            }
            let snapshot = "\(name)\napp=\(app.frame)\nmap=\(frameDescription(map))\n"
                + "detail=\(frameDescription(detail))\n"
                + "row=\(frameDescription(row))\n"
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            try snapshot.write(to: url, atomically: true, encoding: .utf8)
            FileHandle.standardOutput.write(Data("DUO_SWEEP \(name)\n".utf8))
        }

        func waitFor(_ name: String, app: XCUIApplication, timeout: TimeInterval = 75,
                     file: StaticString = #filePath, line: UInt = #line) -> Bool {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if fileManager.fileExists(atPath: url.path) { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
            let peopleMap = app.descendants(matching: .any)["people-map-canvas"]
            let evidence = "Timed out waiting for host handoff '\(name)'. app=\(app.frame); "
                + "peopleMap=\(peopleMap.exists ? String(describing: peopleMap.frame) : "<absent>"); "
                + "detail=\(app.staticTexts["person-sharing-directions"].exists)"
            XCTFail(evidence, file: file, line: line)
            XCTContext.runActivity(named: "Duo handoff timeout: \(name)") { activity in
                activity.add(XCTAttachment(screenshot: app.screenshot()))
                activity.add(XCTAttachment(string: app.debugDescription))
            }
            return false
        }

        func assertOpenRootGeometry(_ app: XCUIApplication, closedWidth: CGFloat,
                                   file: StaticString = #filePath, line: UInt = #line) {
            let map = app.descendants(matching: .any)["people-map-canvas"]
            let row = app.buttons["person-row-maya"]
            let hasMap = map.waitForExistence(timeout: 8)
            let hasRow = row.waitForExistence(timeout: 8)
            XCTAssertTrue(hasMap, "Open Duo must show the real People map.", file: file, line: line)
            XCTAssertTrue(hasRow, "Open Duo must show the actual People list.", file: file, line: line)
            guard hasMap && hasRow else {
                XCTContext.runActivity(named: "Open Duo People elements missing") { activity in
                    activity.add(XCTAttachment(screenshot: app.screenshot()))
                    activity.add(XCTAttachment(string: app.debugDescription))
                }
                return
            }
            XCTAssertGreaterThan(app.frame.width, closedWidth + 100,
                                 "Opening simulated Duo should expand the actual app content by at least 100pt.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(map.frame.width, 320, "The leading map pane must remain useful.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(row.frame.width, 100, "The actual People row target must remain usable without filling its panel.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "The People row must retain a 44pt hit target.", file: file, line: line)
            XCTAssertTrue(row.isHittable, "The actual People row must remain hittable.", file: file, line: line)
            XCTAssertLessThanOrEqual(map.frame.maxX, row.frame.minX, "The People row must not overlap the map pane.", file: file, line: line)
            if map.frame.width < 320 || row.frame.width < 100 || row.frame.height < 44
                || !row.isHittable || map.frame.maxX > row.frame.minX {
                XCTContext.runActivity(named: "Open Duo People geometry failure") { activity in
                    activity.add(XCTAttachment(screenshot: app.screenshot()))
                    activity.add(XCTAttachment(string: app.debugDescription))
                    activity.add(XCTAttachment(string: "app=\(app.frame); map=\(map.frame); row=\(row.frame)"))
                }
            }
        }

        func assertOpenDetailGeometry(_ app: XCUIApplication, closedWidth: CGFloat,
                                      file: StaticString = #filePath, line: UInt = #line) {
            let map = app.descendants(matching: .any)["people-map-canvas"]
            let detail = app.staticTexts["person-sharing-directions"]
            let hasMap = map.waitForExistence(timeout: 8)
            let hasDetail = detail.waitForExistence(timeout: 8)
            XCTAssertTrue(hasMap, "Open Duo detail must retain the real map.", file: file, line: line)
            XCTAssertTrue(hasDetail, "Open Duo must retain the selected person's detail.", file: file, line: line)
            guard hasMap && hasDetail else {
                XCTContext.runActivity(named: "Open Duo detail elements missing") { activity in
                    activity.add(XCTAttachment(screenshot: app.screenshot()))
                    activity.add(XCTAttachment(string: app.debugDescription))
                }
                return
            }
            XCTAssertGreaterThan(app.frame.width, closedWidth + 100,
                                 "Open Duo content must be wider than the closed state.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(map.frame.width, 320, "The leading map pane must remain useful in detail.", file: file, line: line)
            XCTAssertGreaterThan(detail.frame.width, 0, "Selected-person detail text must have visible geometry.", file: file, line: line)
            XCTAssertTrue(detail.isHittable, "Selected-person detail text must be visually present in the trailing pane.", file: file, line: line)
            XCTAssertLessThanOrEqual(map.frame.maxX, detail.frame.minX + 1,
                                     "Selected-person detail must remain to the right of the leading map.", file: file, line: line)
            if map.frame.width < 320 || detail.frame.width <= 0 || !detail.isHittable || map.frame.maxX > detail.frame.minX + 1 {
                XCTContext.runActivity(named: "Open Duo detail geometry failure") { activity in
                    activity.add(XCTAttachment(screenshot: app.screenshot()))
                    activity.add(XCTAttachment(string: app.debugDescription))
                    activity.add(XCTAttachment(string: "app=\(app.frame); map=\(map.frame); detail=\(detail.frame)"))
                }
            }
        }

        func assertOpenMapRoute(_ app: XCUIApplication, closedWidth: CGFloat,
                                file: StaticString = #filePath, line: UInt = #line) {
            let map = app.descendants(matching: .any)["map-screen-canvas"]
            let panel = app.descendants(matching: .any)["map-screen-person-panel"]
            let name = app.staticTexts["map-selected-person-name"]
            let selectedPersonAction = app.buttons["map-view-selected-person"]
            let hasMap = map.waitForExistence(timeout: 8)
            let hasPanel = panel.waitForExistence(timeout: 8)
            let hasName = name.waitForExistence(timeout: 8)
            XCTAssertTrue(hasMap, "The dedicated Map route must render its actual map canvas.", file: file, line: line)
            XCTAssertTrue(hasPanel, "The dedicated Map route must retain its selected-person panel.", file: file, line: line)
            XCTAssertTrue(hasName, "The dedicated Map route must retain the selected person.", file: file, line: line)
            guard hasMap && hasPanel && hasName else {
                XCTContext.runActivity(named: "Duo Map route elements missing") { activity in
                    activity.add(XCTAttachment(screenshot: app.screenshot()))
                    activity.add(XCTAttachment(string: app.debugDescription))
                }
                return
            }
            let mapCount = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@", "map-screen-canvas")
            ).count
            XCTAssertGreaterThan(app.frame.width, closedWidth + 100)
            XCTAssertEqual(mapCount, 1, "The wide Map route must own exactly one map canvas.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(map.frame.width, 320, "The dedicated Map route should keep a useful leading canvas.", file: file, line: line)
            XCTAssertGreaterThanOrEqual(panel.frame.width, 200, "The selected-person panel content should retain a useful width.", file: file, line: line)
            XCTAssertLessThanOrEqual(map.frame.maxX, panel.frame.minX + 1,
                              "The map canvas must sit beside the selected-person panel.", file: file, line: line)
            XCTAssertTrue(map.isHittable, "The dedicated map canvas must remain interactive.", file: file, line: line)
            XCTAssertEqual(name.label, "Maya Chen", "The map route should preserve Maya as the selected person.", file: file, line: line)
            XCTAssertTrue(name.isHittable, "The selected person's panel identity should remain visible.", file: file, line: line)
            XCTAssertTrue(selectedPersonAction.waitForExistence(timeout: 5), "The panel should retain its existing View action.", file: file, line: line)
            XCTAssertTrue(selectedPersonAction.isHittable, "The selected person's View action should remain usable.", file: file, line: line)
            XCTAssertTrue(selectedPersonAction.label.contains("Maya"))
            XCTAssertTrue(app.buttons["map-back-to-people"].exists, "The route should retain its People navigation action.", file: file, line: line)
            XCTAssertFalse(app.descendants(matching: .any)["people-map-canvas"].exists,
                            "The wide Map route must not retain a second parent People map.", file: file, line: line)
            let geometry = XCTAttachment(string: "app=\(app.frame); map=\(map.frame); panel=\(panel.frame); name=\(name.frame); viewAction=\(selectedPersonAction.frame)")
            geometry.name = "Duo dedicated Map route geometry"
            geometry.lifetime = .keepAlways
            add(geometry)
        }

        let app = launchDemo()
        XCTAssertTrue(app.buttons["person-row-maya"].waitForExistence(timeout: 20), "Fixture must load the real People row.")
        XCTAssertTrue(app.buttons["people-sheet-detent"].exists, "Closed Duo should use the compact sheet layout.")
        XCTAssertFalse(app.buttons["person-row-maya"].frame.isEmpty)
        let closedWidth = app.frame.width
        try mark("closed.ready", app: app)
        guard waitFor("open.continue", app: app) else { return }
        assertOpenRootGeometry(app, closedWidth: closedWidth)

        app.buttons["tab-sharing"].tap()
        let sharingRow = app.descendants(matching: .any)["sharing-mode-group-maya"]
        XCTAssertTrue(sharingRow.waitForExistence(timeout: 8), "Open Duo should show Maya's actual Sharing row.")
        let personName = sharingRow.staticTexts.matching(NSPredicate(format: "label == %@", "Maya Chen")).firstMatch
        let off = app.buttons["sharing-mode-off-maya"]
        let sealed = app.buttons["sharing-mode-sealed-maya"]
        let always = app.buttons["sharing-mode-always-maya"]
        let actions = app.buttons["sharing-actions-maya"]
        XCTAssertTrue(personName.waitForExistence(timeout: 5), "The Sharing row must retain Maya's identity.")
        for identifier in ["sharing-mode-off-maya", "sharing-mode-sealed-maya", "sharing-mode-always-maya"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Sharing row is missing \(identifier).")
            XCTAssertTrue(control.isHittable, "Sharing mode control \(identifier) must remain hittable in open Duo.")
            XCTAssertGreaterThanOrEqual(control.frame.width, 43.99)
            XCTAssertGreaterThanOrEqual(control.frame.height, 43.99)
        }
        XCTAssertTrue(actions.waitForExistence(timeout: 5), "Sharing row must retain its secondary actions menu.")
        XCTAssertTrue(actions.isHittable)
        XCTAssertGreaterThanOrEqual(actions.frame.width, 43.99)
        XCTAssertGreaterThanOrEqual(actions.frame.height, 43.99)
        XCTAssertLessThanOrEqual(sharingRow.frame.height, 84,
                                 "The normal-size connected person should remain one compact Sharing row.")
        let rowElements = [personName, off, sealed, always, actions]
        let rowFrames = rowElements.map(\.frame)
        for (index, frame) in rowFrames.enumerated() {
            XCTAssertGreaterThan(min(frame.maxY, sharingRow.frame.maxY) - max(frame.minY, sharingRow.frame.minY), 0,
                                 "Each Sharing control must occupy the compact row's vertical band.")
            XCTAssertGreaterThanOrEqual(frame.minX, sharingRow.frame.minX - 1)
            XCTAssertLessThanOrEqual(frame.maxX, sharingRow.frame.maxX + 1)
            if index > 0 {
                XCTAssertLessThanOrEqual(rowFrames[index - 1].maxX, frame.minX + 1,
                                         "Sharing row order must be Maya | Off | Sealed | Always | actions without overlap.")
            }
        }
        app.buttons["tab-circle"].tap()
        XCTAssertTrue(app.buttons["person-row-maya"].waitForExistence(timeout: 8))

        // The ordinary demo is Free: Leo's Always location is intentionally
        // absent from the leading People map, so View must keep its own map.
        let leoView = app.buttons["person-peek-leo"]
        XCTAssertTrue(leoView.waitForExistence(timeout: 5), "The Free fixture should expose Leo's Always View action.")
        leoView.tap()
        XCTAssertTrue(app.staticTexts["view-location-freshness"].waitForExistence(timeout: 8),
                      "Leo's Always detail should show its real location freshness line.")
        XCTAssertTrue(app.descendants(matching: .any)["view-embedded-map"].waitForExistence(timeout: 8),
                      "Free viewers have no Always pin in the leading map, so the View map must remain.")
        let viewBack = app.buttons["circle-back"]
        XCTAssertTrue(viewBack.waitForExistence(timeout: 5))
        viewBack.tap()
        XCTAssertTrue(app.buttons["person-row-maya"].waitForExistence(timeout: 8),
                      "Returning from Leo's View should restore the People root before Maya's Look.")

        app.buttons["person-row-maya"].tap()
        let detail = app.staticTexts["person-sharing-directions"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8), "Selecting Maya should push the real person screen.")
        let look = app.buttons["person-profile-peek"]
        XCTAssertTrue(look.waitForExistence(timeout: 5), "The selected person should offer Look.")
        look.tap()
        XCTAssertTrue(app.buttons["confirm-look-notify"].waitForExistence(timeout: 5))
        app.buttons["confirm-look-notify"].tap()
        XCTAssertTrue(app.staticTexts["view-location-freshness"].waitForExistence(timeout: 8),
                      "A confirmed Look should open the actual snapshot View screen.")
        XCTAssertTrue(waitForCondition(timeout: 5, condition: {
            !app.descendants(matching: .any)["view-embedded-map"].exists
        }), "When the leading People map already shows the same snapshot, View should omit its duplicate inset map.")
        XCTAssertTrue(app.buttons["tab-sharing"].exists, "Shared navigation should remain available while open.")
        assertOpenDetailGeometry(app, closedWidth: closedWidth)
        try mark("selected.ready", app: app)
        guard waitFor("folded.continue", app: app) else { return }

        XCTAssertLessThan(app.frame.width, closedWidth + 100, "Folding should return to compact navigation width.")
        XCTAssertTrue(detail.waitForExistence(timeout: 8), "Folding must preserve the selected person's navigation path.")
        XCTAssertTrue(waitForCondition(timeout: 5, condition: {
            app.descendants(matching: .any)["view-embedded-map"].exists
        }), "The compact View route should restore its standalone map while preserving navigation.")
        try mark("folded.ready", app: app)
        guard waitFor("reopened.continue", app: app) else { return }

        assertOpenDetailGeometry(app, closedWidth: closedWidth)
        XCTAssertTrue(waitForCondition(timeout: 5, condition: {
            !app.descendants(matching: .any)["view-embedded-map"].exists
        }), "Reopening should hide the inset again when the leading People map still has the same snapshot.")

        let openMap = app.buttons["view-open-map"]
        XCTAssertTrue(openMap.waitForExistence(timeout: 5), "View should keep its existing Open Map action.")
        openMap.tap()
        assertOpenMapRoute(app, closedWidth: closedWidth)
        let mapCapture = XCTAttachment(screenshot: app.screenshot())
        mapCapture.name = "Duo wide Map route with one map and Maya panel"
        mapCapture.lifetime = .keepAlways
        add(mapCapture)
        try mark("map-open.ready", app: app)
        guard waitFor("map-folded.continue", app: app) else { return }

        XCTAssertLessThan(app.frame.width, closedWidth + 100, "Folding while Map is open should restore compact width.")
        XCTAssertTrue(app.descendants(matching: .any)["map-screen-canvas"].waitForExistence(timeout: 8),
                      "Folding must preserve the dedicated Map route.")
        XCTAssertEqual(app.staticTexts["map-selected-person-name"].label, "Maya Chen",
                       "Folding must preserve the selected person on Map.")
        try mark("map-folded.ready", app: app)
        guard waitFor("map-reopened.continue", app: app) else { return }

        assertOpenMapRoute(app, closedWidth: closedWidth)
        let reopenedMapCapture = XCTAttachment(screenshot: app.screenshot())
        reopenedMapCapture.name = "Duo reopened Map route with preserved Maya selection"
        reopenedMapCapture.lifetime = .keepAlways
        add(reopenedMapCapture)
        app.buttons["map-back-to-people"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["people-map-canvas"].waitForExistence(timeout: 8),
                      "Returning to People should restore its own leading map.")
        XCTAssertFalse(app.descendants(matching: .any)["map-screen-canvas"].exists,
                        "Returning to People should leave the dedicated Map destination.")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Duo returned to People after Map route"
        capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
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

        let actions = app.buttons["sharing-actions-maya"]
        XCTAssertTrue(actions.waitForExistence(timeout: 8))
        let sharingScroll = app.scrollViews["sharing-scroll"]
        XCTAssertTrue(sharingScroll.waitForExistence(timeout: 5))
        for _ in 0..<6 where !isFullyVisible(actions, within: sharingScroll.frame.intersection(app.windows.firstMatch.frame)) {
            sharingScroll.swipeUp(velocity: .slow)
        }
        let sharingViewport = sharingScroll.frame.intersection(app.windows.firstMatch.frame)
        let pause = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "pause-sharing-maya", "Pause"
        )).firstMatch
        guard activateMenuTrigger(actions, expecting: pause, in: app, within: sharingViewport) else {
            XCTFail("Opening Maya's native Sharing actions should expose Pause.\n\(app.debugDescription)")
            app.terminate()
            return
        }
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        guard activateMenuOption(pause, in: app, within: app.windows.firstMatch.frame, postcondition: {
            app.buttons["pause-duration-3600"].exists
        }) else {
            XCTFail("Selecting Pause should open its duration sheet.\n\(app.debugDescription)")
            app.terminate()
            return
        }
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

        let remove = app.buttons["remove-person-action-maya"]
        guard activateMenuTrigger(
            actions,
            expecting: remove,
            in: app,
            within: app.scrollViews["sharing-scroll"].frame.intersection(app.windows.firstMatch.frame)
        ) else {
            XCTFail("Opening Maya's native Sharing actions should expose Remove.\n\(app.debugDescription)")
            app.terminate()
            return
        }
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        guard activateMenuOption(remove, in: app, within: app.windows.firstMatch.frame, postcondition: {
            app.buttons["remove-person-confirm"].exists
        }) else {
            XCTFail("Selecting Remove should open its confirmation dialog.\n\(app.debugDescription)")
            app.terminate()
            return
        }
        tapConfirmationAction("remove-person-confirm", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["sharing-mode-group-maya"].waitForExistence(timeout: 2))
    }

    func testPauseChoicesAndCancelRemainReachableAtAccessibilityText() {
        let variants: [(dark: Bool, language: String)] = [
            (false, "en"),
            (true, "de"),
            (false, "fr"),
            (true, "ja"),
            (false, "zh-Hans"),
            (true, "pt-BR")
        ]
        for (dark, language) in variants {
            let app = launchDemo(dark: dark, contentSize: "UICTContentSizeCategoryAccessibilityXXXL", language: language)
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
            app.buttons["tab-sharing"].tap()
            let actions = app.buttons["sharing-actions-maya"]
            XCTAssertTrue(actions.waitForExistence(timeout: 8))
            let sharingScroll = app.scrollViews["sharing-scroll"]
            XCTAssertTrue(sharingScroll.waitForExistence(timeout: 5))
            let pauseLabel: String
            switch language {
            case "ja": pauseLabel = "一時停止"
            case "zh-Hans": pauseLabel = "暂停"
            case "pt-BR": pauseLabel = "Pausar"
            default: pauseLabel = "Pause"
            }
            let pauseScroll = app.scrollViews["pause-sharing-scroll"]
            let firstDuration = app.buttons["pause-duration-3600"]

            func settledFrame(of element: XCUIElement, timeout: TimeInterval = 1.2) -> CGRect? {
                let deadline = ProcessInfo.processInfo.systemUptime + timeout
                var previous: CGRect?
                var stableSamples = 0
                while ProcessInfo.processInfo.systemUptime < deadline {
                    if element.exists {
                        let frame = element.frame
                        if frame.width > 0 && frame.height > 0 {
                            if let previous,
                               abs(previous.minX - frame.minX) < 1,
                               abs(previous.minY - frame.minY) < 1,
                               abs(previous.width - frame.width) < 1,
                               abs(previous.height - frame.height) < 1 {
                                stableSamples += 1
                                if stableSamples >= 2 { return frame }
                            } else {
                                stableSamples = 0
                            }
                            previous = frame
                        }
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                }
                return element.exists ? element.frame : nil
            }

            func scrollToSharingAction(_ element: XCUIElement, towardBottom: Bool,
                                       requiresHittable: Bool = true) -> Bool {
                for _ in 0..<40 {
                    let viewport = sharingScroll.frame.intersection(app.windows.firstMatch.frame)
                    let visible = requiresHittable
                        ? isFullyVisible(element, within: viewport)
                        : isFullyVisibleGeometry(element, within: viewport)
                    if visible { return true }
                    let settled = settledFrame(of: element)
                    let shouldScrollDown: Bool
                    if let frame = settled, viewport.height > 0 {
                        let overflowTop = frame.minY < viewport.minY + 2
                        let overflowBottom = frame.maxY > viewport.maxY - 2
                        if overflowTop && !overflowBottom {
                            shouldScrollDown = false
                        } else if overflowBottom && !overflowTop {
                            shouldScrollDown = true
                        } else if overflowTop && overflowBottom {
                            shouldScrollDown = frame.midY > viewport.midY
                        } else {
                            shouldScrollDown = frame.midY > viewport.midY
                        }
                    } else {
                        shouldScrollDown = towardBottom
                    }
                    let startY: CGFloat = shouldScrollDown ? 0.55 : 0.45
                    let endY: CGFloat = 0.50
                    sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                        .press(forDuration: 0.12, thenDragTo: sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
                    _ = settledFrame(of: element, timeout: 0.8)
                }
                let finalViewport = sharingScroll.frame.intersection(app.windows.firstMatch.frame)
                return requiresHittable
                    ? isFullyVisible(element, within: finalViewport)
                    : isFullyVisibleGeometry(element, within: finalViewport)
            }

            let expandedLabel: String
            let collapsedLabel: String
            switch language {
            case "de": expandedLabel = "Erweitert"; collapsedLabel = "Eingeklappt"
            case "fr": expandedLabel = "Développé"; collapsedLabel = "Réduit"
            case "ja": expandedLabel = "展開"; collapsedLabel = "折りたたみ"
            case "zh-Hans": expandedLabel = "已展开"; collapsedLabel = "已折叠"
            case "pt-BR": expandedLabel = "Expandido"; collapsedLabel = "Recolhido"
            default: expandedLabel = "Expanded"; collapsedLabel = "Collapsed"
            }
            XCTAssertTrue(scrollToSharingAction(actions, towardBottom: false), "The ellipsis must be scrollable into the Sharing viewport.")
            XCTAssertEqual(actions.value as? String, collapsedLabel, "VoiceOver should report the collapsed action-list state in \(language).")
            actions.tap()
            XCTAssertEqual(actions.value as? String, expandedLabel, "VoiceOver should report the expanded action-list state in \(language).")

            let presenceGrant = app.buttons["presence-grant-maya"]
            XCTAssertTrue(scrollToSharingAction(presenceGrant, towardBottom: true, requiresHittable: false),
                          "The long Home/Away action must remain fully visible after scrolling even when disabled in demo mode.")
            XCTAssertFalse(presenceGrant.isEnabled, "Demo mode should keep the presence grant action disabled.")
            XCTAssertTrue(isFullyVisibleGeometry(presenceGrant, within: sharingScroll.frame.intersection(app.windows.firstMatch.frame)),
                          "The disabled Home/Away action must be fully inside the Sharing viewport.")
            XCTAssertGreaterThan(presenceGrant.frame.height, 44,
                                 "At accessibility text sizes, the long action label should wrap vertically.")
            let expectedPresenceLabel: String
            switch language {
            case "de": expectedPresenceLabel = "Lass Maya wissen, wenn ich zu Hause oder unterwegs bin"
            case "fr": expectedPresenceLabel = "Prévenez Maya quand je suis chez moi ou absent"
            case "ja": expectedPresenceLabel = "Mayaに自宅か外出中かを知らせる"
            case "zh-Hans": expectedPresenceLabel = "让我在家或外出时通知 Maya"
            case "pt-BR": expectedPresenceLabel = "Avisar Maya quando eu estiver em casa ou fora"
            default: expectedPresenceLabel = "Let Maya know when I’m Home or Away"
            }
            XCTAssertEqual(presenceGrant.label, expectedPresenceLabel,
                           "The full localized presence action label must remain accessible in \(language).")

            let removeAction = app.buttons["remove-person-action-maya"]
            XCTAssertTrue(scrollToSharingAction(removeAction, towardBottom: true), "The expanded action list must scroll all the way to Remove.")
            let expectedRemoveLabel: String
            switch language {
            case "de": expectedRemoveLabel = "Entfernen"
            case "fr": expectedRemoveLabel = "Retirer"
            case "ja": expectedRemoveLabel = "削除"
            case "zh-Hans": expectedRemoveLabel = "消除"
            case "pt-BR": expectedRemoveLabel = "Remover"
            default: expectedRemoveLabel = "Remove"
            }
            XCTAssertEqual(removeAction.label, expectedRemoveLabel)

            let pause = app.buttons["pause-sharing-maya"]
            XCTAssertTrue(scrollToSharingAction(pause, towardBottom: false), "Pause must be reachable within the actual Sharing scroll viewport.")
            XCTAssertEqual(pause.label, pauseLabel, "The inline Pause action must use the selected app language.")
            XCTAssertTrue(isFullyVisible(pause, within: sharingScroll.frame.intersection(app.windows.firstMatch.frame)),
                          "Pause must not be clipped by the Sharing viewport.")
            pause.tap()
            guard waitForCondition(timeout: 5, condition: { pauseScroll.exists && firstDuration.exists }) else {
                XCTFail("Tapping the inline Pause action should open the actual duration sheet.\n\(app.debugDescription)")
                app.terminate()
                continue
            }
            let initialPauseViewport = pauseScroll.frame.intersection(app.windows.firstMatch.frame)
            let initialCapture = XCTAttachment(screenshot: app.screenshot())
            initialCapture.name = "Pause first open - \(language) - \(dark ? "dark" : "light") - accessibility text"
            initialCapture.lifetime = .keepAlways
            add(initialCapture)
            XCTAssertTrue(isFullyVisible(firstDuration, within: initialPauseViewport),
                          "The first Pause duration should be fully visible on the initial sheet without scrolling.")
            XCTAssertGreaterThanOrEqual(firstDuration.frame.height, 44 - 1e-6,
                                        "The first Pause duration should retain a 44-point target on first open.")

            let durations = [3600, 28800, 86400, 172800, 259200]
            var durationVisibilityFailed = false
            for duration in durations {
                let choice = app.buttons["pause-duration-\(duration)"]
                if !scrollPauseSheet(to: choice, in: app) {
                    XCTFail("Every pause duration should be fully visible inside the Pause sheet at maximum text size.\n\(app.debugDescription)")
                    durationVisibilityFailed = true
                    break
                }
                XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
            }
            if durationVisibilityFailed {
                app.terminate()
                continue
            }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Pause - Accessibility text - \(language) - \(dark ? "dark" : "light")"
            capture.lifetime = .keepAlways
            add(capture)
            let cancel = app.buttons["pause-sharing-cancel"]
            guard scrollPauseSheet(to: cancel, in: app) else {
                XCTFail("Cancel should remain fully visible inside the Pause sheet after the duration list.\n\(app.debugDescription)")
                app.terminate()
                continue
            }
            let cancelCapture = XCTAttachment(screenshot: app.screenshot())
            cancelCapture.name = "Pause - Cancel reachable - \(language) - \(dark ? "dark" : "light")"
            cancelCapture.lifetime = .keepAlways
            add(cancelCapture)
            cancel.tap()
            XCTAssertTrue(actions.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["sharing-mode-sealed-maya"].isSelected,
                          "Inspecting or cancelling Pause must not change sharing.")
        }
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
                XCTFail("Sharing row geometry did not remain steady and hittable in \(variant.language).")
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
        let peopleMap = app.descendants(matching: .any)["people-map-canvas"]
        let embeddedMap = app.descendants(matching: .any)["view-embedded-map"]
        if peopleMap.exists {
            // CircleView exposes map pins as people-map-pin-<person UUID>, not a
            // name-based ID. Match the actual annotation by that stable prefix
            // and its accessible member name, then verify the selected snapshot.
            let leadingMayaPin = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "people-map-pin-", "Maya Chen"
            )).firstMatch
            XCTAssertTrue(leadingMayaPin.waitForExistence(timeout: 5),
                          "The wide People map should contain Maya's real authorized snapshot pin.")
            XCTAssertTrue(leadingMayaPin.label.contains(snapshotTime),
                          "Maya's leading-map pin should retain the selected snapshot time.")
            XCTAssertFalse(embeddedMap.exists,
                           "When the wide People map already contains Maya's same snapshot, View must omit the duplicate inset.")
        } else {
            XCTAssertTrue(embeddedMap.waitForExistence(timeout: 5),
                          "Compact View has no leading People map, so it must retain its standalone map.")
        }
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
            XCTFail("German XXL Sharing controls did not remain steady and hittable.")
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
        let setAway = app.buttons["set-home-status-away"].firstMatch
        XCTAssertTrue(setAway.waitForExistence(timeout: 5))
        setAway.tap()
        XCTAssertTrue(waitForCondition(timeout: 5, condition: {
            !app.buttons["set-home-status-home"].exists
                && !setAway.exists
                && !setHidden.exists
        }), "Selecting Away should dismiss the native Home/Away/Hidden options before the next action.")

        let addSomeone = app.buttons["add-someone-button"]
        let sharingScroll = app.scrollViews["sharing-scroll"]
        XCTAssertTrue(addSomeone.waitForExistence(timeout: 5), "The Sharing tab should return after presence selection.")
        XCTAssertTrue(sharingScroll.waitForExistence(timeout: 5), "Sharing should retain its scroll viewport after presence selection.")
        for _ in 0..<24 {
            let viewport = sharingScroll.frame.intersection(app.windows.firstMatch.frame)
            if isFullyVisible(addSomeone, within: viewport) { break }
            let belowViewport = !addSomeone.exists || addSomeone.frame.isEmpty
                || addSomeone.frame.midY > viewport.midY
            let startY: CGFloat = belowViewport ? 0.82 : 0.18
            let endY: CGFloat = belowViewport ? 0.62 : 0.38
            sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(forDuration: 0.05, thenDragTo: sharingScroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
        }
        let addViewport = sharingScroll.frame.intersection(app.windows.firstMatch.frame)
        XCTAssertTrue(isFullyVisible(addSomeone, within: addViewport), "Add someone must be fully visible inside Sharing before its single tap.")
        XCTAssertNotNil(steadyVisibleFrames([addSomeone], in: sharingScroll, app: app,
                                            stableFor: 0.3, timeout: 5),
                        "Add someone must settle at a stable in-viewport position before tapping.")
        addSomeone.tap()
        XCTAssertTrue(app.staticTexts["add-person-heading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["add-person-explanation"].exists, "Explain that connecting does not start sharing, without repeating phone-format guidance.")
        let handle = app.textFields["connection-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(handle.isHittable, "The Add sheet should expose the handle field after one Add tap.")
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

    func testNotificationPreferencesRemainReachableWithoutPrompting() {
        for (dark, language, accessibility) in [(false, "en", false), (true, "de", true)] {
            let app = launchDemo(dark: dark, route: "you",
                                 contentSize: accessibility ? "UICTContentSizeCategoryAccessibilityXXXL" : nil,
                                 language: language)
            XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 20))
            let status = app.staticTexts["notifications-permission-status"]
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertTrue(scrollYouContent(to: status, direction: .down, in: app))
            let viewport = app.scrollViews["you-scroll"].frame
            XCTAssertTrue(isFullyVisible(status, within: viewport), "The complete notification status should be inside the You scroll viewport.")
            let enable = app.buttons["enable-notifications"]
            let settings = app.buttons["open-notification-settings"]
            let action = enable.exists ? enable : settings
            XCTAssertTrue(scrollYouContent(to: action, direction: .down, in: app))
            XCTAssertTrue(isFullyVisible(action, within: viewport), "The full notification action should be visible, not clipped by the scroll viewport.")
            XCTAssertGreaterThanOrEqual(action.frame.width, 43.99)
            XCTAssertGreaterThanOrEqual(action.frame.height, 43.99)
            XCTAssertFalse(app.alerts.firstMatch.exists, "Opening You must not request notification permission.")
            XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists)
            if enable.exists {
                XCTAssertFalse(enable.isEnabled, "The offline demo must not request native notification permission.")
            }
            let support = app.descendants(matching: .any)["support-link"].firstMatch
            XCTAssertTrue(support.waitForExistence(timeout: 5))
            XCTAssertTrue(isFullyVisible(support, within: app.windows.firstMatch.frame), "The legal footer should be fully visible at the bottom of the screen.")
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "You notifications - \(language) - \(dark ? "dark" : "light") - \(accessibility ? "maximum text" : "standard text")"
            capture.lifetime = .keepAlways
            add(capture)
            app.terminate()
        }
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
            let choice = app.buttons[option]
            let viewport = app.scrollViews["you-scroll"].frame.intersection(app.windows.firstMatch.frame)
            XCTAssertTrue(activateMenuTrigger(picker, expecting: choice, in: app, within: viewport),
                          "Opening the appearance picker should expose \(option).\n\(app.debugDescription)")
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "The picker should offer the \(option) appearance.")
            XCTAssertTrue(activateMenuOption(choice, in: app, within: app.windows.firstMatch.frame, postcondition: {
                (app.descendants(matching: .any)["appearance-preference"].value as? String) == option
            }), "Choosing \(option) should update the appearance picker value.\n\(app.debugDescription)")

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
        let systemChoice = app.buttons["System"]
        let viewport = app.scrollViews["you-scroll"].frame.intersection(app.windows.firstMatch.frame)
        XCTAssertTrue(activateMenuTrigger(picker, expecting: systemChoice, in: app, within: viewport),
                      "Opening the appearance picker should expose System.\n\(app.debugDescription)")
        XCTAssertTrue(activateMenuOption(systemChoice, in: app, within: app.windows.firstMatch.frame, postcondition: {
            (app.descendants(matching: .any)["appearance-preference"].value as? String) == "System"
        }), "Choosing System should update the appearance picker value.\n\(app.debugDescription)")
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
            let homeStatus = app.buttons["home-status-control"]
            for _ in 0..<24 {
                let viewport = sharingScroll.frame.intersection(app.windows.firstMatch.frame)
                if isFullyVisible(homeStatus, within: viewport) { break }
                let belowViewport = !homeStatus.exists || homeStatus.frame.isEmpty
                    || homeStatus.frame.midY > viewport.midY
                nudgeSharingScroll(forward: belowViewport)
            }
            XCTAssertTrue(homeStatus.exists, "Sharing should expose the Home status card at accessibility sizes.")
            XCTAssertTrue(isFullyVisible(homeStatus, within: sharingScroll.frame.intersection(app.windows.firstMatch.frame)),
                          "The wrapped Home status card should remain fully reachable in the Sharing scroll view.")
            XCTAssertGreaterThanOrEqual(homeStatus.frame.height, 52)
            let expectedHomeStatusLabel = variant.language == "de" ? "Home-Status" : "Home status"
            XCTAssertEqual(homeStatus.label, expectedHomeStatusLabel,
                           "The localized Home status heading should be exposed to accessibility.")
            let currentPresence = homeStatus.value as? String
            XCTAssertNotNil(currentPresence, "The current presence should be exposed as the card's accessibility value.")
            XCTAssertFalse((currentPresence ?? "").isEmpty)
            let homeStatusCapture = XCTAttachment(screenshot: app.screenshot())
            homeStatusCapture.name = "Accessibility text - Home status card - \(variant.language) - \(dark ? "dark" : "light")"
            homeStatusCapture.lifetime = .keepAlways
            add(homeStatusCapture)
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
            let keyboard = app.keyboards.firstMatch
            let keyboardVisible = waitForCondition(timeout: 5, condition: {
                keyboard.exists && keyboard.frame.height > 0
            })
            XCTAssertTrue(keyboardVisible, "Typing should present the software keyboard before checking Add controls.")
            guard keyboardVisible else {
                add(XCTAttachment(screenshot: app.screenshot()))
                add(XCTAttachment(string: app.debugDescription))
                app.terminate()
                continue
            }
            let addScroll = app.scrollViews["add-person-scroll"]
            XCTAssertTrue(addScroll.waitForExistence(timeout: 5), "The Add form should expose its scroll viewport while the keyboard is open.")
            let close = app.buttons["cancel-add-person"]
            let borderedField = app.descendants(matching: .any)["connection-lookup-field"]
            XCTAssertTrue(borderedField.waitForExistence(timeout: 5), "The full bordered field should remain addressable while the keyboard is open.")
            let appWindow = app.windows.firstMatch
            func addFieldLayoutIsValid(requiresClear: Bool) -> Bool {
                guard borderedField.exists, field.exists, close.exists, keyboard.exists else { return false }
                if requiresClear && !clear.exists { return false }
                let fieldFrame = borderedField.frame
                let scrollFrame = addScroll.frame
                let windowFrame = appWindow.frame
                let footerFrame = CGRect(x: windowFrame.minX,
                                         y: close.frame.midY - 26,
                                         width: windowFrame.width,
                                         height: 52)
                let keyFrame = keyboard.frame
                guard frameIsFullyVisible(fieldFrame, within: scrollFrame),
                      scrollFrame.maxY - fieldFrame.maxY >= 8 - 1,
                      fieldFrame.maxY <= footerFrame.minY - 8 + 1,
                      !fieldFrame.intersects(footerFrame),
                      !fieldFrame.intersects(keyFrame),
                      !footerFrame.intersects(keyFrame),
                      close.isHittable,
                      field.isHittable else { return false }
                if requiresClear {
                    return clear.isHittable
                        && clear.frame.width >= 43.99
                        && clear.frame.height >= 43.99
                        && frameIsFullyVisible(clear.frame, within: fieldFrame)
                        && !clear.frame.intersects(keyFrame)
                }
                return true
            }
            func waitForAddFieldLayout(requiresClear: Bool) -> Bool {
                let targets = requiresClear ? [borderedField, field, clear] : [borderedField, field]
                guard steadyVisibleFrames(targets, in: addScroll, app: app,
                                          stableFor: 0.3, timeout: 5) != nil else { return false }
                return waitForCondition(timeout: 5) { addFieldLayoutIsValid(requiresClear: requiresClear) }
            }
            func addFieldLayoutDiagnostic(requiresClear: Bool) -> String {
                guard borderedField.exists, field.exists, close.exists, keyboard.exists,
                      addScroll.exists, appWindow.exists else {
                    return "elements: borderedField=\(borderedField.exists) textField=\(field.exists) close=\(close.exists) keyboard=\(keyboard.exists) scroll=\(addScroll.exists) window=\(appWindow.exists)"
                }
                let fieldFrame = borderedField.frame
                let scrollFrame = addScroll.frame
                let windowFrame = appWindow.frame
                let footerFrame = CGRect(x: windowFrame.minX,
                                         y: close.frame.midY - 26,
                                         width: windowFrame.width,
                                         height: 52)
                let keyFrame = keyboard.frame
                var predicates = [
                    "fullFieldInScroll=\(frameIsFullyVisible(fieldFrame, within: scrollFrame))",
                    "scrollBottomClearance=\(scrollFrame.maxY - fieldFrame.maxY) (requires >= 7)",
                    "footerTopClearance=\(footerFrame.minY - fieldFrame.maxY) (requires >= 7)",
                    "fieldIntersectsFooter=\(fieldFrame.intersects(footerFrame))",
                    "fieldIntersectsKeyboard=\(fieldFrame.intersects(keyFrame))",
                    "footerIntersectsKeyboard=\(footerFrame.intersects(keyFrame))",
                    "closeHittable=\(close.isHittable)",
                    "fieldHittable=\(field.isHittable)"
                ]
                if requiresClear {
                    predicates += [
                        "clearExists=\(clear.exists)",
                        "clearHittable=\(clear.isHittable)",
                        "clearFrame=\(NSCoder.string(for: clear.frame))",
                        "clearSizeAtLeast44=\(clear.frame.width >= 43.99 && clear.frame.height >= 43.99)",
                        "clearInsideBorderedField=\(frameIsFullyVisible(clear.frame, within: fieldFrame))",
                        "clearIntersectsKeyboard=\(clear.frame.intersects(keyFrame))"
                    ]
                }
                return ([
                    "fieldFrame=\(NSCoder.string(for: fieldFrame))",
                    "scrollFrame=\(NSCoder.string(for: scrollFrame))",
                    "windowFrame=\(NSCoder.string(for: windowFrame))",
                    "closeFrame=\(NSCoder.string(for: close.frame))",
                    "derivedFooterFrame=\(NSCoder.string(for: footerFrame))",
                    "keyboardFrame=\(NSCoder.string(for: keyFrame))"
                ] + predicates).joined(separator: "\n")
            }
            let fieldReadyBeforeClear = waitForAddFieldLayout(requiresClear: true)
            if !fieldReadyBeforeClear {
                let diagnostic = XCTAttachment(string: addFieldLayoutDiagnostic(requiresClear: true))
                diagnostic.name = "Add field geometry failure - \(variant.language) - \(dark ? "dark" : "light")"
                diagnostic.lifetime = .keepAlways
                add(diagnostic)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Add field geometry failure screenshot - \(variant.language) - \(dark ? "dark" : "light")"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Add field geometry failure hierarchy - \(variant.language) - \(dark ? "dark" : "light")"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertTrue(fieldReadyBeforeClear,
                          "The entire bordered field must settle inside the scroll viewport with 8pt footer clearance, separate from the keyboard.")
            guard fieldReadyBeforeClear else {
                add(XCTAttachment(screenshot: app.screenshot()))
                add(XCTAttachment(string: app.debugDescription))
                app.terminate()
                continue
            }
            let closeFrames = steadyVisibleFrames([close], in: appWindow, app: app,
                                                  stableFor: 0.3, timeout: 5)
            XCTAssertNotNil(closeFrames, "Close must settle at a stable position inside the visible app window.")
            guard closeFrames != nil else {
                add(XCTAttachment(screenshot: app.screenshot()))
                add(XCTAttachment(string: app.debugDescription))
                app.terminate()
                continue
            }
            XCTAssertTrue(close.isHittable, "Close must remain hittable above the software keyboard.")
            XCTAssertGreaterThanOrEqual(close.frame.height, 43.99)
            XCTAssertGreaterThanOrEqual(close.frame.minX, appWindow.frame.minX - 1)
            XCTAssertLessThanOrEqual(close.frame.maxX, appWindow.frame.maxX + 1)
            XCTAssertGreaterThanOrEqual(close.frame.minY, appWindow.frame.minY - 1)
            XCTAssertLessThanOrEqual(close.frame.maxY, appWindow.frame.maxY + 1)
            XCTAssertFalse(close.frame.intersects(keyboard.frame), "Close must not be obscured by the software keyboard.")
            let populatedState = XCTAttachment(screenshot: app.screenshot())
            populatedState.name = "Accessibility text - Add populated field before clear - \(variant.language) - \(dark ? "dark" : "light")"
            populatedState.lifetime = .keepAlways
            add(populatedState)
            let populatedTree = XCTAttachment(string: app.debugDescription)
            populatedTree.name = "Accessibility hierarchy - Add populated field before clear - \(variant.language) - \(dark ? "dark" : "light")"
            populatedTree.lifetime = .keepAlways
            add(populatedTree)
            let lookup = XCTAttachment(screenshot: app.screenshot())
            lookup.name = "Accessibility text - Add keyboard - \(variant.language) - \(dark ? "dark" : "light")"
            lookup.lifetime = .keepAlways
            add(lookup)
            let keyboardTree = XCTAttachment(string: app.debugDescription)
            keyboardTree.name = "Accessibility hierarchy - Add keyboard before clear - \(variant.language) - \(dark ? "dark" : "light")"
            keyboardTree.lifetime = .keepAlways
            add(keyboardTree)
            let placeholder = field.placeholderValue
            XCTAssertNotNil(placeholder, "The lookup field must expose its placeholder before clearing.")
            XCTAssertFalse((placeholder ?? "").isEmpty, "The lookup placeholder must not be empty.")
            XCTAssertEqual(field.value as? String, "abc", "Typing should populate the lookup field before clearing.")
            clear.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 3), "Clearing must leave the lookup field visible.")
            XCTAssertTrue(close.waitForExistence(timeout: 3), "Clearing must leave the Add sheet close control visible.")
            let clearedState = XCTAttachment(screenshot: app.screenshot())
            clearedState.name = "Accessibility text - Add empty field after clear - \(variant.language) - \(dark ? "dark" : "light")"
            clearedState.lifetime = .keepAlways
            add(clearedState)
            let clearedTree = XCTAttachment(string: app.debugDescription)
            clearedTree.name = "Accessibility hierarchy - Add empty field after clear - \(variant.language) - \(dark ? "dark" : "light")"
            clearedTree.lifetime = .keepAlways
            add(clearedTree)
            let clearedValue = field.value as? String
            XCTAssertNotNil(clearedValue, "The cleared lookup field must expose an accessibility value.")
            XCTAssertNotNil(placeholder, "The lookup field placeholder must still be available after clearing.")
            XCTAssertEqual(clearedValue, placeholder, "Clearing must restore the visible placeholder value.")
            XCTAssertFalse(clear.exists, "Clear should disappear once the lookup field is empty.")

            let fieldReadyAfterClear = waitForAddFieldLayout(requiresClear: false)
            XCTAssertTrue(fieldReadyAfterClear,
                          "After Clear, the bordered field must remain inside its viewport and above the Close footer.")
            let clearedAfterLayout = XCTAttachment(screenshot: app.screenshot())
            clearedAfterLayout.name = "Accessibility text - Add cleared field after layout - \(variant.language) - \(dark ? "dark" : "light")"
            clearedAfterLayout.lifetime = .keepAlways
            add(clearedAfterLayout)

            field.typeText("xyz")
            let fieldReadyAfterRetyping = waitForAddFieldLayout(requiresClear: true)
                && (field.value as? String) == "xyz"
            XCTAssertTrue(fieldReadyAfterRetyping,
                          "Typing again after Clear should keep the whole field visible above the footer and keyboard.")
            let retypedState = XCTAttachment(screenshot: app.screenshot())
            retypedState.name = "Accessibility text - Add field after retyping - \(variant.language) - \(dark ? "dark" : "light")"
            retypedState.lifetime = .keepAlways
            add(retypedState)
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
        timeout: TimeInterval = 30
    ) -> [CGRect]? {
        let start = ProcessInfo.processInfo.systemUptime
        let deadline = start + timeout
        var previous: [CGRect]?
        var stableSince: TimeInterval?
        var samples: [String] = []
        var settled: [CGRect]?

        while ProcessInfo.processInfo.systemUptime < deadline {
            let now = ProcessInfo.processInfo.systemUptime
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
            let firstExists = elements.first?.exists ?? false
            let visible = firstExists && elements.dropFirst().allSatisfy(\.isHittable)
                && geometryValid
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

    private func launchDemo(dark: Bool? = nil, route: String? = nil, forceEnglish: Bool = true, contentSize: String? = nil, language: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        if let route { app.launchEnvironment["TRUST_SCREENSHOT"] = route }
        if let dark { app.launchArguments += ["-appearancePreference", dark ? "dark" : "light"] }
        if let contentSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize] }
        // Demo tests assert English copy. The argument-domain override makes each launch
        // independent of the persistent language preference left by other simulator runs.
        if let language { app.launchArguments += ["-trust.appLanguage", language] }
        else if forceEnglish { app.launchArguments += ["-trust.appLanguage", "en"] }
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

    /// Scrolls only inside the Pause duration sheet and requires full-frame visibility.
    /// Native scroll-view swipes keep gestures inside the presented Pause sheet.
    private func scrollPauseSheet(to element: XCUIElement, in app: XCUIApplication) -> Bool {
        let scrollView = app.scrollViews["pause-sharing-scroll"]
        guard scrollView.waitForExistence(timeout: 2) else {
            attachPauseScrollFailure(element, in: app, scrollFrame: nil, viewport: nil)
            return false
        }
        let appWindow = app.windows.firstMatch.frame
        var lastScrollFrame = scrollView.frame
        var lastViewport = lastScrollFrame.intersection(appWindow)

        for _ in 0..<12 {
            lastScrollFrame = scrollView.frame
            lastViewport = lastScrollFrame.intersection(appWindow)
            guard !lastViewport.isNull && lastViewport.width > 0 && lastViewport.height > 0 else {
                attachPauseScrollFailure(element, in: app, scrollFrame: lastScrollFrame, viewport: lastViewport)
                return false
            }
            if isFullyVisible(element, within: lastViewport) { return true }
            let frame = element.frame
            let hasUsableFrame = !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            let targetY = hasUsableFrame ? frame.midY : .nan
            let dragDirection: ScrollDirection
            if targetY.isFinite && frame.maxY > lastViewport.maxY - 8 {
                dragDirection = .down
            } else if targetY.isFinite && frame.minY < lastViewport.minY + 8 {
                dragDirection = .up
            } else if targetY.isFinite {
                dragDirection = targetY > lastViewport.midY ? .down : .up
            } else {
                dragDirection = .down
            }
            switch dragDirection {
            case .down: scrollView.swipeUp(velocity: .slow)
            case .up: scrollView.swipeDown(velocity: .slow)
            }
        }
        lastScrollFrame = scrollView.frame
        lastViewport = lastScrollFrame.intersection(appWindow)
        guard !lastViewport.isNull && isFullyVisible(element, within: lastViewport) else {
            attachPauseScrollFailure(element, in: app, scrollFrame: lastScrollFrame, viewport: lastViewport)
            return false
        }
        return true
    }

    private func attachPauseScrollFailure(_ element: XCUIElement, in app: XCUIApplication,
                                         scrollFrame: CGRect?, viewport: CGRect?) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Pause target clipped - \(element.identifier)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let geometry = XCTAttachment(string: "target=\(element.frame); scroll=\(String(describing: scrollFrame)); visible viewport=\(String(describing: viewport)); app window=\(app.windows.firstMatch.frame)")
        geometry.name = "Pause target and current visible viewport geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Pause target clipped accessibility hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    /// Uses short viewport-relative drags and re-evaluates the target after every move.
    /// Large swipes can jump past a control when accessibility text expands the page.
    private func scrollYouContent(to element: XCUIElement, direction: ScrollDirection, in app: XCUIApplication) -> Bool {
        let scrollView = app.scrollViews["you-scroll"]
        guard scrollView.waitForExistence(timeout: 5) else { return false }
        let viewport = scrollView.frame
        guard viewport.width > 0, viewport.height > 0 else { return false }

        for _ in 0..<18 {
            if isFullyVisible(element, within: viewport) { return true }
            let frame = element.frame
            let hasUsableFrame = !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            let targetY = hasUsableFrame ? frame.midY : .nan
            let dragDirection: ScrollDirection
            if targetY.isFinite && frame.maxY > viewport.maxY - 8 {
                dragDirection = .down
            } else if targetY.isFinite && frame.minY < viewport.minY + 8 {
                dragDirection = .up
            } else if targetY.isFinite {
                // Move a partially clipped control toward the viewport center.
                dragDirection = targetY > viewport.midY ? .down : .up
            } else {
                dragDirection = direction
            }

            let startY: CGFloat = dragDirection == .down ? 0.82 : 0.18
            let endY: CGFloat = dragDirection == .down ? 0.62 : 0.38
            let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        return isFullyVisible(element, within: viewport)
    }

    private func isFullyVisible(_ element: XCUIElement, within viewport: CGRect) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0,
              viewport.width > 0, viewport.height > 0 else { return false }
        let tolerance: CGFloat = 2
        return element.isHittable
            && frame.minX >= viewport.minX - tolerance
            && frame.maxX <= viewport.maxX + tolerance
            && frame.minY >= viewport.minY - tolerance
            && frame.maxY <= viewport.maxY + tolerance
    }

    private func isFullyVisibleGeometry(_ element: XCUIElement, within viewport: CGRect) -> Bool {
        guard element.exists else { return false }
        return frameIsFullyVisible(element.frame, within: viewport)
    }

    private enum ScrollDirection: Equatable {
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

    private func activateMenuTrigger(_ trigger: XCUIElement, expecting menuItem: XCUIElement,
                                     in app: XCUIApplication, within viewport: CGRect,
                                     timeout: TimeInterval = 25) -> Bool {
        guard waitForStableMenuAction(trigger, within: viewport, timeout: timeout) else {
            attachMenuActivationFailure("Menu trigger did not settle before activation", element: trigger, in: app)
            return false
        }
        trigger.tap()
        if waitForCondition(timeout: 8, condition: { menuItem.exists && menuItem.isHittable }) { return true }

        guard trigger.exists, trigger.isHittable, frameIsFullyVisible(trigger.frame, within: viewport) else {
            attachMenuActivationFailure("Menu trigger did not open its expected item", element: trigger, in: app)
            return false
        }
        attachMenuActivationFailure("Native menu-trigger tap did not open the menu; trying one element-centered tap", element: trigger, in: app)
        trigger.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return waitForCondition(timeout: 10, condition: { menuItem.exists && menuItem.isHittable })
    }

    private func activateMenuOption(_ option: XCUIElement, in app: XCUIApplication,
                                    within viewport: CGRect, timeout: TimeInterval = 25,
                                    postcondition: () -> Bool) -> Bool {
        guard waitForStableMenuAction(option, within: viewport, timeout: timeout) else {
            attachMenuActivationFailure("Menu option did not settle before selection", element: option, in: app)
            return false
        }
        option.tap()
        if waitForCondition(timeout: 4, condition: postcondition) { return true }

        guard option.exists, option.isHittable, frameIsFullyVisible(option.frame, within: viewport) else {
            attachMenuActivationFailure("Menu option activation did not satisfy its expected state", element: option, in: app)
            return false
        }
        attachMenuActivationFailure("Native menu-option tap did not change state; trying one element-centered tap", element: option, in: app)
        option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let completed = waitForCondition(timeout: 8, condition: postcondition)
        if !completed {
            attachMenuActivationFailure("Menu option remained unchanged after bounded activation", element: option, in: app)
        }
        return completed
    }

    private func waitForCondition(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func frameIsFullyVisible(_ frame: CGRect, within viewport: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
            && viewport.width > 0 && viewport.height > 0
            && frame.minX >= viewport.minX - 1 && frame.maxX <= viewport.maxX + 1
            && frame.minY >= viewport.minY - 1 && frame.maxY <= viewport.maxY + 1
    }

    private func waitForStableMenuAction(_ option: XCUIElement,
                                         within viewport: CGRect, timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var previousFrame: CGRect?
        var stableSince: TimeInterval?
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard let snapshot = try? option.snapshot(), snapshot.isEnabled,
                  option.isHittable, frameIsFullyVisible(snapshot.frame, within: viewport) else {
                previousFrame = nil
                stableSince = nil
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                continue
            }
            let frame = snapshot.frame
            let now = ProcessInfo.processInfo.systemUptime
            if previousFrame != frame {
                previousFrame = frame
                stableSince = now
            }
            if let stableSince, now - stableSince >= 0.35 { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForPauseSheet(_ scrollView: XCUIElement, firstDuration: XCUIElement,
                                   timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if scrollView.exists && firstDuration.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return scrollView.exists && firstDuration.exists
    }

    private func attachMenuActivationFailure(_ title: String, element: XCUIElement, in app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = title
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let elementFrame = element.exists ? NSCoder.string(for: element.frame) : "<element absent>"
        let scroll = app.scrollViews["pause-sharing-scroll"]
        let scrollFrame = scroll.exists ? NSCoder.string(for: scroll.frame) : "<sheet absent>"
        let duration = app.buttons["pause-duration-3600"]
        let durationFrame = duration.exists ? NSCoder.string(for: duration.frame) : "<duration absent>"
        let geometry = XCTAttachment(string: "activated element frame=\(elementFrame); sheet scroll frame=\(scrollFrame); first duration frame=\(durationFrame); app window=\(NSCoder.string(for: app.windows.firstMatch.frame))")
        geometry.name = "Menu activation geometry"
        geometry.lifetime = .keepAlways
        add(geometry)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Menu activation hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
