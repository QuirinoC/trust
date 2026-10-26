import Foundation
import XCTest

/// Opt-in, real-service APNs lane. The runner supplies a fresh local Development API
/// with sandbox APNs credentials, a fresh disposable PostgreSQL database, and a new
/// simulator. This test never uses simctl push or a synthetic notification payload.
final class RealPushAPNSE2ETests: XCTestCase {
    private var api: RealPushTestAPI!

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard let baseURL = ProcessInfo.processInfo.environment["TRUST_UI_TEST_BASE_URL"],
              baseURL == "http://127.0.0.1:5089",
              ProcessInfo.processInfo.environment["TRUST_REAL_PUSH_E2E"] == "1" else {
            throw XCTSkip("Run only through the isolated real APNs runner on loopback port 5089.")
        }
        api = RealPushTestAPI(baseURL: baseURL)
        XCTAssertTrue(api.healthIsAvailable(), "The isolated Development API/proxy must be available.")
        XCTAssertTrue(api.developmentOTPWithoutSMSIsEnabled(), "The local API must provide Development OTP without SMS.")
    }

    func testRealSandboxAPNsForegroundAndBackgroundLookRoute() throws {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let mainName = "PushMain\(suffix)"
        let peerName = "PushPeer\(suffix)"
        let backgroundViewerName = "PushView\(suffix)"
        let mainDevice = "push-main-\(suffix)"
        let peerDevice = "push-peer-\(suffix)"
        let backgroundViewerDevice = "push-view-\(suffix)"
        let firstPhoneSlot = Int(suffix.prefix(2), radix: 16)! % 100
        let mainPhone = "+155555501\(String(format: "%02d", firstPhoneSlot))"
        let peerPhone = "+155555501\(String(format: "%02d", (firstPhoneSlot + 1) % 100))"
        let backgroundViewerPhone = "+155555501\(String(format: "%02d", (firstPhoneSlot + 2) % 100))"
        let main = try XCTUnwrap(api.createOnboardedAccount(
            name: mainName, deviceID: mainDevice, handle: "pm\(suffix)", phone: mainPhone
        ))
        let peer = try XCTUnwrap(api.createOnboardedAccount(
            name: peerName, deviceID: peerDevice, handle: "pp\(suffix)", phone: peerPhone
        ))
        let backgroundViewer = try XCTUnwrap(api.createOnboardedAccount(
            name: backgroundViewerName,
            deviceID: backgroundViewerDevice,
            handle: "pv\(suffix)",
            phone: backgroundViewerPhone
        ))
        defer {
            api.deleteAccount(token: backgroundViewer.token)
            api.deleteAccount(token: peer.token)
            api.deleteAccount(token: main.token)
        }

        XCTAssertEqual(api.createConnectionRequest(recipientID: main.personID, token: peer.token), 200)
        let request = try XCTUnwrap(api.connectionRequests(token: main.token)?["incoming"] as? [[String: Any]])
            .first
        let requestID = try XCTUnwrap(request?["id"] as? String)
        XCTAssertEqual(api.acceptConnectionRequest(id: requestID, token: main.token), 204)
        XCTAssertEqual(api.setResting("sealed", personID: peer.personID, owner: main), 204)
        XCTAssertEqual(api.createConnectionRequest(recipientID: main.personID, token: backgroundViewer.token), 200)
        let backgroundRequest = try XCTUnwrap(api.connectionRequests(token: main.token)?["incoming"] as? [[String: Any]])
            .first(where: { ($0["otherParty"] as? [String: Any])?["accountId"] as? String == backgroundViewer.personID })
        let backgroundRequestID = try XCTUnwrap(backgroundRequest?["id"] as? String)
        XCTAssertEqual(api.acceptConnectionRequest(id: backgroundRequestID, token: main.token), 204)
        XCTAssertEqual(api.setResting("sealed", personID: backgroundViewer.personID, owner: main), 204)
        XCTAssertEqual(api.uploadLocation(token: main.token), 204)

        let app = launchDevelopmentApp(deviceID: mainDevice, displayName: mainName)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["tab-you"].tap()
        let permissionStatus = app.staticTexts["notifications-permission-status"]
        XCTAssertTrue(permissionStatus.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(permissionStatus.label.localizedCaseInsensitiveContains("not enabled"),
                      "The runner must use a fresh simulator whose notification permission has not been pre-authorized.")
        let enable = app.buttons["enable-notifications"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5), app.debugDescription)
        let youScrollView = app.scrollViews.firstMatch
        for _ in 0..<5 where !enable.isHittable {
            if youScrollView.exists {
                youScrollView.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(enable.isHittable, "Enable alerts should be reachable on the You screen.")
        enable.tap()
        allowNotificationPermissionIfPrompted(in: app)
        XCTAssertTrue(waitUntil(timeout: 15) {
            permissionStatus.exists && permissionStatus.label.localizedCaseInsensitiveContains("allowed")
        }, "The explicit Enable alerts action should produce an authorized status.")
        XCTAssertTrue(waitUntil(timeout: 30) { api.sandboxPushRegistrationAckCount() >= 1 },
                      "The local API must acknowledge a sandbox APNs device registration before the first Look.")

        // A foreground Look must reach the real app delegate and display a system
        // notification. The exact notification must then route into Activity.
        let foregroundLookID = try XCTUnwrap(api.sendLook(subjectID: main.personID, token: peer.token))
        XCTAssertTrue(api.hasLookEvent(
            id: foregroundLookID, viewerID: peer.personID, subjectID: main.personID, token: main.token
        ), "The foreground Look should be recorded by the Development API before its notification is tapped.")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let firstNotification = notificationElement(in: springboard, containing: peerName)
        XCTAssertTrue(firstNotification.waitForExistence(timeout: 35),
                      "No genuine sandbox APNs foreground banner appeared. simctl push is not used.\n\(springboard.debugDescription)")
        attachScreenshot("Foreground APNs banner before tap", from: springboard)
        firstNotification.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.buttons["tab-log"].isSelected },
                      "Tapping the Look notification should route to Activity.\n\(app.debugDescription)")
        let foregroundEvent = activityEvent(in: app, id: foregroundLookID)
        XCTAssertTrue(waitUntil(timeout: 15) { foregroundEvent.exists && foregroundEvent.isHittable },
                      "The foreground notification should open a refreshed Activity containing its receipt.\n\(app.debugDescription)")
        attachScreenshot("Foreground APNs tap opened Activity", from: app)

        // Deliver a second Look while the app is backgrounded. Its banner/notification
        // center entry must open the same safe Activity destination when tapped.
        app.buttons["tab-you"].tap()
        XCUIDevice.shared.press(.home)
        let backgroundLookID = try XCTUnwrap(api.sendLook(subjectID: main.personID, token: backgroundViewer.token))
        XCTAssertNotEqual(foregroundLookID, backgroundLookID,
                          "The two distinct viewers must create distinct backend Look events.")
        XCTAssertTrue(api.hasLookEvent(
            id: foregroundLookID, viewerID: peer.personID, subjectID: main.personID, token: main.token
        ))
        XCTAssertTrue(api.hasLookEvent(
            id: backgroundLookID, viewerID: backgroundViewer.personID, subjectID: main.personID, token: main.token
        ), "The background Look should be recorded before its notification is tapped.")
        let backgroundNotification = notificationElement(in: springboard, containing: backgroundViewerName)
        XCTAssertTrue(backgroundNotification.waitForExistence(timeout: 35),
                      "No genuine sandbox APNs background alert arrived.\n\(springboard.debugDescription)")
        attachScreenshot("Background APNs notification before tap", from: springboard)
        backgroundNotification.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.buttons["tab-log"].isSelected },
                      "Tapping a background Look alert should route to Activity.\n\(app.debugDescription)")
        let backgroundEvent = activityEvent(in: app, id: backgroundLookID)
        XCTAssertTrue(waitUntil(timeout: 15) {
            foregroundEvent.exists && backgroundEvent.exists && foregroundEvent.isHittable && backgroundEvent.isHittable
        }, "Activity should show both distinct Look receipts after the background notification tap.\n\(app.debugDescription)")
        attachScreenshot("Background APNs tap opened Activity", from: app)
    }

    func testRealSandboxAPNsNotificationSettingsRecovery() throws {
        let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let mainName = "RecoveryMain\(suffix)"
        let peerName = "RecoveryPeer\(suffix)"
        let mainDevice = "push-recovery-main-\(suffix)"
        let peerDevice = "push-recovery-peer-\(suffix)"
        let firstPhoneSlot = Int(suffix.prefix(2), radix: 16)! % 100
        let mainPhone = "+155555501\(String(format: "%02d", firstPhoneSlot))"
        let peerPhone = "+155555501\(String(format: "%02d", (firstPhoneSlot + 1) % 100))"
        let main = try XCTUnwrap(api.createOnboardedAccount(
            name: mainName, deviceID: mainDevice, handle: "rm\(suffix)", phone: mainPhone
        ))
        let peer = try XCTUnwrap(api.createOnboardedAccount(
            name: peerName, deviceID: peerDevice, handle: "rp\(suffix)", phone: peerPhone
        ))
        defer {
            api.deleteAccount(token: peer.token)
            api.deleteAccount(token: main.token)
        }

        XCTAssertEqual(api.createConnectionRequest(recipientID: main.personID, token: peer.token), 200)
        let request = try XCTUnwrap(api.connectionRequests(token: main.token)?["incoming"] as? [[String: Any]])
            .first
        let requestID = try XCTUnwrap(request?["id"] as? String)
        XCTAssertEqual(api.acceptConnectionRequest(id: requestID, token: main.token), 204)
        XCTAssertEqual(api.setResting("sealed", personID: peer.personID, owner: main), 204)
        XCTAssertEqual(api.uploadLocation(token: main.token), 204)

        XCTAssertEqual(api.sandboxPushRegistrationAckCount(), 0,
                       "A new isolated database must have no prior notification registration.")
        let app = launchDevelopmentApp(deviceID: mainDevice, displayName: mainName)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab-you"].waitForExistence(timeout: 30), app.debugDescription)
        app.buttons["tab-you"].tap()
        let permissionStatus = app.staticTexts["notifications-permission-status"]
        XCTAssertTrue(permissionStatus.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(permissionStatus.label.localizedCaseInsensitiveContains("not enabled"),
                      "Use a fresh simulator with notifications not previously decided.")
        let enable = app.buttons["enable-notifications"]
        XCTAssertTrue(enable.waitForExistence(timeout: 8), app.debugDescription)
        let youScrollView = app.scrollViews["you-scroll"]
        for _ in 0..<5 where !enable.isHittable {
            youScrollView.swipeUp()
        }
        XCTAssertTrue(enable.isHittable, "Enable alerts must be reachable on You.\n\(app.debugDescription)")
        enable.tap()
        denyNotificationPermission(in: app)

        XCTAssertTrue(waitUntil(timeout: 10) {
            permissionStatus.exists && permissionStatus.label.localizedCaseInsensitiveContains("off in settings")
        }, "Declining the system prompt should show Off in Settings.\n\(app.debugDescription)")
        let settingsAction = app.buttons["open-notification-settings"]
        XCTAssertTrue(settingsAction.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<5 where !settingsAction.isHittable {
            youScrollView.swipeUp()
        }
        XCTAssertTrue(settingsAction.isHittable, app.debugDescription)
        XCTAssertEqual(api.sandboxPushRegistrationAckCount(), 0,
                       "A denied installation must not be registered as an APNs recipient.")
        attachScreenshot("Notifications denied with Settings recovery action", from: app)

        settingsAction.tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(waitUntil(timeout: 12) { settings.state == .runningForeground },
                      "Open Settings should show the native app Settings page.\n\(settings.debugDescription)")
        let allowNotifications = settings.switches.matching(
            NSPredicate(format: "label ==[c] %@", "Allow Notifications")
        ).firstMatch
        if !waitUntil(timeout: 10) { allowNotifications.exists && allowNotifications.isHittable } {
            attachScreenshot("Direct Notifications Settings route did not show its switch", from: settings)
            attachText("Direct Notifications Settings route hierarchy", settings.debugDescription)
            openTrustNotificationsSettingsFromApps(in: settings)
        }
        XCTAssertTrue(waitUntil(timeout: 10) { allowNotifications.exists && allowNotifications.isHittable },
                      "The native Trust Notifications page should expose Allow Notifications.\n\(settings.debugDescription)")
        if !isSwitchOn(allowNotifications) { allowNotifications.tap() }
        XCTAssertTrue(waitUntil(timeout: 10) { isSwitchOn(allowNotifications) },
                      "Allow Notifications must be on in system Settings.\n\(settings.debugDescription)")
        attachScreenshot("Allow Notifications enabled in iOS Settings", from: settings)

        app.activate()
        XCTAssertTrue(waitUntil(timeout: 15) {
            permissionStatus.exists && permissionStatus.label.localizedCaseInsensitiveContains("allowed")
        }, "Returning from Settings should refresh Trust's notification permission status.\n\(app.debugDescription)")
        attachScreenshot("Notifications allowed after returning to Trust", from: app)
        XCTAssertTrue(waitUntil(timeout: 30) { api.sandboxPushRegistrationAckCount() >= 1 },
                      "Returning from Settings should register the current installation with the local API.")

        let lookID = try XCTUnwrap(api.sendLook(subjectID: main.personID, token: peer.token))
        XCTAssertTrue(api.hasLookEvent(
            id: lookID, viewerID: peer.personID, subjectID: main.personID, token: main.token
        ), "The recovery Look must be recorded by the local API.")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notification = notificationElement(in: springboard, containing: peerName)
        XCTAssertTrue(notification.waitForExistence(timeout: 35),
                      "A genuine APNs notification should arrive after Settings re-enables alerts.\n\(springboard.debugDescription)")
        attachScreenshot("Settings recovery APNs notification before tap", from: springboard)
        notification.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { app.buttons["tab-log"].isSelected },
                      "Tapping the recovered APNs notification should route to Activity.\n\(app.debugDescription)")
        let event = activityEvent(in: app, id: lookID)
        XCTAssertTrue(waitUntil(timeout: 15) { event.exists && event.isHittable },
                      "Activity should show the recovered Look receipt after tapping its notification.\n\(app.debugDescription)")
        attachScreenshot("Settings recovery APNs receipt in Activity", from: app)
    }

    private func activityEvent(in app: XCUIApplication, id: UUID) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "activity-event-\(id.uuidString)")
            .firstMatch
    }

    private func attachScreenshot(_ name: String, from application: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: application.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachText(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func notificationElement(in springboard: XCUIApplication, containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let notification = springboard.descendants(matching: .any).matching(predicate).firstMatch
        if notification.waitForExistence(timeout: 5) { return notification }

        // A transient banner may have expired before XCTest queried SpringBoard.
        // Open Notification Center and look for the server-generated alert there.
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        let end = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.1, thenDragTo: end)
        return springboard.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func allowNotificationPermissionIfPrompted(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAllow = springboard.alerts.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Allow")
        ).firstMatch
        let appAllow = app.alerts.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Allow")
        ).firstMatch
        if appAllow.waitForExistence(timeout: 2) {
            appAllow.tap()
        } else if systemAllow.waitForExistence(timeout: 8) {
            systemAllow.tap()
        }
        XCTAssertTrue(waitUntil(timeout: 10) {
            app.staticTexts["notifications-permission-status"].exists
                && !app.buttons["enable-notifications"].isHittable
        }, "The system permission prompt should finish before the test requests a real APNs notification.")
    }

    private func denyNotificationPermission(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deniedSystemChoice = springboard.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Don't Allow", "Don’t Allow")
        ).firstMatch
        let deniedAppChoice = app.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Don't Allow", "Don’t Allow")
        ).firstMatch
        if deniedAppChoice.waitForExistence(timeout: 2) {
            deniedAppChoice.tap()
        } else {
            XCTAssertTrue(deniedSystemChoice.waitForExistence(timeout: 8),
                          "The first explicit Enable alerts action should show the system permission prompt.\n\(springboard.debugDescription)")
            deniedSystemChoice.tap()
        }
        XCTAssertTrue(waitUntil(timeout: 10) {
            app.staticTexts["notifications-permission-status"].exists
                && app.staticTexts["notifications-permission-status"].label.localizedCaseInsensitiveContains("off in settings")
        }, "Trust should reflect the denied notification permission.\n\(app.debugDescription)")
    }

    private func openTrustNotificationsSettingsFromApps(in settings: XCUIApplication) {
        let trustNotifications = settings.switches.matching(
            NSPredicate(format: "label ==[c] %@", "Allow Notifications")
        ).firstMatch
        if trustNotifications.exists && trustNotifications.isHittable { return }

        // The app-specific notification URL can resume Settings at any prior
        // page. Normalize only through visible native navigation controls.
        let settingsRoot = settings.navigationBars["Settings"]
        let appsPage = settings.navigationBars["Apps"]
        let trustPage = settings.navigationBars["Trust"]
        let trustBundleRow = settings.descendants(matching: .any)["com.collapsetechnologies.trust"]
        let appsSearchField = settings.searchFields.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Apps")
        ).firstMatch
        func isAppsSearchState() -> Bool {
            trustBundleRow.exists || appsSearchField.exists
        }
        for _ in 0..<6 where !settingsRoot.exists && !appsPage.exists && !trustPage.exists && !isAppsSearchState() {
            let back = settings.navigationBars.buttons.firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
            _ = waitUntil(timeout: 3, condition: {
                settingsRoot.exists || appsPage.exists || trustPage.exists || isAppsSearchState()
            })
        }

        if trustPage.exists {
            openNotificationsRow(inTrustSettings: settings)
            return
        }

        // The root may not be visible if Settings resumed the Apps page.
        // Skip the Apps button in that case; otherwise scroll the root list
        // until its native Apps row is visible.
        let appsID = settings.buttons["com.apple.settings.apps"]
        let appsLabel = settings.buttons["Apps"]
        if !appsPage.exists && !isAppsSearchState() {
            let list = settings.collectionViews.firstMatch
            for _ in 0..<12 {
                if (appsID.exists && appsID.isHittable) || (appsLabel.exists && appsLabel.isHittable) { break }
                if list.exists { list.swipeUp(velocity: .slow) }
            }
            let appsAction = appsID.exists && appsID.isHittable ? appsID : appsLabel
            guard appsAction.exists && appsAction.isHittable else {
                attachScreenshot("Settings fallback could not find Apps", from: settings)
                attachText("Settings fallback Apps hierarchy", settings.debugDescription)
                XCTFail("Settings fallback should expose Apps from the current Settings page.\n\(settings.debugDescription)")
                return
            }
            appsAction.tap()
        }

        guard waitUntil(timeout: 10, condition: { appsPage.exists || isAppsSearchState() }) else {
            attachScreenshot("Settings did not navigate to Apps", from: settings)
            attachText("Settings Apps transition hierarchy", settings.debugDescription)
            XCTFail("Native Settings should open the Apps page.\n\(settings.debugDescription)")
            return
        }
        let trustNameRow = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Trust")
        ).firstMatch
        let searchField = settings.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else {
            attachScreenshot("Settings Apps search field missing", from: settings)
            attachText("Settings Apps search field hierarchy", settings.debugDescription)
            XCTFail("Settings Apps should provide search to locate Trust.\n\(settings.debugDescription)")
            return
        }
        if !(searchField.value as? String ?? "").localizedCaseInsensitiveContains("trust") {
            searchField.tap()
            if let current = searchField.value as? String, !current.isEmpty {
                searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            searchField.typeText("Trust")
        }
        let searchButton = settings.keyboards.buttons.matching(
            NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Search", "Go")
        ).firstMatch
        if searchButton.exists && searchButton.isHittable { searchButton.tap() }

        func trustRow() -> XCUIElement? {
            if trustBundleRow.exists && trustBundleRow.isHittable { return trustBundleRow }
            if trustNameRow.exists && trustNameRow.isHittable { return trustNameRow }
            return nil
        }
        guard waitUntil(timeout: 15, condition: { trustRow()?.isHittable == true }) else {
            attachScreenshot("Settings Apps search did not find Trust", from: settings)
            attachText("Settings Apps search diagnostics", "Search query: Trust\n\(settings.debugDescription)")
            XCTFail("Settings Apps search should return the Trust app row.\n\(settings.debugDescription)")
            return
        }
        guard let row = trustRow() else {
            attachScreenshot("Settings Apps fallback could not find Trust", from: settings)
            attachText("Settings Apps fallback hierarchy", settings.debugDescription)
            XCTFail("Settings Apps did not expose Trust.")
            return
        }
        XCTAssertTrue(waitForStableHitTarget(row, timeout: 5),
                      "Trust must be stable and visible before opening its settings.")
        row.tap()
        let notificationsRow = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Notifications")
        ).firstMatch
        var reachedNotificationsEntry = waitUntil(timeout: 8, condition: {
            notificationsRow.exists && notificationsRow.isHittable
        })
        if !reachedNotificationsEntry && row.exists && row.isHittable {
            attachScreenshot("Trust result remained visible after native row tap", from: settings)
            attachText("Trust result tap recovery hierarchy", settings.debugDescription)
            let frame = row.frame
            let window = settings.windows.firstMatch.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if frame.width > 0, frame.height > 0, window.contains(center) {
                settings.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: center.x - window.minX, dy: center.y - window.minY))
                    .tap()
                reachedNotificationsEntry = waitUntil(timeout: 8, condition: {
                    notificationsRow.exists && notificationsRow.isHittable
                })
            }
        }
        guard reachedNotificationsEntry else {
            attachScreenshot("Settings did not open Trust app details", from: settings)
            attachText("Settings Trust app transition hierarchy", settings.debugDescription)
            XCTFail("Selecting the Trust result should expose its Notifications setting.\n\(settings.debugDescription)")
            return
        }
        notificationsRow.tap()
        let allowSwitch = settings.switches.matching(
            NSPredicate(format: "label ==[c] %@", "Allow Notifications")
        ).firstMatch
        XCTAssertTrue(waitUntil(timeout: 12, condition: { allowSwitch.exists && allowSwitch.isHittable }),
                      "Trust's native Notifications settings should expose Allow Notifications.\n\(settings.debugDescription)")
    }

    private func openNotificationsRow(inTrustSettings settings: XCUIApplication) {
        let notificationsRow = settings.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "Notifications")
        ).firstMatch
        guard waitUntil(timeout: 12, condition: {
            notificationsRow.exists && notificationsRow.isHittable
        }) else {
            attachScreenshot("Trust app Settings did not expose Notifications", from: settings)
            attachText("Trust app Settings hierarchy", settings.debugDescription)
            XCTFail("Trust's native app settings should expose Notifications.\n\(settings.debugDescription)")
            return
        }
        notificationsRow.tap()
        let allowSwitch = settings.switches.matching(
            NSPredicate(format: "label ==[c] %@", "Allow Notifications")
        ).firstMatch
        XCTAssertTrue(waitUntil(timeout: 12) { allowSwitch.exists && allowSwitch.isHittable },
                      "Trust's native Notifications settings should expose Allow Notifications.\n\(settings.debugDescription)")
    }

    private func isSwitchOn(_ element: XCUIElement) -> Bool {
        let value = String(describing: element.value ?? "").lowercased()
        return value == "1" || value == "on" || value == "true"
    }

    private func launchDevelopmentApp(deviceID: String, displayName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-trust.appLanguage", "en"]
        app.launchEnvironment["TRUST_BASE_URL"] = "http://127.0.0.1:5089"
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = displayName
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_MODE"] = "1"
        app.launchEnvironment["TRUST_AGE_TEST_RESET_STATE"] = "1"
        app.launch()
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST_RESET_AUTH")
        app.launchEnvironment.removeValue(forKey: "TRUST_AGE_TEST_RESET_STATE")

        let month = app.textFields["age-birth-month"]
        XCTAssertTrue(month.waitForExistence(timeout: 15), app.debugDescription)
        for (field, value) in [
            (month, "01"),
            (app.textFields["age-birth-day"], "01"),
            (app.textFields["age-birth-year"], "1990")
        ] {
            field.tap()
            field.typeText(value)
        }
        let continueButton = app.buttons["age-gate-continue"]
        XCTAssertTrue(waitUntil(timeout: 5) { continueButton.isEnabled }, app.debugDescription)
        continueButton.tap()
        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 45), app.debugDescription)
        return app
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    private func waitForStableHitTarget(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        var previousFrame = CGRect.null
        var stableSamples = 0
        return waitUntil(timeout: timeout) {
            guard element.exists && element.isHittable else {
                previousFrame = element.frame
                stableSamples = 0
                return false
            }
            let currentFrame = element.frame
            if currentFrame == previousFrame {
                stableSamples += 1
            } else {
                stableSamples = 0
            }
            previousFrame = currentFrame
            return stableSamples >= 1
        }
    }
}

