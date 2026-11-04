import Foundation

/// Patches only a server-confirmed relationship in the last-good circle response.
/// Keeping the API-shaped cache preserves offline startup without resurrecting a
/// share or removed relationship after the app process restarts.
public enum TrustCircleCacheMutation {
    /// Clears only ongoing live/history fields. Look snapshots live separately in
    /// the retained look log and remain subject to their existing consent rules.
    public static func scrubbingUnauthorizedLiveData(
        in data: Data,
        accountID: UUID,
        now: Date = Date()
    ) -> Data? {
        guard var payload = decode(data, accountID: accountID),
              var members = payload["members"] as? [[String: Any]] else { return nil }
        var changed = false
        for index in members.indices {
            let member = members[index]
            let authorized = member["inboundLive"] as? Bool ?? false
            let notExpired: Bool
            if let expiryValue = member["liveAccessExpiresAt"], !(expiryValue is NSNull) {
                if let rawExpiry = expiryValue as? String,
                   let expiry = parseDate(rawExpiry) {
                    notExpired = expiry > now
                } else {
                    // A present but malformed expiry is not the server's explicit
                    // no-expiry value. Fail closed so cached coordinates cannot
                    // outlive an undecodable authorization window.
                    notExpired = false
                }
            } else {
                // Missing/null expiry is valid for an authorized non-expiring grant.
                notExpired = true
            }
            guard !authorized || !notExpired else { continue }
            if members[index]["live"] != nil, !(members[index]["live"] is NSNull) {
                members[index]["live"] = NSNull()
                changed = true
            }
            if members[index]["trail"] != nil, !(members[index]["trail"] is NSNull) {
                members[index]["trail"] = NSNull()
                changed = true
            }
            if members[index]["locationHistory"] != nil, !(members[index]["locationHistory"] is NSNull) {
                members[index]["locationHistory"] = NSNull()
                changed = true
            }
        }
        guard changed else { return data }
        payload["members"] = members
        return encode(payload)
    }

    public static func belongsToAccount(_ data: Data, accountID: UUID) -> Bool {
        decode(data, accountID: accountID) != nil
    }

    public static func updatingShare(
        in data: Data,
        accountID: UUID,
        personID: UUID,
        connectionID: UUID,
        share: PersonShareState,
        now: Date = Date()
    ) -> Data? {
        guard var payload = decode(data, accountID: accountID),
              var members = payload["members"] as? [[String: Any]],
              let index = members.firstIndex(where: {
                  matches($0, personID: personID, connectionID: connectionID)
              }) else { return nil }

        let resting: String
        let presentation: String
        let pauseUntil: Any
        let restoresTo: Any
        switch share.presentation(at: now) {
        case .off:
            resting = "off"
            presentation = "off"
            pauseUntil = NSNull()
            restoresTo = NSNull()
        case .untilTheyLook:
            resting = "untilTheyLook"
            presentation = "untilTheyLook"
            pauseUntil = NSNull()
            restoresTo = NSNull()
        case .always:
            resting = "always"
            presentation = "always"
            pauseUntil = NSNull()
            restoresTo = NSNull()
        case .paused(let ends, let revertsTo):
            resting = "paused"
            presentation = "paused"
            pauseUntil = iso8601(ends)
            restoresTo = revertsTo == .always ? "always" : "untilTheyLook"
        }
        members[index]["share"] = [
            "resting": resting,
            "pauseUntil": pauseUntil,
            "presentation": presentation,
            "revertsTo": restoresTo,
            // The mutation response omits the new server revision. Nil forces a fresh
            // circle read before a later consent-enabling write.
            "revision": NSNull()
        ]
        payload["members"] = members
        return encode(payload)
    }

    public static func removing(
        from data: Data,
        accountID: UUID,
        personID: UUID,
        connectionID: UUID
    ) -> Data? {
        guard var payload = decode(data, accountID: accountID),
              let members = payload["members"] as? [[String: Any]],
              members.contains(where: { matches($0, personID: personID, connectionID: connectionID) }) else {
            return nil
        }
        payload["members"] = members.filter { !matches($0, personID: personID, connectionID: connectionID) }
        return encode(payload)
    }

    private static func decode(_ data: Data, accountID: UUID) -> [String: Any]? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let you = payload["you"] as? [String: Any],
              let rawOwnerID = you["id"] as? String,
              UUID(uuidString: rawOwnerID) == accountID else { return nil }
        return payload
    }

    private static func matches(_ member: [String: Any], personID: UUID, connectionID: UUID) -> Bool {
        guard let person = member["person"] as? [String: Any],
              let rawPersonID = person["id"] as? String,
              let rawConnectionID = member["connectionId"] as? String else { return false }
        return UUID(uuidString: rawPersonID) == personID
            && UUID(uuidString: rawConnectionID) == connectionID
    }

    private static func encode(_ payload: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(payload) else { return nil }
        return try? JSONSerialization.data(withJSONObject: payload)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}
