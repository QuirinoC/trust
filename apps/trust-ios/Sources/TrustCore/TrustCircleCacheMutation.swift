import Foundation

/// Patches only a server-confirmed relationship in the last-good circle response.
/// Keeping the API-shaped cache preserves offline startup without resurrecting a
/// share or removed relationship after the app process restarts.
public enum TrustCircleCacheMutation {
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
}