private struct RealPushSession {
    let token: String
    let personID: String
}

private struct RealPushAPIResponse {
    let status: Int
    let body: Any?
}

private final class RealPushTestAPI {
    private let baseURL: URL
    private let session = URLSession(configuration: .ephemeral)

    init(baseURL: String) {
        self.baseURL = URL(string: baseURL)!
    }

    func healthIsAvailable() -> Bool {
        let response = request("GET", "/health/live")
        return (200..<300).contains(response.status)
    }

    func developmentOTPWithoutSMSIsEnabled() -> Bool {
        let response = request("GET", "/api/v1/local-test-capabilities")
        return (200..<300).contains(response.status)
            && (response.body as? [String: Any])?["developmentOtpWithoutSms"] as? Bool == true
    }

    func createOnboardedAccount(name: String, deviceID: String, handle: String, phone: String) -> RealPushSession? {
        guard let created = jsonRequest("POST", "/api/v1/session/development", body: [
            "displayName": name, "deviceId": deviceID, "provider": "development"
        ]).body as? [String: Any],
              let token = created["token"] as? String,
              let person = created["you"] as? [String: Any],
              let personID = person["id"] as? String else { return nil }
        guard request("PUT", "/api/v1/me/handle", token: token, body: ["handle": handle]).status == 204,
              verifyPhone(token: token, phone: phone) else { return nil }
        return RealPushSession(token: token, personID: personID)
    }

