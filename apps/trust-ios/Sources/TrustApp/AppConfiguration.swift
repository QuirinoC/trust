import Foundation
import UIKit

enum AppConfiguration {
    static let monthlyProductID = "com.collapsetechnologies.trust.circle.monthly"
    static let annualProductID = "com.collapsetechnologies.trust.circle.annual"
    static let bundleIdentifier = "com.collapsetechnologies.trust"
    static let monthlyDisplayPrice = "$7.99"
    static let annualDisplayPrice = "$69.99"
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    static let productionAPIURL = URL(string: "https://trust.collapsetechnologies.com")!
    static let localAPIURL = URL(string: "http://127.0.0.1:5088")!
    static let legalSiteURL = URL(string: "https://jointrust.app")!
    static let privacyURL = URL(string: "https://jointrust.app/privacy")!
    static let termsURL = URL(string: "https://jointrust.app/terms")!
    static let supportURL = URL(string: "https://jointrust.app/support")!
    static let marketingURL = URL(string: "https://jointrust.app")!

    static let requestTimeout: TimeInterval = 15
    static let healthProbeTimeout: TimeInterval = 3

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    /// Build setting, scheme env, or Debug/Release default.
    /// Physical Debug builds must not use loopback — that is the phone, not the Mac API.
    static var apiBaseURL: URL {
        remapLoopbackOnDevice(configuredAPIBaseURL)
    }

    static var usesProductionAPI: Bool {
        apiBaseURL.host?.contains("collapsetechnologies.com") == true
    }

    static var apiHostDescription: String {
        apiBaseURL.host ?? apiBaseURL.absoluteString
    }

    static func isLoopback(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "127.0.0.1" || host == "localhost" || host == "::1" || host == "[::1]"
    }

    /// Set only by the `Trust-Sandbox` scheme (`TRUST_STRICT_API=1`). L2 sandbox verification
    /// is worthless if a down Dev API silently hands the session to production — see
    /// `debugAPICandidates` and `remapLoopbackOnDevice`.
    static var isStrictAPIMode: Bool {
        ProcessInfo.processInfo.environment["TRUST_STRICT_API"] == "1"
    }

    /// Ordered hosts `prepare()` probes with `/health/live` to resolve `resolvedBaseURL`.
    /// In strict (Trust-Sandbox) mode this is **only** the configured host — never Simulator
    /// loopback, never production — so an unreachable Dev API surfaces as `reachabilityNotice`
    /// instead of quietly resolving to `productionAPIURL`.
    static func debugAPICandidates(preferred: URL = apiBaseURL) -> [URL] {
        var urls: [URL] = [preferred]
        #if DEBUG
        if !isStrictAPIMode {
            if isSimulator, preferred != localAPIURL {
                urls.append(localAPIURL)
            }
            if preferred != productionAPIURL {
                urls.append(productionAPIURL)
            }
        }
        #endif
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    static func isAPILive(_ base: URL) async -> Bool {
        guard let url = URL(string: "/health/live", relativeTo: base)?.absoluteURL else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = healthProbeTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = healthProbeTimeout
        config.timeoutIntervalForResource = healthProbeTimeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    static func firstReachableAPI(preferred: URL = apiBaseURL) async -> URL? {
        for url in debugAPICandidates(preferred: preferred) {
            if await isAPILive(url) { return url }
        }
        return nil
    }

    private static var configuredAPIBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment["TRUST_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "TRUST_BASE_URL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty,
               !trimmed.hasPrefix("$("),
               let url = URL(string: trimmed) {
                return url
            }
        }
        #if DEBUG
        return isSimulator ? localAPIURL : productionAPIURL
        #else
        return productionAPIURL
        #endif
    }

    private static func remapLoopbackOnDevice(_ url: URL) -> URL {
        #if DEBUG
        // Strict mode never falls back to production: a misconfigured loopback URL on a
        // physical device should fail loud (unreachable), not quietly ship the session to prod.
        if !isSimulator, isLoopback(url), !isStrictAPIMode {
            return productionAPIURL
        }
        #endif
        return url
    }
}
