import XCTest

/// Opt-in, bounded observations of Apple-owned simulator services. These probes never
/// enter credentials, confirm a purchase, or claim that an external service succeeded.
final class SimulatorAppleServiceProbeTests: XCTestCase {
    private var enabled: Bool { ProcessInfo.processInfo.environment["TRUST_SIMULATOR_APPLE_PROBE"] == "1" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard enabled else { throw XCTSkip("Set TRUST_SIMULATOR_APPLE_PROBE=1 to run external Apple service probes.") }
    }

    func testAttemptAppleSignInAndRecordBoundary() throws {
        let app = probeApplication()
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchArguments += ["-trust.appLanguage", "en"]
        app.launch()

        let signIn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sign in with Apple")).firstMatch
        XCTAssertTrue(signIn.waitForExistence(timeout: 15), "Fresh reset-auth launch should show the real Apple sign-in action.")
        XCTAssertTrue(signIn.isEnabled)
        XCTAssertFalse(app.staticTexts["age-gate-title"].exists)
        XCTAssertFalse(app.staticTexts["app-transaction-title"].exists)
        signIn.tap()

        let observed = waitForAppleUI(in: app, timeout: 25)
        attachNote(name: "Attempt Apple sign-in boundary", observation: observed)
        // Apple account-required alerts are owned by SpringBoard, not the app process.
        let appleAlert = springBoardAccountAlert()
        var dismissedSystemUI = false
        if appleAlert.waitForExistence(timeout: 2) {
            let close = appleAlert.buttons.matching(NSPredicate(format: "label ==[c] %@", "Close")).firstMatch
            if close.exists { close.tap(); dismissedSystemUI = true }
        } else {
            let cancel = systemCancel(in: app)
            if cancel.waitForExistence(timeout: 1) { cancel.tap(); dismissedSystemUI = true }
            let notNow = systemBoundaryButtons(in: app).matching(NSPredicate(format: "label CONTAINS[c] %@", "Not Now")).firstMatch
            if notNow.waitForExistence(timeout: 1) { notNow.tap(); dismissedSystemUI = true }
        }

        let appleAlertGone = waitForSpringBoardAlertDismissal(appleAlert, timeout: 5)
        let signInReturned = signIn.waitForExistence(timeout: 10)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: signIn)
        let signInEnabled = XCTWaiter.wait(for: [enabled], timeout: 5) == .completed
        let noOverlay = noSystemOverlay(app)
        let signInReady = appleAlertGone && signInReturned && signInEnabled && noOverlay
        XCTAssertFalse(app.staticTexts["age-gate-title"].exists)
        XCTAssertFalse(app.staticTexts["app-transaction-title"].exists)
        let exitObservation: String
        if signInReady && dismissedSystemUI {
            exitObservation = "The system account boundary was closed; the real sign-in action remains enabled and no system overlay remains. No authentication success occurred."
        } else if signInReady && observed.hasPrefix("No sheet or alert") {
            exitObservation = "No sheet or alert modal appeared; the unauthenticated sign-in action remains hittable. The external sign-in attempt outcome is unclassified."
        } else {
            exitObservation = "Native Apple boundary dismissal could not be verified; outcome is unclassified and no app-only screenshot is retained."
        }
        attachNote(name: "Apple sign-in cancellation state", observation: exitObservation)
        XCTAssertTrue(signInReady, "The unauthenticated sign-in screen must return without a system overlay.")
        if signInReady {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Apple sign-in cancellation state - privacy-safe app screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testAttemptStoreKitPaywallWithoutPurchase() throws {
        let app = probeApplication()
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_DEMO"] = "1"
        app.launchEnvironment["TRUST_SCREENSHOT"] = "paywall"
        app.launchArguments += ["-trust.appLanguage", "en"]
        app.launch()

        let heading = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Plus")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 12), "The supported demo screenshot route should open the actual paywall UI.")
        let state = waitForPaywallState(app, timeout: 20)
        attachNote(name: "Attempt StoreKit paywall boundary", observation: state)
        if noSystemOverlay(app) && app.buttons["plus-close"].isHittable {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Attempt StoreKit paywall boundary - app-only screenshot"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        // A restore request is non-purchasing. Tap only the real StoreKit restore control
        // if SubscriptionStoreView exposes it; never select a subscription purchase option.
        let restore = app.buttons.matching(NSPredicate(format: "label ==[c] %@ OR label ==[c] %@", "Restore Purchases", "Restore Subscription")).firstMatch
        var restoreObservation = "Restore was not exposed as an accessibility button by StoreKit."
        if restore.waitForExistence(timeout: 1) {
            restore.tap()
            restoreObservation = waitForRestoreBoundary(app, timeout: 7)
        }
        attachNote(name: "StoreKit restore boundary", observation: restoreObservation)

        let close = app.buttons["plus-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 2), "The actual paywall Close control must remain available.")
        XCTAssertTrue(noSystemOverlay(app), "A system account or error boundary must be gone before leaving the paywall.")
        XCTAssertTrue(close.isHittable, "The actual paywall Close control must be hittable.")
        close.tap()
        XCTAssertTrue(waitForPaywallDismissal(app, timeout: 5),
                       "Closing the paywall must dismiss its StoreKit subscription view.")
        XCTAssertFalse(app.buttons["plus-close"].exists, "Closing the paywall must leave the paywall screen.")
        attachNote(name: "StoreKit no-purchase exit", observation: "Paywall closed successfully; no purchase was completed.")
    }

    private func waitForAppleUI(in app: XCUIApplication, timeout: TimeInterval) -> String {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            let springboardAlert = springBoardAccountAlert()
            if springboardAlert.exists {
                let title = springboardAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sign in to your Apple Account")).firstMatch
                let body = springboardAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "You need to sign in to your Apple Account in Settings")).firstMatch
                if title.exists && body.exists {
                    return "SpringBoard displayed the Apple Account-required alert (‘Sign in to your Apple Account’ / ‘You need to sign in to your Apple Account in Settings.’). No credentials were entered."
                }
                return "SpringBoard displayed an account alert after the Apple sign-in attempt; exact Apple Account-required copy was not confirmed. No credentials were entered."
            }
            if let modal = systemBoundary(in: app) {
                let labels = modal.descendants(matching: .any).allElementsBoundByIndex
                    .filter { $0.exists && !$0.label.isEmpty }.map(\.label)
                let kind: String
                if labels.contains(where: { $0.localizedCaseInsensitiveContains("error") || $0.localizedCaseInsensitiveContains("unavailable") }) {
                    kind = "generic modal with error-like text"
                } else if labels.contains(where: { $0.localizedCaseInsensitiveContains("account") || $0.localizedCaseInsensitiveContains("sign in") }) {
                    kind = "generic account/sign-in modal"
                } else {
                    kind = "generic modal"
                }
                return "An app or system \(kind) appeared after the Apple sign-in attempt; Apple ownership could not be proven, so the result is unclassified. No credentials were entered."
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return "No sheet or alert modal was observable within the bounded wait. This does not indicate successful Apple sign-in."
    }

    private func waitForPaywallState(_ app: XCUIApplication, timeout: TimeInterval) -> String {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            let labels = visibleLabels(in: app)
            let error = app.descendants(matching: .any)["plus-store-error"]
            if error.exists {
                return "Product request error appeared in plus-store-error: \(safeStoreError(error.label))."
            }
            if let price = labels.first(where: { hasPrice($0) }) {
                return "StoreKit exposed a native price-bearing subscription option: \(price). No purchase was selected."
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return "No catalog result was observable: neither plus-store-error nor a native price-bearing subscription option appeared (20-second boundary). External StoreKit success was not inferred."
    }

    private func waitForRestoreBoundary(_ app: XCUIApplication, timeout: TimeInterval) -> String {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            let springboardAlert = springBoardAccountAlert()
            if springboardAlert.exists {
                // Detect credential fields by element type only; never inspect their values.
                let requiresCredentials = springboardAlert.textFields.count > 0
                    && springboardAlert.secureTextFields.count > 0
                if requiresCredentials {
                    let observation = "Restore reached a SpringBoard Apple Account credential form with Apple Account and password fields. Field contents were not read; credentials were not entered."
                    let cancel = springboardAlert.buttons.matching(NSPredicate(format: "label ==[c] %@", "Cancel")).firstMatch
                    if cancel.exists { cancel.tap() }
                    return observation + (waitForSpringBoardAlertDismissal(springboardAlert, timeout: 3)
                        ? " Credential form canceled and alert dismissed."
                        : " Credential form dismissal was not verified.")
                }
                let title = springboardAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Sign in to your Apple Account")).firstMatch
                let body = springboardAlert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "You need to sign in to your Apple Account in Settings")).firstMatch
                let observation = title.exists && body.exists
                    ? "Restore surfaced SpringBoard's Apple Account-required alert. No account was selected."
                    : "Restore surfaced a SpringBoard account alert with unclassified copy."
                let close = springboardAlert.buttons.matching(NSPredicate(format: "label ==[c] %@", "Close")).firstMatch
                if close.exists { close.tap() }
                return observation + (waitForSpringBoardAlertDismissal(springboardAlert, timeout: 3) ? " Alert closed." : " Alert dismissal not verified.")
            }
            if let modal = systemBoundary(in: app) {
                let labels = modal.descendants(matching: .any).allElementsBoundByIndex
                    .filter { $0.exists && !$0.label.isEmpty }.map(\.label)
                if labels.contains(where: { $0.localizedCaseInsensitiveContains("account") }) {
                    return "Restore produced an account-required modal boundary. Provider ownership could not be proven; no account was selected."
                }
                if labels.contains(where: { $0.localizedCaseInsensitiveContains("error") }) {
                    return "Restore produced an error modal boundary. Provider ownership could not be proven."
                }
                return "Restore produced a modal boundary with no classified account/error result. Provider ownership could not be proven."
            }
            let error = app.descendants(matching: .any)["plus-store-error"]
            if error.exists { return "Restore exposed app error: \(safeStoreError(error.label))." }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return "No account/error modal or plus-store-error was observable within 7 seconds after Restore."
    }

    private func systemBoundaryButtons(in app: XCUIApplication) -> XCUIElementQuery {
        (systemBoundary(in: app) ?? app.alerts.firstMatch).buttons
    }

    private func systemBoundary(in app: XCUIApplication) -> XCUIElement? {
        if app.sheets.firstMatch.exists { return app.sheets.firstMatch }
        if app.alerts.firstMatch.exists { return app.alerts.firstMatch }
        return nil
    }

    private func noSystemOverlay(_ app: XCUIApplication) -> Bool {
        !app.sheets.firstMatch.exists && !app.alerts.firstMatch.exists
            && springBoardApp().alerts.count == 0
    }

    private func waitForPaywallDismissal(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !app.buttons["plus-close"].exists
                && !app.descendants(matching: .any)["plus-subscription-store"].exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !app.buttons["plus-close"].exists
            && !app.descendants(matching: .any)["plus-subscription-store"].exists
    }

    private func systemCancel(in app: XCUIApplication) -> XCUIElement {
        systemBoundaryButtons(in: app).matching(NSPredicate(format: "label CONTAINS[c] %@", "Cancel")).firstMatch
    }

    private func springBoardApp() -> XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    private func springBoardAccountAlert() -> XCUIElement {
        springBoardApp().alerts.firstMatch
    }

    private func waitForSpringBoardAlertDismissal(_ alert: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if !alert.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !alert.exists
    }

    private func hasPrice(_ text: String) -> Bool {
        text.range(of: #"(?:[$€£¥]\s?\d|\d[\.,]?\d*\s?(?:USD|EUR|GBP|JPY))"#,
                   options: .regularExpression) != nil
    }

    private func safeStoreError(_ text: String) -> String {
        // The app's localized StoreKit request errors are generic service descriptions.
        // Drop any line that resembles an address or token before retaining exact copy.
        let safe = text.components(separatedBy: .newlines).filter {
            !$0.contains("@") && !$0.localizedCaseInsensitiveContains("token")
        }
        return safe.joined(separator: " ").isEmpty ? "[redacted unsafe error text]" : safe.joined(separator: " ")
    }

    private func probeApplication() -> XCUIApplication {
        let bundle = ProcessInfo.processInfo.environment["TRUST_PROBE_APP_BUNDLE_IDENTIFIER"]
            ?? "com.collapsetechnologies.trust.staging"
        return XCUIApplication(bundleIdentifier: bundle)
    }

    private func visibleLabels(in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any).allElementsBoundByIndex
            .filter { $0.exists && !$0.label.isEmpty }
            .map(\.label)
    }

    private func attachNote(name: String, observation: String) {
        let note = XCTAttachment(string: observation)
        note.name = name + " - observation"
        note.lifetime = .keepAlways
        add(note)
    }
}
