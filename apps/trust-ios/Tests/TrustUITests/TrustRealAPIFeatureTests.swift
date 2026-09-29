import CoreLocation
import Foundation
import XCTest

/// Development-only end-to-end lane. It is deliberately pinned to loopback and creates
/// disposable identities that are deleted even when an assertion fails.
final class TrustRealAPIFeatureTests: XCTestCase {
    private let api = LocalTrustAPI()

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard api.hasSafeConfiguration else {
            throw XCTSkip("Set TRUST_UI_TEST_BASE_URL explicitly to the isolated HTTP loopback API on port 5089. Skipping before account creation or phone-send requests.")
        }
        guard api.healthIsAvailable() else {
            throw XCTSkip("The isolated local API on port 5089 is unavailable; skipping its opt-in simulator lane.")
        }
        guard api.developmentOTPWithoutSMSIsEnabled() else {
            throw XCTSkip("The local API is not Development with Twilio unconfigured. Skipping before account creation or any phone-send request.")
        }
    }

    /// Paired acceptance prototype. Run this case simultaneously in two independent
    /// XCTest processes with the same pair ID and roles alice/bob. The accounts are
    /// created from their own app UI; the local API resolves the peer's public handle.
    func testPairedRequestAcceptAndPresenceGrantRole() throws {
        // The pair receives moving Core Simulator routes configured by the harness
        // before launch; this diagnostic uses no XCTest static location override.
        let environment = ProcessInfo.processInfo.environment
        guard let role = environment["TRUST_UI_PAIR_ROLE"], ["alice", "bob"].contains(role),
              let pairID = environment["TRUST_UI_PAIR_ID"], pairID.range(of: "^[a-f0-9]{8}$", options: .regularExpression) != nil else {
            throw XCTSkip("Set TRUST_UI_PAIR_ROLE=alice|bob and one shared eight-hex TRUST_UI_PAIR_ID in both simulator launchd environments.")
        }

        let aliceHandle = "pa\(pairID)a"
        let bobHandle = "pa\(pairID)b"
        let ownHandle = role == "alice" ? aliceHandle : bobHandle
        let peerHandle = role == "alice" ? bobHandle : aliceHandle
        let ownName = role == "alice" ? "PairAlice" : "PairBob"
        let deviceID = "trust-pair-\(pairID)-\(role)"
        let session = try XCTUnwrap(api.developmentSession(name: ownName, deviceID: deviceID))
        // The pair shares server state while the other simulator's UI is still
        // refreshing. The isolated Memory API is stopped after both runners exit.

        let pool = LocalTrustAPI.reservedPhonePool()
        let pairPhoneBase = Int(pairID.prefix(6), radix: 16)! % (pool.count / 2) * 2
        let slot = pairPhoneBase + (role == "alice" ? 0 : 1)
        let phoneDigits = pool[slot]
        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = ownName
        app.launchEnvironment["TRUST_UI_TEST_RESET_AUTH"] = "1"
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launch()

        let handleField = app.textFields.firstMatch
        XCTAssertTrue(handleField.waitForExistence(timeout: 20))
        handleField.tap()
        let suggested = handleField.value as? String ?? ""
        handleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: suggested.count) + ownHandle)
        let continueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Continue")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { continueButton.isEnabled })
        let discoveryToggle = app.switches["onboarding-discovery-toggle"]
        XCTAssertTrue(discoveryToggle.waitForExistence(timeout: 5))
        if !isSwitchOn(discoveryToggle) {
            discoveryToggle.tap()
            XCTAssertTrue(waitUntil(timeout: 5) { self.isSwitchOn(discoveryToggle) }, "Phone discovery should be explicitly enabled before continuing.")
        }
        continueButton.tap()
        let phone = app.textFields["phone-number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 10))
        phone.tap()
        phone.typeText("+1\(phoneDigits)")
        app.buttons["send-phone-code"].tap()
        let codeNotice = app.staticTexts["phone-notice"]
        XCTAssertTrue(codeNotice.waitForExistence(timeout: 10))
        let code = codeNotice.label.filter(\.isNumber)
        XCTAssertEqual(code.count, 6)
        let codeField = app.textFields["phone-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText(code)
        app.buttons["verify-phone-code"].tap()
        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
        let ownAccount = api.circle(token: session.token)?["you"] as? [String: Any]
        XCTAssertEqual(ownAccount?["handle"] as? String, ownHandle)
        XCTAssertEqual(ownAccount?["onboardingComplete"] as? Bool, true, "The API peer should see this simulator account as fully onboarded.")
        XCTAssertEqual(ownAccount?["phoneVerified"] as? Bool, true)
        XCTAssertEqual(ownAccount?["discoveryEnabled"] as? Bool, true, "The test explicitly opts into discoverability on both accounts.")
        app.buttons["tab-you"].tap()
        let ownHandleButton = app.buttons["copy-own-handle"]
        XCTAssertTrue(ownHandleButton.waitForExistence(timeout: 10))
        XCTAssertEqual(ownHandleButton.value as? String, "@\(ownHandle)", "This simulator's UI must remain signed into its own paired identity.")

        if role == "alice" {
            var peerLookup = api.lookupPersonResponse(handle: peerHandle, token: session.token)
            // Handle discovery is intentionally rate-limited (60 searches/minute).
            // Poll slowly and reuse the successful response instead of immediately
            // spending another request from the same budget to fetch the account ID.
            let resolvedPeer = waitUntil(timeout: 60, pollInterval: 2) {
                peerLookup = self.api.lookupPersonResponse(handle: peerHandle, token: session.token)
                return (200..<300).contains(peerLookup.status)
                    && (peerLookup.json as? [String: Any])?["accountId"] as? String != nil
            }
            XCTAssertTrue(resolvedPeer, "Bob's handle should resolve after onboarding. API response: HTTP \(peerLookup.status) \(String(describing: peerLookup.json)); Alice state: \(String(describing: ownAccount))")
            guard let peerID = (peerLookup.json as? [String: Any])?["accountId"] as? String else { XCTFail("Bob's public handle should resolve after onboarding."); return }
            app.buttons["tab-sharing"].tap()
            let add = app.buttons["add-someone-button"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            let phoneLookup = app.textFields["connection-handle"]
            XCTAssertTrue(phoneLookup.waitForExistence(timeout: 8))
            // The paired request uses Bob's verified phone number. Cancellation is
            // covered in the single-UI test, where the peer cannot race acceptance.
            let bobPhoneDigits = pool[pairPhoneBase + 1]
            phoneLookup.typeText("+1 (\(bobPhoneDigits.prefix(3))) \(bobPhoneDigits.dropFirst(3).prefix(3))-\(bobPhoneDigits.suffix(4))")
            XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 12), "A verified exact phone match should resolve to Bob's handle.")
            XCTAssertEqual(app.staticTexts["connection-lookup-handle"].label, "@\(peerHandle)")
            let keyboardDone = app.buttons["Done"]
            if keyboardDone.exists { keyboardDone.tap() }
            let sendRequest = app.buttons["send-connection-request"]
            XCTAssertTrue(sendRequest.waitForExistence(timeout: 5))
            sendRequest.tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                let pending = !(self.api.connectionRequests(token: session.token)?["sent"] as? [[String: Any]] ?? []).isEmpty
                return pending || self.api.member(personID: peerID, token: session.token) != nil
            }, "Sending by phone should create a pending request or Bob should already have accepted it.")
            app.buttons["cancel-add-person"].tap()
            XCTAssertTrue(waitUntil(timeout: 90) { self.api.member(personID: peerID, token: session.token) != nil }, "Bob's UI did not accept the request.")

            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let refreshStartedAt = Date()
            app.swipeDown()
            let memberGroup = app.descendants(matching: .any)["sharing-mode-group-pairbob"]
            XCTAssertTrue(memberGroup.waitForExistence(timeout: 20), "Alice's UI should show Bob after Bob accepts.\n\(app.debugDescription)")
            self.add(XCTAttachment(string: "Alice's Sharing list converged after pull-to-refresh in \(Date().timeIntervalSince(refreshStartedAt)) seconds."))
            let peerNameKey = "pairbob"
            let actions = app.buttons["sharing-actions-\(peerNameKey)"]
            XCTAssertTrue(actions.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(api.member(personID: peerID, token: session.token)?["outboundPresenceGranted"] as? Bool ?? true)
            actions.tap()
            let grant = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Let PairBob know when I’m Home or Away")).firstMatch
            XCTAssertTrue(grant.waitForExistence(timeout: 5))
            grant.tap()
            XCTAssertTrue(waitUntil(timeout: 10) { self.api.member(personID: peerID, token: session.token)?["outboundPresenceGranted"] as? Bool == true })
            XCTAssertTrue(app.staticTexts["Home/Away sharing preference updated."].waitForExistence(timeout: 15), "Wait for the first grant write and refresh to finish before changing the choice again.")
            let sealed = app.buttons["sharing-mode-sealed-pairbob"]
            XCTAssertTrue(sealed.waitForExistence(timeout: 8))
            sealed.tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                self.outboundPresentation(personID: peerID, token: session.token) == "untilTheyLook"
            }, "Alice must choose Sealed before Bob can see her Home/Away status.")
            allowBackgroundLocationIfPrompted(in: app)
            // Mirror Bob's authenticated session so the UI test waits for each
            // Alice status change to become visible to the actual recipient.
            let bobSession = try XCTUnwrap(api.developmentSession(
                name: "PairBob",
                deviceID: "trust-pair-\(pairID)-bob"
            ))
            XCTAssertEqual(bobSession.personID, peerID)
            let homeStatus = app.buttons["home-status-control"]
            XCTAssertTrue(homeStatus.waitForExistence(timeout: 10))
            XCTAssertTrue(scrollUpUntilHittable(homeStatus, in: app), app.debugDescription)
            XCTAssertTrue(waitUntil(timeout: 240) {
                self.yourHomeState(token: bobSession.token) == "hidden"
            }, "Bob must finish Look and Home set/clear and publish the Hidden readiness barrier before Alice starts her Home/Away/Hidden sequence.")

            for state in ["home", "away", "hidden"] {
                homeStatus.tap()
                let choice = app.buttons.matching(identifier: "set-home-status-\(state)").firstMatch
                XCTAssertTrue(choice.waitForExistence(timeout: 5), "The Sharing status menu should offer \(state).")
                choice.tap()
                XCTAssertTrue(waitUntil(timeout: 15) { self.yourHomeState(token: session.token) == state }, "Alice's selected status should persist as \(state).")
                if state == "hidden" {
                    XCTAssertTrue(waitUntil(timeout: 30) {
                        let response = self.api.memberResponse(personID: session.personID, token: bobSession.token)
                        guard (200..<300).contains(response.status),
                              let member = response.member,
                              member["inboundPresenceGranted"] as? Bool == true else { return false }
                        // A successful recipient response must still include Alice;
                        // Hidden is proven only when that member has no visible
                        // Home/Away payload, not when the request or lookup fails.
                        return member["homePresence"] == nil || member["homePresence"] is NSNull
                    }, "Hidden should suppress Alice's status for Bob while the explicit grant and Sealed mode remain active.")
                } else {
                    XCTAssertTrue(waitUntil(timeout: 30) {
                        self.visibleHomePresence(personID: session.personID, token: bobSession.token) == state
                    }, "Bob should see Alice's \(state.capitalized) status through his own circle response.")
                }
                XCTAssertTrue(waitUntil(timeout: 30) {
                    self.yourHomeState(token: bobSession.token) == state
                }, "Wait for Bob's same-state API acknowledgement before Alice changes her status again.")
            }
            XCTAssertTrue(homeStatus.label.contains("Hidden"), "Alice's Sharing control should reflect the final Hidden choice.")

            let originalConnectionID = try XCTUnwrap(api.member(personID: peerID, token: session.token)?["connectionId"] as? String)
            XCTAssertFalse(originalConnectionID.isEmpty)
            XCTAssertTrue(waitUntil(timeout: 20) {
                let response = self.api.memberResponse(personID: session.personID, token: bobSession.token)
                return (200..<300).contains(response.status) && response.member?["connectionId"] as? String == originalConnectionID
            }, "Bob's successful circle response should carry the same active connection ID.")
            XCTAssertTrue(waitUntil(timeout: 30) { self.inboundPresentation(personID: peerID, token: session.token) == "off" }, "Wait until Bob's UI Stop has taken effect before Alice removes him.")
            XCTAssertTrue(actions.waitForExistence(timeout: 8))
            actions.tap()
            let remove = app.buttons["remove-person-action-pairbob"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            remove.tap()
            let confirmRemove = app.buttons.matching(identifier: "remove-person-confirm")
            XCTAssertTrue(confirmRemove.firstMatch.waitForExistence(timeout: 5))
            confirmRemove.element(boundBy: 0).tap()
            XCTAssertTrue(waitUntil(timeout: 20) {
                self.successfulCircleOmitsMember(personID: peerID, token: session.token)
                    && self.successfulCircleOmitsMember(personID: session.personID, token: bobSession.token)
            }, "Removal must be reflected by successful decoded circle responses for both accounts.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let bobGroup = app.descendants(matching: .any)["sharing-mode-group-pairbob"]
            XCTAssertTrue(waitUntil(timeout: 15) { !bobGroup.exists }, "Alice's refreshed Sharing list should remove Bob.")
            attachScreenshot(of: app, named: "Pair lifecycle - Alice removed Bob")

            XCTAssertTrue(waitUntil(timeout: 90) { !(self.api.connectionRequests(token: session.token)?["incoming"] as? [[String: Any]] ?? []).isEmpty }, "Bob should send Alice a fresh request by phone after removal.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let acceptAgain = app.buttons["accept-connection-request-\(bobHandle)"]
            XCTAssertTrue(acceptAgain.waitForExistence(timeout: 15), "Alice should refresh Sharing to render Bob's new incoming request.\n\(app.debugDescription)")
            // Bob changes his real Sharing status to Away only after his UI has
            // rendered the Sent row. Wait for that API-visible acknowledgement
            // before accepting so the paired test cannot race through the state.
            XCTAssertTrue(waitUntil(timeout: 240) {
                self.yourHomeState(token: bobSession.token) == "away"
            }, "Bob's UI should acknowledge seeing the pending Sent row before Alice accepts it.")
            acceptAgain.tap()
            XCTAssertTrue(waitUntil(timeout: 90) { self.activeConnectionID(personID: peerID, token: session.token).map { $0 != originalConnectionID } == true }, "Acceptance should produce a nonempty new connection ID.")
            let reconnectedGroup = app.descendants(matching: .any)["sharing-mode-group-pairbob"]
            XCTAssertTrue(reconnectedGroup.waitForExistence(timeout: 20), "Alice's UI should show Bob after accepting the new request.")
            let reconnectedOff = app.buttons["sharing-mode-off-pairbob"]
            XCTAssertTrue(reconnectedOff.waitForExistence(timeout: 8))
            XCTAssertTrue(reconnectedOff.isSelected, "Alice's reconnected row should visibly start Off.")
            attachScreenshot(of: app, named: "Pair lifecycle - Alice reconnected Off")
            try assertReconnectedPair(
                ownToken: session.token, peerToken: bobSession.token,
                ownID: session.personID, peerID: peerID, originalConnectionID: originalConnectionID
            )

        } else {
            XCTAssertTrue(waitUntil(timeout: 90) { !(self.api.connectionRequests(token: session.token)?["incoming"] as? [[String: Any]] ?? []).isEmpty }, "Alice's UI did not send a request.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let accept = app.buttons["accept-connection-request-\(aliceHandle)"]
            XCTAssertTrue(accept.waitForExistence(timeout: 15))
            accept.tap()
            guard let aliceID = api.lookupPerson(handle: peerHandle, token: session.token) else { XCTFail("Alice's public handle should resolve after onboarding."); return }
            XCTAssertTrue(waitUntil(timeout: 15) { self.api.member(personID: aliceID, token: session.token) != nil })
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let refreshStartedAt = Date()
            app.swipeDown()
            let memberGroup = app.descendants(matching: .any)["sharing-mode-group-pairalice"]
            XCTAssertTrue(memberGroup.waitForExistence(timeout: 20), "Bob's UI should show Alice after accepting.\n\(app.debugDescription)")
            self.add(XCTAttachment(string: "Bob's Sharing list converged after pull-to-refresh in \(Date().timeIntervalSince(refreshStartedAt)) seconds."))

            let sealed = app.buttons["sharing-mode-sealed-pairalice"]
            XCTAssertTrue(sealed.waitForExistence(timeout: 10), app.debugDescription)
            sealed.tap()
            XCTAssertTrue(waitUntil(timeout: 10) { self.outboundPresentation(personID: aliceID, token: session.token) == "untilTheyLook" }, "Bob's UI should update Bob→Alice, visible as outboundShare in Bob's circle response.")
            allowBackgroundLocationIfPrompted(in: app)

            let aliceSession = try XCTUnwrap(api.developmentSession(
                name: "PairAlice",
                deviceID: "trust-pair-\(pairID)-alice"
            ))
            XCTAssertEqual(aliceSession.personID, aliceID, "The recipient observer must be the same Alice account that completed UI onboarding.")
            XCTAssertTrue(waitUntil(timeout: 30) {
                guard let member = self.api.member(personID: aliceID, token: session.token) else { return false }
                return member["inboundPresenceGranted"] as? Bool == true
                    && member["outboundPresenceGranted"] as? Bool == false
            }, "Bob's circle response should first show Alice's one-way grant from her Sharing UI, while Bob's reciprocal grant is still off.")
            // SwiftUI Menu drops the nested identifier in the native menu host.
            // Match its visible accessibility label, as in the single-app flow,
            // so Bob makes the reciprocal choice through his own Sharing UI.
            let alicePresenceGrant = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Let PairAlice know when I’m Home or Away")
            ).firstMatch
            let aliceActions = app.buttons["sharing-actions-pairalice"]
            XCTAssertTrue(aliceActions.waitForExistence(timeout: 8), app.debugDescription)
            aliceActions.tap()
            XCTAssertTrue(alicePresenceGrant.waitForExistence(timeout: 5), "Bob's native Sharing menu should expose the visible grant action.\n\(app.debugDescription)")
            alicePresenceGrant.tap()
            XCTAssertTrue(app.staticTexts["Home/Away sharing preference updated."].waitForExistence(timeout: 15), "Bob's UI should acknowledge the reciprocal grant write.")
            XCTAssertTrue(waitUntil(timeout: 30) {
                let bobView = self.api.memberResponse(personID: aliceID, token: session.token)
                let aliceView = self.api.memberResponse(personID: session.personID, token: aliceSession.token)
                guard (200..<300).contains(bobView.status), (200..<300).contains(aliceView.status),
                      let bobMember = bobView.member, let aliceMember = aliceView.member else { return false }
                return bobMember["outboundPresenceGranted"] as? Bool == true
                    && bobMember["inboundPresenceGranted"] as? Bool == true
                    && aliceMember["inboundPresenceGranted"] as? Bool == true
            }, "Successful circle responses for Bob and Alice should show both explicit grant directions after Bob's UI action.")

            // This Sealed Look is a real recipient UI action, not an API fixture. With
            // an isolated Memory API, Bob's test role can confirm the receipt after
            // the app displays the one-time snapshot. A missing Core Location upload
            // makes the Look endpoint reject with no_location.
            XCTAssertTrue(waitUntil(timeout: 30) {
                let member = self.api.member(personID: aliceID, token: session.token)
                return (member?["inboundShare"] as? [String: Any])?["presentation"] as? String == "untilTheyLook"
            }, "Alice must be Sealed toward Bob before Bob requests a Look.")
            XCTAssertFalse(api.hasLookEvent(subjectID: aliceID, token: session.token), "The fresh pair should not already contain a Look receipt for Alice.")
            app.buttons["tab-circle"].tap()
            // API state is authoritative, but Bob may already have a cached Circle
            // snapshot from before Alice chose Sealed. Refresh the recipient's
            // People list before opening the profile so the UI exercises the same
            // state the API assertion just observed.
            app.swipeDown()
            let aliceRow = app.buttons["person-row-pairalice"]
            XCTAssertTrue(aliceRow.waitForExistence(timeout: 15), "Bob's People list should show Alice before Look.\n\(app.debugDescription)")
            aliceRow.tap()
            let sharingDirections = app.staticTexts["person-sharing-directions"]
            XCTAssertTrue(waitUntil(timeout: 15) {
                sharingDirections.exists && sharingDirections.label.contains("They share with you: Sealed")
            }, "Bob's refreshed person screen should show Alice's inbound Sealed sharing before offering Look.\n\(app.debugDescription)")
            let lookAction = app.buttons["person-profile-peek"]
            XCTAssertTrue(lookAction.waitForExistence(timeout: 10), "A Sealed person should offer the notify-first Look action.")
            lookAction.tap()
            let confirmLook = app.buttons["confirm-look-notify"]
            XCTAssertTrue(confirmLook.waitForExistence(timeout: 8))
            confirmLook.tap()
            XCTAssertTrue(app.buttons["view-open-map"].waitForExistence(timeout: 20), "Bob should open the API-backed Look snapshot, not just see the pre-Look explanation.\n\(app.debugDescription)")
            XCTAssertTrue(waitUntil(timeout: 20) { self.api.hasLookEvent(subjectID: aliceID, token: session.token) }, "The API should record Bob's real UI Look for Alice.")
            let lookEvent = try XCTUnwrap(api.latestLookEvent(subjectID: aliceID, token: session.token))
            XCTAssertEqual(lookEvent["kind"] as? String, "look")
            XCTAssertEqual(lookEvent["includedLive"] as? Bool, true, "The Look receipt must prove that a current location point was included.")
            add(XCTAttachment(string: "Bob completed a Sealed Look in UI and the API recorded includedLive=true while both simulators followed the moving Core Simulator route."))

            // A confirmed Look snapshot should render as a map pin, and the receipt
            // should appear in Activity under the same event ID returned by the API.
            let openMap = app.buttons["view-open-map"]
            XCTAssertTrue(openMap.waitForExistence(timeout: 10), app.debugDescription)
            openMap.tap()
            let mapCanvas = app.descendants(matching: .any)["map-screen-canvas"]
            XCTAssertTrue(mapCanvas.waitForExistence(timeout: 20), "A confirmed Look should add its snapshot pin to the map.")
            XCTAssertTrue(app.descendants(matching: .any)["map-screen-person-panel"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["PairAlice"].exists, "The selected map pin should identify Alice.")
            attachScreenshot(of: app, named: "Paired Sealed Look - snapshot map pin")
            app.buttons["map-back-to-people"].tap()
            app.buttons["tab-log"].tap()
            let lookEventID = try XCTUnwrap(lookEvent["id"] as? String).uppercased()
            let activityRow = app.descendants(matching: .any)["activity-event-\(lookEventID)"]
            XCTAssertTrue(activityRow.waitForExistence(timeout: 20), "The viewer's Activity list should include the Look receipt recorded by the API.")
            XCTAssertTrue(activityRow.label.contains("PairAlice"), "Activity should name the person the viewer just looked at.")
            attachScreenshot(of: app, named: "Paired Sealed Look - Activity receipt")
            app.buttons["tab-circle"].tap()

            // Verify first-use Home selection using the moving Core Simulator route.
            // Home's exact coordinates stay in the on-device store; the API only
            // receives the place label/ID and the resulting coarse presence state.
            app.buttons["tab-you"].tap()
            let myLocation = app.buttons["my-location"]
            XCTAssertTrue(myLocation.waitForExistence(timeout: 10))
            myLocation.tap()
            let setHome = app.buttons["home-set-button"]
            XCTAssertTrue(setHome.waitForExistence(timeout: 10), app.debugDescription)
            if !setHome.isHittable { app.swipeUp() }
            setHome.tap()
            let whenInUseAlert = app.alerts.firstMatch
            if whenInUseAlert.waitForExistence(timeout: 2) {
                let whileUsing = whenInUseAlert.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "While Using")
                ).firstMatch
                let allowOnce = whenInUseAlert.buttons.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "Allow Once")
                ).firstMatch
                if whileUsing.exists { whileUsing.tap() }
                else if allowOnce.exists { allowOnce.tap() }
                else { XCTFail("When-In-Use location permission appeared without a recognizable allow action.\n\(app.debugDescription)") }
            }
            let homePlaceStatus = app.staticTexts["home-place-status"]
            XCTAssertTrue(waitUntil(timeout: 30) {
                homePlaceStatus.exists && homePlaceStatus.label.localizedCaseInsensitiveContains("set")
            }, "The You → My Location screen should confirm Home was set from the moving simulator route.\n\(app.debugDescription)")
            let setHomeResponse = api.yourHomePlace(token: session.token)
            XCTAssertTrue((200..<300).contains(setHomeResponse.status), "A successful circle response should expose the newly set Home place.")
            XCTAssertEqual(setHomeResponse.label, "Home")
            // A fresh account/device may have only When-In-Use access. Home/Away
            // geofencing requires Always, so complete the real permission upgrade
            // instead of dismissing the explainer and then expecting a transition.
            allowBackgroundLocationIfPrompted(in: app)
            let locationPermission = app.staticTexts["location-permission-status"]
            XCTAssertTrue(waitUntil(timeout: 12) {
                locationPermission.exists && locationPermission.label.localizedCaseInsensitiveContains("always")
            }, "The paired Home/Away test requires Always location permission; complete Trust's explainer and the iOS Always prompt.\n\(app.debugDescription)\n\(XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription)")

            let originalHomePlaceID = try XCTUnwrap(setHomeResponse.placeID)
            XCTAssertTrue(waitUntil(timeout: 20) {
                self.yourHomeState(token: session.token) == "home"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "home"
            }, "Setting Home should publish Home to a connected person who has granted Home/Away visibility.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.yourHomeState(token: session.token) == "away"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "away"
            }, "As the moving simulator leaves the saved Home radius, both accounts should observe Away.")

            // Re-setting Home is an update-in-place action. It keeps the logical
            // place ID on the server but stores the new current coordinate locally.
            // A fresh simulator fix can fall back at 20 seconds; allow time for that
            // one-shot request, the server update, and both accounts' next reads.
            XCTAssertTrue(setHome.isHittable, "Set Home Here should remain available when a place already exists.")
            setHome.tap()
            XCTAssertTrue(waitUntil(timeout: 40) {
                self.yourHomeState(token: session.token) == "home"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "home"
            }, "Saving Home at the new current location should publish Home again to the connected account; allow for the location request's 20-second last-known-fix fallback.")
            let updatedHomeResponse = api.yourHomePlace(token: session.token)
            XCTAssertEqual(updatedHomeResponse.label, "Home")
            XCTAssertEqual(updatedHomeResponse.placeID, originalHomePlaceID, "Updating the saved coordinate should keep the same logical Home place ID.")
            XCTAssertTrue(homePlaceStatus.label.localizedCaseInsensitiveContains("set"))
            XCTAssertTrue(locationPermission.label.localizedCaseInsensitiveContains("always"), "Updating Home must retain Always location permission.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.yourHomeState(token: session.token) == "away"
                    && self.visibleHomePresence(personID: session.personID, token: aliceSession.token) == "away"
            }, "The updated Home location should continue to drive Away when the moving simulator leaves its new radius.")

            let clearHome = app.buttons["home-clear-button"]
            XCTAssertTrue(clearHome.waitForExistence(timeout: 10), app.debugDescription)
            if !clearHome.isHittable { app.swipeUp() }
            clearHome.tap()
            XCTAssertTrue(waitUntil(timeout: 20) {
                homePlaceStatus.exists && !homePlaceStatus.label.localizedCaseInsensitiveContains("set")
            }, "Clearing Home should return the You screen to its unset state.\n\(app.debugDescription)")
            let clearHomeResponse = api.yourHomePlace(token: session.token)
            XCTAssertTrue((200..<300).contains(clearHomeResponse.status), "A successful circle response should confirm Home was cleared.")
            XCTAssertNil(clearHomeResponse.label, "The API should no longer expose a Home place after Clear Home.")
            add(XCTAttachment(string: "Bob set Home, drove the moving simulator out of range, updated the same logical Home place from the new fix, observed Home→Away again, then cleared it. Alice's independent account observed both status transitions. The server received only the place ID/label; coordinates remained on-device."))

            // Signal that Bob has completed Look and Home set/clear before Alice
            // starts her recipient-visibility sequence. Hidden is a stable marker:
            // geofence updates must not replace an explicit Hidden choice.
            let doneWithLocation = app.buttons["Done"]
            XCTAssertTrue(doneWithLocation.waitForExistence(timeout: 8), app.debugDescription)
            doneWithLocation.tap()
            app.buttons["tab-sharing"].tap()
            let bobHomeStatus = app.buttons["home-status-control"]
            XCTAssertTrue(bobHomeStatus.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(scrollUpUntilHittable(bobHomeStatus, in: app), app.debugDescription)
            bobHomeStatus.tap()
            let markHidden = app.buttons.matching(identifier: "set-home-status-hidden").firstMatch
            XCTAssertTrue(markHidden.waitForExistence(timeout: 5))
            markHidden.tap()
            XCTAssertTrue(waitUntil(timeout: 20) { self.yourHomeState(token: session.token) == "hidden" }, "Bob's UI should publish the Hidden readiness barrier for Alice.")
            XCTAssertTrue(bobHomeStatus.label.localizedCaseInsensitiveContains("Hidden"), "Bob's Sharing control should show the acknowledged Hidden state.")
            add(XCTAttachment(string: "Bob completed Look and Home set/clear, then set Hidden in Sharing UI as a stable readiness barrier for Alice's Home/Away/Hidden sequence."))

            // Alice transitions Home -> Away -> Hidden in her UI. Her role waits
            // for each recipient-visible response before moving to the next state.
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.visibleHomePresence(personID: aliceID, token: session.token) == "home"
            }, "Bob should receive Alice's Home status after both grants are enabled.")
            XCTAssertEqual(api.postHomePresence(state: "home", token: session.token), 204, "Bob acknowledges Home only after his recipient response sees Alice's Home.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                self.visibleHomePresence(personID: aliceID, token: session.token) == "away"
            }, "Bob should receive Alice's Away status after Home.")
            XCTAssertEqual(api.postHomePresence(state: "away", token: session.token), 204, "Bob acknowledges Away only after his recipient response sees Alice's Away.")
            XCTAssertTrue(waitUntil(timeout: 60) {
                let response = self.api.memberResponse(personID: aliceID, token: session.token)
                guard (200..<300).contains(response.status),
                      let member = response.member,
                      member["inboundPresenceGranted"] as? Bool == true else { return false }
                return member["homePresence"] == nil || member["homePresence"] is NSNull
            }, "Bob's response should hide Alice's Home/Away after she chooses Hidden.")
            XCTAssertEqual(api.postHomePresence(state: "hidden", token: session.token), 204, "Bob acknowledges Hidden only after his successful recipient response suppresses Alice's presence.")
            app.buttons["tab-circle"].tap()
            app.swipeDown()
            let hiddenAliceRow = app.buttons["person-row-pairalice"]
            XCTAssertTrue(hiddenAliceRow.waitForExistence(timeout: 15), "Bob's Duo People list should still show Alice after refreshing the Hidden state.\n\(app.debugDescription)")
            hiddenAliceRow.tap()
            let aliceStatus = app.staticTexts["person-status"]
            XCTAssertTrue(waitUntil(timeout: 15) {
                aliceStatus.exists && aliceStatus.label.localizedCaseInsensitiveContains("hidden")
            }, "Bob's Duo person screen should render Alice as Hidden after a successful recipient response suppressed her Home/Away payload.\n\(app.debugDescription)")
            app.buttons["tab-sharing"].tap()
            let later = app.buttons["always-explainer-later"]
            if later.waitForExistence(timeout: 2) { later.tap() }
            let off = app.buttons["sharing-mode-off-pairalice"]
            XCTAssertTrue(off.waitForExistence(timeout: 8))
            XCTAssertTrue(waitUntil(timeout: 5) { off.isHittable }, "Stop should be tappable after the sharing explainer closes.")
            off.tap()
            let confirmStop = app.buttons.matching(identifier: "stop-sharing-confirm")
            XCTAssertTrue(confirmStop.firstMatch.waitForExistence(timeout: 5))
            confirmStop.element(boundBy: 0).tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                self.outboundPresentation(personID: aliceID, token: session.token) == "off"
            }, "Stopping sharing through Bob's UI should immediately revoke Bob→Alice visibility.")

            let originalConnectionID = try XCTUnwrap(api.member(personID: aliceID, token: session.token)?["connectionId"] as? String)
            XCTAssertFalse(originalConnectionID.isEmpty)
            XCTAssertTrue(waitUntil(timeout: 20) {
                let response = self.api.memberResponse(personID: session.personID, token: aliceSession.token)
                return (200..<300).contains(response.status) && response.member?["connectionId"] as? String == originalConnectionID
            }, "Alice's successful circle response should carry the same active connection ID.")
            XCTAssertTrue(waitUntil(timeout: 90) {
                self.successfulCircleOmitsMember(personID: aliceID, token: session.token)
                    && self.successfulCircleOmitsMember(personID: session.personID, token: aliceSession.token)
            }, "Alice's UI removal should produce successful circle responses without the peer for both accounts.")
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            let aliceGroup = app.descendants(matching: .any)["sharing-mode-group-pairalice"]
            XCTAssertTrue(waitUntil(timeout: 15) { !aliceGroup.exists }, "Bob's refreshed Sharing list should remove Alice.")
            attachScreenshot(of: app, named: "Pair lifecycle - Bob removed by Alice")

            app.buttons["add-someone-button"].tap()
            let lookup = app.textFields["connection-handle"]
            XCTAssertTrue(lookup.waitForExistence(timeout: 8))
            let alicePhoneDigits = LocalTrustAPI.reservedPhonePool()[pairPhoneBase]
            lookup.typeText("+1 (\(alicePhoneDigits.prefix(3))) \(alicePhoneDigits.dropFirst(3).prefix(3))-\(alicePhoneDigits.suffix(4))")
            XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 12), "Alice's verified fictional phone should resolve for the re-add.")
            XCTAssertEqual(app.staticTexts["connection-lookup-handle"].label, "@\(aliceHandle)")
            let keyboardDone = app.buttons["Done"]
            if keyboardDone.exists && keyboardDone.isHittable {
                keyboardDone.tap()
            } else {
                // On Duo/iOS 27 the software-keyboard accessory can report
                // “Done” while XCTest cannot scroll it into a hittable frame.
                // Return invokes this field's .onSubmit and dismisses focus;
                // valid phone input is already resolved, so it does not issue
                // another lookup.
                lookup.typeText("\n")
            }
            let sendAgain = app.buttons["send-connection-request"]
            XCTAssertTrue(sendAgain.waitForExistence(timeout: 5))
            sendAgain.tap()
            XCTAssertTrue(waitUntil(timeout: 10) {
                let pending = !(self.api.connectionRequests(token: session.token)?["sent"] as? [[String: Any]] ?? []).isEmpty
                return pending || self.activeConnectionID(personID: aliceID, token: session.token).map { $0 != originalConnectionID } == true
            }, "Bob's UI should create a pending request or Alice should already have accepted it.")
            app.buttons["cancel-add-person"].tap()
            app.buttons["tab-you"].tap()
            XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["tab-you"].isSelected }, "Bob should open You while Alice reviews the request.")
            app.buttons["tab-sharing"].tap()
            XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["tab-sharing"].isSelected }, "Bob should return to Sharing to verify his Sent request.")
            let pendingSentRequest = app.descendants(matching: .any)["connection-request-sent-\(aliceHandle)"]
            XCTAssertTrue(pendingSentRequest.waitForExistence(timeout: 15), "Bob should see the new Sent request before Alice accepts it.\n\(app.debugDescription)")
            let requestReviewStatus = app.buttons["home-status-control"]
            XCTAssertTrue(requestReviewStatus.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(scrollUpUntilHittable(requestReviewStatus, in: app), app.debugDescription)
            requestReviewStatus.tap()
            let markAway = app.buttons.matching(identifier: "set-home-status-away").firstMatch
            XCTAssertTrue(markAway.waitForExistence(timeout: 5), app.debugDescription)
            markAway.tap()
            XCTAssertTrue(waitUntil(timeout: 20) { self.yourHomeState(token: session.token) == "away" }, "Bob should publish Away through the Sharing UI after seeing the pending Sent request.")
            XCTAssertTrue(waitUntil(timeout: 240) {
                self.activeConnectionID(personID: aliceID, token: session.token).map { $0 != originalConnectionID } == true
            }, "Alice should accept Bob's request in her UI and create a new relationship.")
            // Acceptance happens on the other device while Bob stays on Sharing.
            // There is no guaranteed push delivery for this state change, so
            // re-enter Sharing to exercise its explicit cross-device refresh.
            app.buttons["tab-you"].tap()
            app.buttons["tab-sharing"].tap()
            XCTAssertTrue(waitUntil(timeout: 8) { app.buttons["tab-sharing"].isSelected }, "Bob should re-enter Sharing after Alice accepts.")
            app.swipeDown()
            let reconnectedAlice = app.descendants(matching: .any)["sharing-mode-group-pairalice"]
            XCTAssertTrue(reconnectedAlice.waitForExistence(timeout: 20), "Bob's refreshed Sharing list should show Alice reconnected. API member: \(String(describing: api.member(personID: aliceID, token: session.token))).\n\(app.debugDescription)")
            let requestsError = app.descendants(matching: .any)["connection-requests-error"]
            if !waitUntil(timeout: 15, condition: { !requestsError.exists }) {
                let retry = app.buttons["retry-connection-requests"]
                XCTAssertTrue(retry.waitForExistence(timeout: 8), "A stale Requests notice should expose Retry.\n\(app.debugDescription)")
                retry.tap()
                XCTAssertTrue(waitUntil(timeout: 30) { !requestsError.exists }, "Retry should clear the stale Requests notice after the account's successful re-add.\n\(app.debugDescription)")
                add(XCTAttachment(string: "Returning to Sharing did not clear the prior Requests notice within 15 seconds; the visible Retry action was used and cleared it."))
            }
            let requestsSection = app.descendants(matching: .any)["connection-requests-section"]
            XCTAssertTrue(waitUntil(timeout: 30) {
                !pendingSentRequest.exists && !requestsSection.exists && !requestsError.exists
            }, "After Alice accepts, Bob's completed Requests refresh should remove the stale Sent row and its now-empty Requests section.\n\(app.debugDescription)")
            XCTAssertTrue(waitUntil(timeout: 15) { self.outboundPresentation(personID: aliceID, token: session.token) == "off" }, "The reconnected row should start Off.")
            XCTAssertTrue(app.buttons["sharing-mode-off-pairalice"].isSelected, "Bob's reconnected row should visibly start Off.")
            add(XCTAttachment(string: "Bob's UI showed the Sent request while pending. After Alice accepted, a completed app refresh removed that stale row, showed the empty Requests state, retained the reconnected relationship, and kept sharing Off."))
            attachScreenshot(of: app, named: "Pair lifecycle - Bob reconnected Off")
            try assertReconnectedPair(
                ownToken: session.token, peerToken: aliceSession.token,
                ownID: session.personID, peerID: aliceID, originalConnectionID: originalConnectionID
            )
        }
    }

    func testPrivacyHeldAccountCanDeleteAfterRelaunch() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-held-delete-\(suffix)"
        let name = "HeldDelete\(suffix.prefix(6))"
        let session = try XCTUnwrap(api.developmentSession(name: name, deviceID: deviceID))
        defer { api.deleteAccount(token: session.token) }

        XCTAssertEqual(api.placePrivacyHold(token: session.token), 204)
        XCTAssertEqual(api.request("GET", "/api/v1/circle", token: session.token).status, 423)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = name
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launch()

        let delete = app.buttons["age-privacy-hold-delete-account"]
        XCTAssertTrue(delete.waitForExistence(timeout: 20), app.debugDescription)

        // The authorization needed only for account deletion must survive an app
        // restart while the server continues to deny ordinary account access. The
        // second launch intentionally has no UI-test or development-session bypass.
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TRUST_DEV_SESSION")
        app.launchEnvironment.removeValue(forKey: "TRUST_UI_TEST")
        app.launch()
        XCTAssertTrue(delete.waitForExistence(timeout: 20), app.debugDescription)

        delete.tap()
        let confirm = app.alerts.buttons.matching(identifier: "age-privacy-hold-delete-confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        var replacementSession: DisposableSession?
        XCTAssertTrue(waitUntil(timeout: 20) {
            guard let candidate = self.api.developmentSession(name: name, deviceID: deviceID) else { return false }
            guard candidate.personID != session.personID else { return false }
            replacementSession = candidate
            return true
        }, "Deleting the held account should invalidate its identity; the same test device must receive a new development account.")
        if let replacementSession {
            defer { api.deleteAccount(token: replacementSession.token) }
            XCTAssertNotEqual(replacementSession.personID, session.personID)
        }
    }

    /// The peer accepts through the local API after this UI's initial circle fetch.
    /// Returning to Sharing must fetch promptly and render the new relationship.
    func testSharingTabRefreshShowsPeerAcceptedAfterInitialFetch() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let mainDeviceID = "trust-refresh-main-\(suffix)"
        let peerDeviceID = "trust-refresh-peer-\(suffix)"
        let mainName = "RefreshMain\(suffix.prefix(6))"
        let peerName = "RefreshPeer\(suffix.prefix(6))"
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let mainPhone = try XCTUnwrap(phones.first)
        let peerPhone = try XCTUnwrap(phones.last)
        let mainSession = try XCTUnwrap(api.developmentSession(name: mainName, deviceID: mainDeviceID))
        let peerSession = try XCTUnwrap(api.developmentSession(name: peerName, deviceID: peerDeviceID))
        defer {
            api.deleteAccount(token: peerSession.token)
            api.deleteAccount(token: mainSession.token)
        }

        let mainHandle = "rm\(suffix.prefix(10))"
        let peerHandle = "rp\(suffix.prefix(10))"
        XCTAssertEqual(api.putHandle(mainHandle, token: mainSession.token), 204)
        XCTAssertEqual(api.putHandle(peerHandle, token: peerSession.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(mainPhone)", token: mainSession.token))
        XCTAssertTrue(api.verifyPhone(phone: "+1\(peerPhone)", token: peerSession.token))
        XCTAssertEqual(api.setPhoneDiscovery(true, token: peerSession.token), 204)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = mainDeviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = mainName
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 20))
        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.buttons["copy-own-handle"].waitForExistence(timeout: 10))
        app.buttons["tab-sharing"].tap()
        let groupID = "sharing-mode-group-\(peerName.lowercased())"
        XCTAssertFalse(app.descendants(matching: .any)[groupID].exists, "The initial circle fetch should be empty before peer acceptance.")

        app.buttons["add-someone-button"].tap()
        let lookup = app.textFields["connection-handle"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 8))
        lookup.typeText(peerHandle)
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10))
        app.buttons["send-connection-request"].tap()
        app.buttons["cancel-add-person"].tap()
        guard let request = (api.connectionRequests(token: peerSession.token)?["incoming"] as? [[String: Any]])?.first,
              let requestID = request["id"] as? String else {
            XCTFail("The peer should receive the UI-created request.")
            return
        }
        XCTAssertEqual(api.request("POST", "/api/v1/connection-requests/\(requestID)/accept", token: peerSession.token).status, 204)
        let acceptedAt = Date()
        XCTAssertTrue(waitUntil(timeout: 15) { self.api.member(personID: peerSession.personID, token: mainSession.token) != nil })

        app.buttons["tab-you"].tap()
        app.buttons["tab-sharing"].tap()
        let connected = app.descendants(matching: .any)[groupID]
        XCTAssertTrue(connected.waitForExistence(timeout: 15), "Returning to Sharing must fetch and render the accepted member without relying on a manual pull gesture.\n\(app.debugDescription)")
        add(XCTAttachment(string: "The UI rendered the API-accepted member after Sharing-tab entry in \(Date().timeIntervalSince(acceptedAt)) seconds."))
    }

    func testAlwaysSharedLocationHistoryRendersAndClearsAfterStop() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let viewerDeviceID = "trust-history-viewer-\(suffix)"
        let subjectDeviceID = "trust-history-subject-\(suffix)"
        let viewerName = "HistoryViewer\(suffix.prefix(5))"
        let subjectName = "HistoryPeer\(suffix.prefix(5))"
        let phones = Array(LocalTrustAPI.reservedPhonePool().shuffled().prefix(2))
        let viewerPhone = try XCTUnwrap(phones.first)
        let subjectPhone = try XCTUnwrap(phones.last)
        let viewer = try XCTUnwrap(api.developmentSession(name: viewerName, deviceID: viewerDeviceID))
        let subject = try XCTUnwrap(api.developmentSession(name: subjectName, deviceID: subjectDeviceID))
        defer {
            api.deleteAccount(token: subject.token)
            api.deleteAccount(token: viewer.token)
        }

        XCTAssertEqual(api.putHandle("hv\(suffix.prefix(10))", token: viewer.token), 204)
        XCTAssertEqual(api.putHandle("hp\(suffix.prefix(10))", token: subject.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(viewerPhone)", token: viewer.token))
        XCTAssertTrue(api.verifyPhone(phone: "+1\(subjectPhone)", token: subject.token))

        let request = api.request(
            "POST",
            "/api/v1/connection-requests",
            token: viewer.token,
            body: ["recipientId": subject.personID]
        )
        XCTAssertEqual(request.status, 200)
        let requestID = try XCTUnwrap((request.json as? [String: Any])?["id"] as? String)
        XCTAssertEqual(api.request("POST", "/api/v1/connection-requests/\(requestID)/accept", token: subject.token).status, 204)

        // Always requires Plus for the person sharing. The Development API exposes
        // its review unlock so this test never enters StoreKit or creates a purchase.
        XCTAssertEqual(api.request("POST", "/api/v1/circle/entitlement", token: subject.token, body: ["reviewUnlock": true]).status, 204)
        let subjectConnectionID = try XCTUnwrap(activeConnectionID(personID: viewer.personID, token: subject.token))
        let subjectShareRevision = try XCTUnwrap(activeShareRevision(personID: viewer.personID, token: subject.token))
        XCTAssertEqual(
            api.request(
                "PATCH",
                "/api/v1/people/\(viewer.personID)/share",
                token: subject.token,
                body: ["connectionId": subjectConnectionID, "revision": subjectShareRevision, "resting": "always"]
            ).status,
            204
        )

        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let historyPoints: [[String: Any]] = (0..<3).map { index in
            let timestamp = now.addingTimeInterval(TimeInterval(-120 * (index + 1)))
            return [
                "timestamp": formatter.string(from: timestamp),
                "latitude": 47.60 + Double(index) * 0.001,
                "longitude": -122.33 - Double(index) * 0.001
            ]
        }
        XCTAssertEqual(
            api.request(
                "POST",
                "/api/v1/location",
                token: subject.token,
                body: [
                    "timestamp": formatter.string(from: now),
                    "latitude": 47.60,
                    "longitude": -122.33,
                    "batteryPercent": 75,
                    "isCharging": false,
                    "points": historyPoints
                ]
            ).status,
            204
        )
        let seededHistory = api.request("GET", "/api/v1/people/\(subject.personID)/history", token: viewer.token)
        XCTAssertEqual(seededHistory.status, 200)
        XCTAssertEqual(((seededHistory.json as? [String: Any])?["points"] as? [[String: Any]])?.count, 3)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = viewerDeviceID
        app.launchEnvironment["TRUST_UI_TEST_DISPLAY_NAME"] = viewerName
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["tab-circle"].waitForExistence(timeout: 15))
        let peerRow = app.buttons["person-row-\(subjectName.lowercased())"]
        XCTAssertTrue(peerRow.waitForExistence(timeout: 15), app.debugDescription)
        let availableLabel = peerRow.label
        peerRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["person-history"].waitForExistence(timeout: 15), app.debugDescription)
        for index in 0..<3 {
            XCTAssertTrue(
                app.descendants(matching: .any)["person-history-visit-\(index)"].waitForExistence(timeout: 10),
                "The Always-shared trail should render all three points returned by the API.\n\(app.debugDescription)"
            )
        }
        attachScreenshot(of: app, named: "Always sharing - location history")

        // Stop sharing on the subject's server account, then force the viewer's
        // circle refresh. The Person screen must no longer expose retained visits.
        let stoppedShareRevision = try XCTUnwrap(activeShareRevision(personID: viewer.personID, token: subject.token))
        XCTAssertEqual(
            api.request("PATCH", "/api/v1/people/\(viewer.personID)/share", token: subject.token, body: ["connectionId": subjectConnectionID, "revision": stoppedShareRevision, "resting": "off"]).status,
            204
        )
        let stoppedCircle = api.memberResponse(personID: subject.personID, token: viewer.token)
        XCTAssertEqual(stoppedCircle.status, 200)
        XCTAssertNotNil(stoppedCircle.member, "Stopping sharing must retain the connection in the server circle.")
        XCTAssertEqual((stoppedCircle.member?["inboundShare"] as? [String: Any])?["presentation"] as? String, "off")
        let stoppedHistory = api.request("GET", "/api/v1/people/\(subject.personID)/history", token: viewer.token)
        XCTAssertEqual(stoppedHistory.status, 409, "The server must revoke history access immediately when Always sharing stops.")
        app.buttons["circle-back"].tap()
        XCTAssertTrue(peerRow.waitForExistence(timeout: 5))
        let peopleList = app.scrollViews["people-list"]
        XCTAssertTrue(peopleList.waitForExistence(timeout: 5), app.debugDescription)
        peopleList.swipeDown()
        XCTAssertTrue(waitUntil(timeout: 15) { peerRow.label != availableLabel }, "The row should reflect the server-confirmed Stop before opening Person again.\n\(app.debugDescription)")
        peerRow.tap()
        XCTAssertTrue(app.staticTexts["person-status"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["person-history"].exists, "Stopping Always must remove the viewer's cached history from the Person screen.")
    }

    func testRealOnboardingHandleRequestAcceptAndStopSharing() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-ui-test-\(suffix)"
        let mainName = "UI\(suffix.prefix(8))"
        let peerName = "Peer\(suffix.prefix(8))"
        // Use only fictional 555-0100..0199 values across established area codes.
        // The fixed 202-555-0199 no-match fixture is excluded. A wide randomized pool
        // avoids reusing persistent local SMS budget keys across sequential simulator runs.
        let reservedPhones = LocalTrustAPI.reservedPhonePool().shuffled().prefix(2)
        let phoneDigits = try XCTUnwrap(reservedPhones.first)
        let peerPhoneDigits = try XCTUnwrap(reservedPhones.dropFirst().first)

        let mainSession = try XCTUnwrap(api.developmentSession(name: mainName, deviceID: deviceID))
        var disposableTokens = [mainSession.token]
        defer { disposableTokens.reversed().forEach { api.deleteAccount(token: $0) } }

        let peerSession = try XCTUnwrap(api.developmentSession(name: peerName, deviceID: "trust-ui-peer-\(suffix)"))
        disposableTokens.append(peerSession.token)


        let peerHandle = "peer\(suffix.prefix(8))"
        XCTAssertEqual(api.putHandle(peerHandle, token: peerSession.token), 204)
        XCTAssertTrue(api.verifyPhone(phone: "+1\(peerPhoneDigits)", token: peerSession.token), "The target must be phone-verified before handle discovery.")
        XCTAssertEqual(api.putAvatarPreset("fox", token: peerSession.token), 200)
        XCTAssertEqual(api.setPhoneDiscovery(true, token: peerSession.token), 204)

        let app = XCUIApplication()
        app.launchEnvironment["TRUST_BASE_URL"] = LocalTrustAPI.baseURL
        app.launchEnvironment["TRUST_STRICT_API"] = "1"
        app.launchEnvironment["TRUST_UI_TEST"] = "1"
        app.launchEnvironment["TRUST_UI_TEST_DEVICE_ID"] = deviceID
        app.launchEnvironment["TRUST_DEV_SESSION"] = "1"
        app.launch()

        let handleField = app.textFields.firstMatch
        XCTAssertTrue(handleField.waitForExistence(timeout: 20), "A fresh development identity should land on real handle onboarding.")
        handleField.tap()
        let suggestedHandle = handleField.value as? String ?? ""
        let chosenHandle = "ui\(suffix.prefix(8))"
        handleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: suggestedHandle.count) + chosenHandle)
        let continueButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Continue")).firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil(timeout: 8) { continueButton.isEnabled }, "The locally checked handle should become available.")
        let discoveryToggle = app.switches["onboarding-discovery-toggle"]
        XCTAssertTrue(discoveryToggle.waitForExistence(timeout: 5))
        discoveryToggle.tap()
        continueButton.tap()

        let phone = app.textFields["phone-number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 12), "Completing the handle should open phone verification.")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "By tapping Send code")).firstMatch.exists)
        phone.tap()
        phone.typeText("+1\(phoneDigits)")
        app.buttons["send-phone-code"].tap()

        let codeNotice = app.staticTexts["phone-notice"]
        XCTAssertTrue(codeNotice.waitForExistence(timeout: 10), "Development API should show its test OTP in the app.")
        let digits = codeNotice.label.filter(\.isNumber)
        XCTAssertEqual(digits.count, 6, "The code used here must come from the app's development-only OTP notice.")
        let codeField = app.textFields["phone-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText(digits)
        app.buttons["verify-phone-code"].tap()
        let enteredApp = app.buttons["tab-sharing"].waitForExistence(timeout: 15)
        XCTAssertTrue(enteredApp, "Phone verification did not advance: \(codeNotice.exists ? codeNotice.label : "no phone notice")")

        let onboarded = api.circle(token: mainSession.token)
        XCTAssertEqual((onboarded?["you"] as? [String: Any])?["handle"] as? String, chosenHandle)
        XCTAssertEqual((onboarded?["you"] as? [String: Any])?["phoneVerified"] as? Bool, true)
        XCTAssertEqual((onboarded?["you"] as? [String: Any])?["discoveryEnabled"] as? Bool, true)

        app.buttons["tab-sharing"].tap()
        let addSomeone = app.buttons["add-someone-button"]
        XCTAssertTrue(addSomeone.waitForExistence(timeout: 10))
        addSomeone.tap()
        let lookupField = app.textFields["connection-handle"]
        XCTAssertTrue(lookupField.waitForExistence(timeout: 10))
        attachScreenshot(of: app, named: "Requests - Add someone empty")
        lookupField.typeText("+1 (\(peerPhoneDigits.prefix(3))) \(peerPhoneDigits.dropFirst(3).prefix(3))-\(peerPhoneDigits.suffix(4))")
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10), "Typing a complete phone number should resolve the exact public handle.")
        XCTAssertEqual(app.staticTexts["connection-lookup-handle"].label, "@\(peerHandle)")
        XCTAssertTrue(app.descendants(matching: .any)["connection-lookup-avatar"].waitForExistence(timeout: 5), "An exact phone match should show the saved picture descriptor.")
        attachScreenshot(of: app, named: "Requests - Phone match and picture")
        lookupField.tap()
        lookupField.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertFalse(app.staticTexts["connection-lookup-handle"].exists, "Editing the query should clear the prior match immediately.")
        app.buttons["clear-connection-lookup"].tap()
        XCTAssertEqual(lookupField.value as? String, "Handle or phone number", "The clear control should empty the entire previous query.")
        lookupField.typeText("+1 202 555 0199")
        let noMatch = app.staticTexts["connection-lookup-no-match"]
        XCTAssertTrue(noMatch.waitForExistence(timeout: 10), "An unmatched complete phone number should show a no-match state.")
        XCTAssertEqual(app.buttons["invite-to-trust"].label, "Share invite link", "The action should describe the native share sheet, without claiming the number is unregistered.")
        attachScreenshot(of: app, named: "Requests - No match invite")
        let outgoingBeforeInvite = (api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]])?.count ?? 0
        app.buttons["invite-to-trust"].tap()
        let nativeShareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(nativeShareSheet.waitForExistence(timeout: 10), "Tapping Invite should open the native share sheet.")
        let copyAction = app.cells.matching(identifier: "actionGroupCell")
            .matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copyAction.waitForExistence(timeout: 5), "The native share sheet should offer its Copy action.")
        attachScreenshot(of: app, named: "Requests - Native invite share sheet")
        app.buttons["header.closeButton"].tap()
        let clearLookup = app.buttons["clear-connection-lookup"]
        // Earlier iOS 27.1 runs ignored close and swipe, but the latest run dismissed
        // normally. Keep the swipe fallback conditional so it is used only if needed.
        if !waitUntil(timeout: 2, condition: { clearLookup.isHittable }) {
            nativeShareSheet.swipeDown()
        }
        var didRelaunchAfterShareSheet = false
        var returnedFromShareSheet = waitUntil(timeout: 5) { clearLookup.isHittable && app.staticTexts["connection-lookup-no-match"].exists }
        if !returnedFromShareSheet {
            didRelaunchAfterShareSheet = true
            // iOS 27.1 can leave the system activity sheet presented after both close
            // and swipe. Relaunch the same authenticated local account and reopen Add.
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["tab-sharing"].waitForExistence(timeout: 15))
            app.buttons["tab-you"].tap()
            let restoredHandle = app.buttons["copy-own-handle"]
            XCTAssertTrue(restoredHandle.waitForExistence(timeout: 10))
            XCTAssertEqual(restoredHandle.value as? String, "@\(chosenHandle)", "Relaunch must restore the same visible account handle.")
            app.buttons["tab-sharing"].tap()
            XCTAssertTrue(addSomeone.waitForExistence(timeout: 10))
            addSomeone.tap()
            returnedFromShareSheet = lookupField.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(returnedFromShareSheet, "The Add screen should be recoverable after dismissing or relaunching from the native share sheet.")
        XCTAssertEqual(api.circle(token: mainSession.token)?["you"].flatMap { ($0 as? [String: Any])?["id"] as? String }, mainSession.personID, "Recovery must return to the same authenticated account.")
        XCTAssertEqual((api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]])?.count ?? 0, outgoingBeforeInvite, "Looking up or sharing an invite must not create a connection request.")
        if didRelaunchAfterShareSheet {
            let recovery = XCTAttachment(string: "iOS 27.1 did not dismiss the native share sheet with close or swipe; the test explicitly relaunched and reopened Add. The authenticated person ID and server request count were checked after recovery.")
            recovery.name = "Diagnostics - iOS 27.1 share-sheet recovery"
            recovery.lifetime = .keepAlways
            add(recovery)
        }
        if !didRelaunchAfterShareSheet {
            app.buttons["clear-connection-lookup"].tap()
        }
        lookupField.typeText(peerHandle)
        XCTAssertTrue(app.staticTexts["connection-lookup-handle"].waitForExistence(timeout: 10))
        app.buttons["send-connection-request"].tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.api.connectionRequests(token: mainSession.token)?["sent"] is [[String: Any]]
                && !((self.api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]]) ?? []).isEmpty
        }, "Sending should create a pending request visible to the sender.")
        app.buttons["cancel-add-person"].tap()
        let sentRequestHandle = app.staticTexts["connection-request-handle-\(peerHandle)"]
        XCTAssertTrue(sentRequestHandle.waitForExistence(timeout: 8), "The sent request should remain visible after closing Add someone.")
        attachScreenshot(of: app, named: "Requests - Sent and pending")
        XCTAssertTrue(addSomeone.waitForExistence(timeout: 5))
        addSomeone.tap()
        XCTAssertTrue(lookupField.waitForExistence(timeout: 5), "The add sheet should reopen after cancellation.")
        XCTAssertEqual(lookupField.value as? String, "Handle or phone number", "Reopening should start with a fresh lookup.")
        app.buttons["cancel-add-person"].tap()
        let cancelPending = app.buttons["cancel-connection-request-\(peerHandle)"]
        XCTAssertTrue(cancelPending.waitForExistence(timeout: 8), "The sent request should expose a UI cancellation action.")
        cancelPending.tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            (self.api.connectionRequests(token: mainSession.token)?["sent"] as? [[String: Any]])?.isEmpty == true
        }, "Canceling from the pending request row should cancel the server request.")

        // The peer cannot race the cancellation above because it is API-only in
        // this focused UI test. Now let it send the reverse request so this UI
        // account exercises the explicit incoming accept flow.
        XCTAssertTrue((200..<300).contains(api.createConnectionRequest(recipientID: mainSession.personID, token: peerSession.token)))
        app.buttons["tab-you"].tap()
        app.buttons["tab-sharing"].tap()
        let incomingAccept = app.buttons["accept-connection-request-\(peerHandle)"]
        XCTAssertTrue(incomingAccept.waitForExistence(timeout: 12), "A received request should show the handle and explicit Accept action.")
        attachScreenshot(of: app, named: "Requests - Incoming with accept and decline")
        incomingAccept.tap()

        let memberGroupID = "sharing-mode-group-\(peerName.lowercased())"
        XCTAssertTrue(app.descendants(matching: .any)[memberGroupID].waitForExistence(timeout: 12), "Accepting the handle request should add the peer to Sharing.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "off"
                && self.inboundPresentation(personID: peerSession.personID, token: mainSession.token) == "off"
        }, "The server should report Off in both directions after the join.")
        let acceptedPerson = app.descendants(matching: .any)[memberGroupID]
        if !acceptedPerson.isHittable { app.swipeUp() }
        attachScreenshot(of: app, named: "Requests - Connected with sharing Off")

        // SwiftUI's native Menu exposes the title as the accessibility label on iOS 27.1,
        // even when its nested button identifier is discarded by the platform menu host.
        let presenceGrant = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Let \(peerName) know when I’m Home or Away")
        ).firstMatch
        XCTAssertTrue(app.buttons["sharing-actions-\(peerName.lowercased())"].waitForExistence(timeout: 5))
        XCTAssertFalse(api.member(personID: peerSession.personID, token: mainSession.token)?["outboundPresenceGranted"] as? Bool ?? true,
                       "Home/Away visibility and arrival alerts must start disabled for a new connection.")
        app.buttons["sharing-actions-\(peerName.lowercased())"].tap()
        XCTAssertTrue(presenceGrant.waitForExistence(timeout: 5))
        presenceGrant.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.api.member(personID: peerSession.personID, token: mainSession.token)?["outboundPresenceGranted"] as? Bool == true
        }, "The per-person control should persist the explicit presence/arrival grant.")
        app.buttons["sharing-actions-\(peerName.lowercased())"].tap()
        XCTAssertTrue(presenceGrant.waitForExistence(timeout: 5))
        presenceGrant.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.api.member(personID: peerSession.personID, token: mainSession.token)?["outboundPresenceGranted"] as? Bool == false
        }, "Turning the per-person grant back off should persist the revocation.")

        let sealed = app.buttons["sharing-mode-sealed-\(peerName.lowercased())"]
        XCTAssertTrue(sealed.waitForExistence(timeout: 5))
        sealed.tap()
        XCTAssertTrue(waitUntil(timeout: 8) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "untilTheyLook"
        }, "The sharing selection should update the peer's server response.")

        let later = app.buttons["always-explainer-later"]
        if later.waitForExistence(timeout: 2) { later.tap() }
        let off = app.buttons["sharing-mode-off-\(peerName.lowercased())"]
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        let offBecameHittable = waitUntil(timeout: 5) { off.isHittable }
        if !offBecameHittable {
            let accessibility = XCTAttachment(string: app.debugDescription)
            accessibility.name = "Diagnostics - Off unavailable after explainer"
            accessibility.lifetime = .keepAlways
            add(accessibility)
            attachScreenshot(of: app, named: "Diagnostics - Off unavailable after explainer")
        }
        XCTAssertTrue(offBecameHittable, "Off should be tappable after the sharing explainer closes.")
        off.tap()
        let confirmStop = app.buttons.matching(identifier: "stop-sharing-confirm")
        XCTAssertTrue(confirmStop.firstMatch.waitForExistence(timeout: 5))
        // SwiftUI exposes two automation aliases for one alert action on Duo.
        confirmStop.element(boundBy: 0).tap()
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "off"
        }, "Stopping sharing should persist Off in the peer's API response.")
        let peerAfterStop = api.member(personID: mainSession.personID, token: peerSession.token)
        XCTAssertEqual(peerAfterStop?["inboundLive"] as? Bool, false)
        XCTAssertTrue(peerAfterStop?["live"] == nil || peerAfterStop?["live"] is NSNull)
    }

    private func inboundPresentation(personID: String, token: String) -> String? {
        guard let inboundShare = api.member(personID: personID, token: token)?["inboundShare"] as? [String: Any] else {
            return nil
        }
        return inboundShare["presentation"] as? String
    }

    private func outboundPresentation(personID: String, token: String) -> String? {
        // CircleResponse serializes the viewer's outbound mode under `share`.
        guard let outboundShare = api.member(personID: personID, token: token)?["share"] as? [String: Any] else {
            return nil
        }
        return outboundShare["presentation"] as? String
    }

    private func yourHomeState(token: String) -> String? {
        guard let home = api.circle(token: token)?["yourHome"] as? [String: Any] else { return nil }
        return home["state"] as? String
    }

    private func visibleHomePresence(personID: String, token: String) -> String? {
        guard let member = api.member(personID: personID, token: token),
              let presence = member["homePresence"] as? [String: Any] else { return nil }
        return presence["state"] as? String
    }

    private func activeConnectionID(personID: String, token: String) -> String? {
        let response = api.memberResponse(personID: personID, token: token)
        guard (200..<300).contains(response.status),
              let connectionID = response.member?["connectionId"] as? String,
              !connectionID.isEmpty else { return nil }
        return connectionID
    }

    private func activeShareRevision(personID: String, token: String) -> Int64? {
        guard let share = api.member(personID: personID, token: token)?["share"] as? [String: Any],
              let revision = share["revision"] as? NSNumber else { return nil }
        return revision.int64Value
    }

    private func successfulCircleOmitsMember(personID: String, token: String) -> Bool {
        let response = api.request("GET", "/api/v1/circle", token: token)
        guard (200..<300).contains(response.status),
              let payload = response.json as? [String: Any],
              let members = payload["members"] as? [[String: Any]] else { return false }
        return !members.contains { ($0["person"] as? [String: Any])?["id"] as? String == personID }
    }

    private func assertReconnectedPair(
        ownToken: String,
        peerToken: String,
        ownID: String,
        peerID: String,
        originalConnectionID: String
    ) throws {
        let ownCircle = api.request("GET", "/api/v1/circle", token: ownToken)
        let peerCircle = api.request("GET", "/api/v1/circle", token: peerToken)
        XCTAssertTrue((200..<300).contains(ownCircle.status), "The reconnected account's circle must load successfully.")
        XCTAssertTrue((200..<300).contains(peerCircle.status), "The other account's circle must load successfully.")
        let ownPayload = try XCTUnwrap(ownCircle.json as? [String: Any])
        let peerPayload = try XCTUnwrap(peerCircle.json as? [String: Any])
        XCTAssertEqual((ownPayload["you"] as? [String: Any])?["id"] as? String, ownID)
        XCTAssertEqual((peerPayload["you"] as? [String: Any])?["id"] as? String, peerID)
        let ownMembers = try XCTUnwrap(ownPayload["members"] as? [[String: Any]])
        let peerMembers = try XCTUnwrap(peerPayload["members"] as? [[String: Any]])
        let memberForPeer = try XCTUnwrap(ownMembers.first { ($0["person"] as? [String: Any])?["id"] as? String == peerID })
        let memberForOwn = try XCTUnwrap(peerMembers.first { ($0["person"] as? [String: Any])?["id"] as? String == ownID })
        let newConnectionID = try XCTUnwrap(memberForPeer["connectionId"] as? String)
        XCTAssertFalse(newConnectionID.isEmpty)
        XCTAssertNotEqual(newConnectionID, originalConnectionID)
        XCTAssertEqual(memberForOwn["connectionId"] as? String, newConnectionID)
        assertReconnectedOffState(memberForPeer)
        assertReconnectedOffState(memberForOwn)
        for token in [ownToken, peerToken] {
            let requests = try XCTUnwrap(api.connectionRequests(token: token))
            XCTAssertTrue((requests["incoming"] as? [[String: Any]])?.isEmpty == true)
            XCTAssertTrue((requests["sent"] as? [[String: Any]])?.isEmpty == true)
        }
    }

    private func assertReconnectedOffState(_ member: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual((member["share"] as? [String: Any])?["presentation"] as? String, "off", file: file, line: line)
        XCTAssertEqual((member["inboundShare"] as? [String: Any])?["presentation"] as? String, "off", file: file, line: line)
        XCTAssertEqual(member["outboundPresenceGranted"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(member["inboundPresenceGranted"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(member["inboundLive"] as? Bool, false, file: file, line: line)
        XCTAssertTrue(member["live"] == nil || member["live"] is NSNull, file: file, line: line)
        XCTAssertTrue(member["homePresence"] == nil || member["homePresence"] is NSNull, file: file, line: line)
    }

    private func waitUntil(timeout: TimeInterval, pollInterval: TimeInterval = 0.25, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return condition()
    }

    private func allowBackgroundLocationIfPrompted(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let explainerAction = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Allow background location")
        ).firstMatch
        guard explainerAction.waitForExistence(timeout: 2) else { return }
        explainerAction.tap()

        let appWhileUsing = app.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "While Using")
        ).firstMatch
        let systemWhileUsing = springboard.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "While Using")
        ).firstMatch
        XCTAssertTrue(waitUntil(timeout: 8) { appWhileUsing.exists || systemWhileUsing.exists }, "Trust should request foreground location before upgrading to Always.\n\(app.debugDescription)\n\(springboard.debugDescription)")
        (appWhileUsing.exists ? appWhileUsing : systemWhileUsing).tap()

        let appAlways = app.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Always")
        ).firstMatch
        let systemAlways = springboard.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Always")
        ).firstMatch
        XCTAssertTrue(waitUntil(timeout: 12) { appAlways.exists || systemAlways.exists }, "Accepting foreground access should lead to the requested Always location choice.\n\(app.debugDescription)\n\(springboard.debugDescription)")
        (appAlways.exists ? appAlways : systemAlways).tap()
    }

    private func scrollUpUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
    }

    private func isSwitchOn(_ element: XCUIElement) -> Bool {
        let value = String(describing: element.value ?? "").lowercased()
        return value == "1" || value == "on" || value == "true"
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct DisposableSession {
    let token: String
    let personID: String
}

/// XCTest runner helper that has no configurable host: every operation stays on loopback.
private final class LocalTrustAPI {
    static var baseURL: String { ProcessInfo.processInfo.environment["TRUST_UI_TEST_BASE_URL"] ?? "" }
    private var base: URL? { URL(string: Self.baseURL) }
    var hasSafeConfiguration: Bool {
        guard let base,
              base.scheme?.lowercased() == "http",
              base.port == 5089,
              base.user == nil,
              base.password == nil,
              base.query == nil,
              base.fragment == nil,
              base.path.isEmpty || base.path == "/" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(base.host?.lowercased() ?? "")
    }

    func healthIsAvailable() -> Bool {
        let result = request("GET", "/health/live")
        return (200..<300).contains(result.status)
    }

    func developmentOTPWithoutSMSIsEnabled() -> Bool {
        let result = request("GET", "/api/v1/local-test-capabilities")
        return (200..<300).contains(result.status)
            && (result.json as? [String: Any])?["developmentOtpWithoutSms"] as? Bool == true
    }

    static func reservedPhonePool() -> [String] {
        let areaCodes = ["202", "212", "213", "305", "310", "312", "415", "617", "718", "917"]
        return areaCodes.flatMap { areaCode in
            (0..<100).compactMap { slot -> String? in
                let number = areaCode + "55501" + String(format: "%02d", slot)
                return number == "2025550199" ? nil : number
            }
        }
    }

    func developmentSession(name: String, deviceID: String) -> DisposableSession? {
        let result = request("POST", "/api/v1/session/development", body: ["displayName": name, "deviceId": deviceID])
        guard result.status == 200,
              let json = result.json as? [String: Any],
              let token = json["token"] as? String,
              let you = json["you"] as? [String: Any],
              let personID = you["id"] as? String else { return nil }
        return DisposableSession(token: token, personID: personID)
    }

    func putHandle(_ handle: String, token: String) -> Int {
        request("PUT", "/api/v1/me/handle", token: token, body: ["handle": handle]).status
    }

    func putAvatarPreset(_ presetID: String, token: String) -> Int {
        request("PUT", "/api/v1/me/avatar/preset", token: token, body: ["presetId": presetID]).status
    }

    func setPhoneDiscovery(_ enabled: Bool, token: String) -> Int {
        request("PUT", "/api/v1/me/discovery", token: token, body: ["enabled": enabled, "consentVersion": 1]).status
    }

    func setPresenceGrant(personID: String, token: String, enabled: Bool) -> Int {
        guard let member = member(personID: personID, token: token),
              let connectionID = member["connectionId"] as? String else { return 0 }
        let revision = member["outboundPresenceRevision"] as? Int64 ?? 0
        return request(
            "PUT",
            "/api/v1/people/\(personID)/presence-grant",
            token: token,
            body: ["connectionId": connectionID, "revision": revision, "enabled": enabled]
        ).status
    }

    func postHomePresence(state: String, token: String) -> Int {
        request("POST", "/api/v1/me/home/presence", token: token, body: ["state": state]).status
    }

    func verifyPhone(phone: String, token: String) -> Bool {
        let sent = request("POST", "/api/v1/me/phone/send", token: token, body: ["phone": phone])
        guard (200..<300).contains(sent.status),
              let payload = sent.json as? [String: Any],
              // A development code is returned only on the no-SMS path.
              let code = payload["developmentCode"] as? String,
              code.count == 6,
              code.allSatisfy(\.isNumber) else { return false }
        return (200..<300).contains(request("POST", "/api/v1/me/phone/verify", token: token, body: ["phone": phone, "code": code]).status)
    }

    func connectionRequests(token: String) -> [String: Any]? {
        request("GET", "/api/v1/connection-requests", token: token).json as? [String: Any]
    }

    func createConnectionRequest(recipientID: String, token: String) -> Int {
        request("POST", "/api/v1/connection-requests", token: token, body: ["recipientId": recipientID]).status
    }

    func lookupPerson(handle: String, token: String) -> String? {
        guard let payload = lookupPersonResponse(handle: handle, token: token).json as? [String: Any] else { return nil }
        return payload["accountId"] as? String
    }

    func lookupPersonResponse(handle: String, token: String) -> (status: Int, json: Any?) {
        request("POST", "/api/v1/people/lookup", token: token, body: ["handle": handle])
    }

    func circle(token: String) -> [String: Any]? {
        request("GET", "/api/v1/circle", token: token).json as? [String: Any]
    }

    func hasLookEvent(subjectID: String, token: String) -> Bool {
        latestLookEvent(subjectID: subjectID, token: token) != nil
    }

    func latestLookEvent(subjectID: String, token: String) -> [String: Any]? {
        guard let events = circle(token: token)?["lookLog"] as? [[String: Any]] else { return nil }
        return events.last { ($0["subjectId"] as? String)?.lowercased() == subjectID.lowercased() }
    }

    func yourHomePlace(token: String) -> (status: Int, label: String?, placeID: String?) {
        let response = request("GET", "/api/v1/circle", token: token)
        guard (200..<300).contains(response.status),
              let payload = response.json as? [String: Any],
              let yourHome = payload["yourHome"] as? [String: Any],
              let place = yourHome["place"] as? [String: Any] else {
            return (response.status, nil, nil)
        }
        return (response.status, place["label"] as? String, place["placeId"] as? String)
    }

    func member(personID: String, token: String) -> [String: Any]? {
        guard let members = circle(token: token)?["members"] as? [[String: Any]] else { return nil }
        return members.first { ($0["person"] as? [String: Any])?["id"] as? String == personID }
    }

    func memberResponse(personID: String, token: String) -> (status: Int, member: [String: Any]?) {
        let response = request("GET", "/api/v1/circle", token: token)
        guard (200..<300).contains(response.status),
              let payload = response.json as? [String: Any],
              let members = payload["members"] as? [[String: Any]] else {
            return (response.status, nil)
        }
        let member = members.first { ($0["person"] as? [String: Any])?["id"] as? String == personID }
        return (response.status, member)
    }

    func deleteAccount(token: String) {
        let result = request("DELETE", "/api/v1/account", token: token)
        // 404 is acceptable when an earlier cleanup or server cascade already removed it.
        assert(result.status == 204 || result.status == 404, "Failed to delete disposable local API test account.")
    }

    func placePrivacyHold(token: String) -> Int {
        request("POST", "/api/v1/age-assurance/privacy-hold", token: token).status
    }

    func request(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) -> (status: Int, json: Any?) {
        guard hasSafeConfiguration, let base, let url = URL(string: path, relativeTo: base) else { return (0, nil) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var responseStatus = 0
        var responseJSON: Any?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            responseStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, !data.isEmpty { responseJSON = try? JSONSerialization.jsonObject(with: data) }
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 12) == .success else { return (0, nil) }
        return (responseStatus, responseJSON)
    }
}