    private func verifyPhone(token: String, phone: String) -> Bool {
        guard let result = jsonRequest("POST", "/api/v1/me/phone/send", token: token, body: ["phone": phone]).body as? [String: Any],
              let code = result["developmentCode"] as? String else { return false }
        return (200..<300).contains(request("POST", "/api/v1/me/phone/verify", token: token,
                                            body: ["phone": phone, "code": code]).status)
    }

    func createConnectionRequest(recipientID: String, token: String) -> Int {
        request("POST", "/api/v1/connection-requests", token: token, body: ["recipientId": recipientID]).status
    }

    func connectionRequests(token: String) -> [String: Any]? {
        request("GET", "/api/v1/connection-requests", token: token).body as? [String: Any]
    }

    func acceptConnectionRequest(id: String, token: String) -> Int {
        request("POST", "/api/v1/connection-requests/\(id)/accept", token: token).status
    }

    func setResting(_ mode: String, personID: String, owner: RealPushSession) -> Int {
        guard let member = circle(token: owner.token)?["members"] as? [[String: Any]],
              let row = member.first(where: { ($0["person"] as? [String: Any])?["id"] as? String == personID }),
              let connectionID = row["connectionId"] as? String,
              let share = row["share"] as? [String: Any],
              let revision = share["revision"] as? NSNumber else { return 0 }
        return request("PATCH", "/api/v1/people/\(personID)/share", token: owner.token,
                       body: ["connectionId": connectionID, "revision": revision, "resting": mode]).status
    }

