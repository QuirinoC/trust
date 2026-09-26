import Foundation
import XCTest

/// Development-only end-to-end lane. It is deliberately pinned to loopback and creates
/// disposable identities that are deleted even when an assertion fails.
final class TrustRealAPIFeatureTests: XCTestCase {
    private let api = LocalTrustAPI()

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard api.isLoopback, api.healthIsAvailable() else {
            throw XCTSkip("The real local API is unavailable; skipping its opt-in simulator lane.")
        }
    }

    func testRealOnboardingInviteAndStopSharing() throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let deviceID = "trust-ui-test-\(suffix)"
        let mainName = "UI\(suffix.prefix(8))"
        let peerName = "Peer\(suffix.prefix(8))"
        // Avoid the shared 555-01xx review fixtures; this random, valid NANP value is
        // effectively unique among existing development identities.
        let phoneDigits = "2127" + String(format: "%06d", Int.random(in: 0...999_999))

        let mainSession = try XCTUnwrap(api.developmentSession(name: mainName, deviceID: deviceID))
        var disposableTokens = [mainSession.token]
        defer { disposableTokens.reversed().forEach { api.deleteAccount(token: $0) } }

        let peerSession = try XCTUnwrap(api.developmentSession(name: peerName, deviceID: "trust-ui-peer-\(suffix)"))
        disposableTokens.append(peerSession.token)

        XCTAssertEqual(api.putHandle("peer\(suffix.prefix(8))", token: peerSession.token), 204)
        let inviteResponse = api.request("POST", "/api/v1/invites", token: peerSession.token)
        XCTAssertEqual(inviteResponse.status, 200, "The second disposable identity should create an invite.")
        let inviteCode = try XCTUnwrap((inviteResponse.json as? [String: Any])?["code"] as? String)

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

        app.buttons["tab-sharing"].tap()
        let addSomeone = app.buttons["add-someone-button"]
        XCTAssertTrue(addSomeone.waitForExistence(timeout: 10))
        addSomeone.tap()
        let inviteField = app.textFields["invite-code"]
        XCTAssertTrue(inviteField.waitForExistence(timeout: 10))
        inviteField.tap()
        inviteField.typeText(inviteCode)
        app.buttons["join-invite-button"].tap()

        let memberGroupID = "sharing-mode-group-\(peerName.lowercased())"
        XCTAssertTrue(app.descendants(matching: .any)[memberGroupID].waitForExistence(timeout: 12), "Invite acceptance should add the API-created peer to Sharing.")
        XCTAssertTrue(waitUntil(timeout: 10) {
            self.inboundPresentation(personID: mainSession.personID, token: peerSession.token) == "off"
                && self.inboundPresentation(personID: peerSession.personID, token: mainSession.token) == "off"
        }, "The server should report Off in both directions after the join.")

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
        XCTAssertTrue(waitUntil(timeout: 5) { off.isHittable }, "Off should be tappable after the sharing explainer closes.")
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

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }
}

private struct DisposableSession {
    let token: String
    let personID: String
}

/// XCTest runner helper that has no configurable host: every operation stays on loopback.
private final class LocalTrustAPI {
    static let baseURL = "http://127.0.0.1:5088"
    private let base = URL(string: baseURL)!
    var isLoopback: Bool { base.host == "127.0.0.1" }

    func healthIsAvailable() -> Bool {
        let result = request("GET", "/health/live")
        return (200..<300).contains(result.status)
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

    func circle(token: String) -> [String: Any]? {
        request("GET", "/api/v1/circle", token: token).json as? [String: Any]
    }

    func member(personID: String, token: String) -> [String: Any]? {
        guard let members = circle(token: token)?["members"] as? [[String: Any]] else { return nil }
        return members.first { ($0["person"] as? [String: Any])?["id"] as? String == personID }
    }

    func deleteAccount(token: String) {
        let result = request("DELETE", "/api/v1/account", token: token)
        // 404 is acceptable when an earlier cleanup or server cascade already removed it.
        assert(result.status == 204 || result.status == 404, "Failed to delete disposable local API test account.")
    }

    func request(_ method: String, _ path: String, token: String? = nil, body: [String: String]? = nil) -> (status: Int, json: Any?) {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
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
