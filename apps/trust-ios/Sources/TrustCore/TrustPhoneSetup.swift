import Foundation

public enum TrustPhoneSetupRoute: Equatable {
    case handle, phone, home
    public static func route(handle: String?, phoneVerified: Bool) -> Self {
        guard let handle, case .valid = TrustHandle.status(of: handle) else { return .handle }
        return phoneVerified ? .home : .phone
    }
}

/// Only retry timing and normalized destinations are persisted, never a verification code.
/// The server remains authoritative when another device has consumed an allowance.
public struct TrustPhoneRetryState: Codable, Equatable {
    public var challengeNumber: String?
    public var challengeExpiresAt: Date?
    public var showingCode: Bool? = false
    public var attemptedNumbers: Set<String> = []
    public var numberDeadlines: [String: Date] = [:]
    public var accountWindowStartedAt: Date?
    public var accountSendCount: Int?
    public var resendDeadline: Date?
    public var correctionDeadline: Date?
    public var globalDeadline: Date?
    public var immediateNumbersRemaining: Int = 3
    public init() {}

    public static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter { $0 >= "0" && $0 <= "9" }
        if trimmed.hasPrefix("+") { return "+" + digits }
        return "+" + (digits.count == 10 ? "1" : "") + digits
    }

    public func deadline(for raw: String) -> Date? {
        let number = Self.normalized(raw)
        let isCorrection = !attemptedNumbers.contains(number) && immediateNumbersRemaining > 0
        return [globalDeadline, correctionDeadline, isCorrection ? nil : resendDeadline, numberDeadlines[number]].compactMap { $0 }.max()
    }

    public func secondsRemaining(for raw: String, now: Date) -> Int {
        max(0, Int(ceil((deadline(for: raw) ?? now).timeIntervalSince(now))))
    }

    public mutating func apply(phone: String, serverTime: Date?, resendAt: Date?, correctionAt: Date?,
                               remaining: Int?, retryAt: Date? = nil, accepted: Bool, now: Date,
                               accountAt: Date? = nil, accountWindow: Date? = nil, accountCount: Int? = nil) {
        // Translate the server duration onto this device's clock to tolerate clock skew.
        func local(_ date: Date?) -> Date? {
            date.map { now.addingTimeInterval($0.timeIntervalSince(serverTime ?? now)) }
        }
        let number = Self.normalized(phone)
        let newerWindow = accountWindow.map { $0 > (accountWindowStartedAt ?? .distantPast) } ?? false
        let olderWindow = accountWindow.map { $0 < (accountWindowStartedAt ?? .distantPast) } ?? false
        let olderCount = !newerWindow && (accountCount ?? Int.max) < (accountSendCount ?? 0)
        // Reordered delivery responses can carry an older budget snapshot even with a newer response timestamp.
        if olderWindow || olderCount {
            if accepted && !olderWindow { attemptedNumbers.insert(number) }
            if let date = local(retryAt ?? resendAt) { numberDeadlines[number] = max(numberDeadlines[number] ?? .distantPast, date) }
            return
        }
        if newerWindow { attemptedNumbers = [] }
        if let accountWindow { accountWindowStartedAt = accountWindow }
        if let accountCount { accountSendCount = accountCount }
        if accepted {
            // A new server window restores grace; discard history from the preceding window.
            if let remaining, remaining > immediateNumbersRemaining { attemptedNumbers = [] }
            attemptedNumbers.insert(number)
            if attemptedNumbers.count > 8 { attemptedNumbers = [number] }
        }
        if let remaining { immediateNumbersRemaining = remaining }
        if let date = local(accountAt ?? resendAt) { resendDeadline = date }
        if let date = local(resendAt) { numberDeadlines[number] = date }
        if let date = local(correctionAt) { correctionDeadline = date }
        if let date = local(retryAt) { numberDeadlines[number] = date }
        if numberDeadlines.count > 8 { numberDeadlines = Dictionary(uniqueKeysWithValues: numberDeadlines.filter { $0.value > now }.sorted { $0.value > $1.value }.prefix(8).map { ($0.key, $0.value) }) }
    }
}