    func uploadLocation(token: String) -> Int {
        let now = ISO8601DateFormatter().string(from: Date())
        let point: [String: Any] = ["timestamp": now, "latitude": 47.60, "longitude": -122.33]
        return request("POST", "/api/v1/location", token: token, body: [
            "timestamp": now, "latitude": 47.60, "longitude": -122.33,
            "batteryPercent": 75, "isCharging": false, "points": [point]
        ]).status
    }

    func sendLook(subjectID: String, token: String) -> UUID? {
        let response = request("POST", "/api/v1/looks", token: token,
                               body: ["subjectId": subjectID, "confirmed": true])
        guard response.status == 200,
              let session = response.body as? [String: Any],
              let event = session["event"] as? [String: Any],
              let rawID = event["id"] as? String else { return nil }
        return UUID(uuidString: rawID)
    }

    func hasLookEvent(id: UUID, viewerID: String, subjectID: String, token: String) -> Bool {
        guard let events = circle(token: token)?["lookLog"] as? [[String: Any]] else { return false }
        return events.contains {
            ($0["id"] as? String)?.lowercased() == id.uuidString.lowercased()
                && ($0["viewerId"] as? String)?.lowercased() == viewerID.lowercased()
                && ($0["subjectId"] as? String)?.lowercased() == subjectID.lowercased()
        }
    }

    func sandboxPushRegistrationAckCount() -> Int {
        guard let state = request("GET", "/__test/state").body as? [String: Any],
              let count = state["sandbox_push_registration_ack_count"] as? Int else { return 0 }
        return count
    }

    func deleteAccount(token: String) {
        let status = request("DELETE", "/api/v1/account", token: token).status
        XCTAssertTrue(status == 204 || status == 404, "Disposable account cleanup failed with HTTP \(status).")
    }

    private func circle(token: String) -> [String: Any]? {
        request("GET", "/api/v1/circle", token: token).body as? [String: Any]
    }

    private func jsonRequest(_ method: String, _ path: String, token: String? = nil,
                             body: [String: Any]? = nil) -> RealPushAPIResponse {
        request(method, path, token: token, body: body)
    }

    @discardableResult
    private func request(_ method: String, _ path: String, token: String? = nil,
                         body: [String: Any]? = nil) -> RealPushAPIResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var responseStatus = 0
        var responseBody: Any?
        session.dataTask(with: request) { data, response, _ in
            responseStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, !data.isEmpty { responseBody = try? JSONSerialization.jsonObject(with: data) }
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 22) == .success else { return RealPushAPIResponse(status: 0, body: nil) }
        return RealPushAPIResponse(status: responseStatus, body: responseBody)
    }
}
