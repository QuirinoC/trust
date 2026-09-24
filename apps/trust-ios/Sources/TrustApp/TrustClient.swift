import Foundation
import TrustCore
import UIKit

struct SessionPayload: Decodable {
    var token: String
    var you: PersonDTO
}

struct PersonDTO: Decodable {
    var id: UUID
    var displayName: String
    var hasCircle: Bool
    var onboardingComplete: Bool?
    var phoneVerified: Bool?
    var handle: String?
}

struct HandleAvailabilityPayload: Decodable {
    var handle: String
    var available: Bool
    var code: String?
}

struct SendPhoneCodePayload: Decodable {
    var expiresAt: Date
    var resendAfterSeconds: Int
    var developmentCode: String?
}

struct AddPersonByPhonePayload: Decodable {
    var outcome: String
    var smsSent: Bool
    var developmentCode: String?
}

struct PresenceDTO: Decodable {
    var lastActiveAt: Date
    var batteryPercent: Int
    var isCharging: Bool
    var gotHomeAt: Date?
    var checkedInAt: Date?
}

struct HomePresenceDTO: Decodable {
    var state: String
    var changedAt: Date
    var placeLabel: String?
}

struct PromiseDTO: Decodable {
    var id: UUID
    var subjectId: UUID
    var trusteeId: UUID
    var placeLabel: String
    var deadlineAt: Date
    var status: String
    var resolvedAt: Date?
    var youAreSubject: Bool
}

struct YourHomeDTO: Decodable {
    var place: HomePlaceDTO?
    var state: String?
    var changedAt: Date?
}

struct HomePlaceDTO: Decodable {
    var placeId: UUID
    var label: String
}

struct LocationDTO: Decodable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
}

struct ShareDTO: Decodable {
    var resting: String
    var pauseUntil: Date?
    var presentation: String
    var revertsTo: String?
}

struct MemberDTO: Decodable {
    var person: PersonDTO
    var presence: PresenceDTO?
    var share: ShareDTO
    var inboundLive: Bool
    var live: LocationDTO?
    var outboundPresenceGranted: Bool?
    var inboundPresenceGranted: Bool?
    var homePresence: HomePresenceDTO?
    var promise: PromiseDTO?
    /// Their share toward you. Optional for pre-inboundShare servers; Circle falls back to Look-probe.
    var inboundShare: ShareDTO?
    /// Older points, when the server sends them. Absent on the current API — live is the only fix.
    var trail: [LocationDTO]?
}

struct CoverageDTO: Decodable {
    var isCovered: Bool
    var sponsorName: String?
    var actingIsSponsor: Bool
    var seatLimit: Int?
    var lookLogDays: Int?
    var hasPlacePings: Bool?
    var canExtendHistory: Bool?
    var canExportLookLog: Bool?
    var banner: String?
}

struct LookEventDTO: Decodable {
    var id: UUID
    var viewerId: UUID
    var viewerName: String
    var subjectId: UUID
    var subjectName: String
    var at: Date
    var historyWindowHours: Int
    var includedLive: Bool
    /// `look` | `view` | `removed`. Absent on pre-006 servers → look.
    var kind: String?
}

struct LookSessionDTO: Decodable {
    var event: LookEventDTO
    var live: LocationDTO
    var trail: [LocationDTO]
}

/// `POST /views` — Available only; logged unless deduped; never a push.
struct ViewPayload: Decodable {
    var logged: Bool
    var event: LookEventDTO?
}

struct CirclePayload: Decodable {
    var you: PersonDTO
    var members: [MemberDTO]
    var coverage: CoverageDTO
    var pendingInviteCode: String?
    var lookLog: [LookEventDTO]
    var retainedLookLogCount: Int
    var allowsDevelopmentSignIn: Bool
    var allowsReviewUnlock: Bool?
    var yourHome: YourHomeDTO?
}

struct InvitePayload: Decodable {
    var code: String
}

struct APIErrorPayload: Decodable {
    var code: String?
    var message: String?
}

struct CircleSnapshot {
    var you: Person
    var members: [TrustedPerson]
    var coverage: CircleCoverage
    var pendingInviteCode: String?
    var lookLog: [LookEvent]
    var retainedLookLogCount: Int
    var allowsDevelopmentSignIn: Bool
    var allowsReviewUnlock: Bool
    var yourHomePlaceID: UUID?
    var yourHomeLabel: String?
    /// Your global presence triad state. `nil` = never set (server "unknown").
    var yourHomeState: HomePresenceKind?
    /// When this snapshot was fetched. Set from the disk cache when offline.
    var fetchedAt: Date = Date()
}

enum TrustClientError: LocalizedError {
    case unauthorized
    case unreachable
    case timeout
    case serverUnavailable(Int)
    /// A known API error code (`pro_required`, `share_off`, …) with plain copy already mapped.
    case api(code: String, message: String)
    /// Unknown server message — passed through.
    case server(String)
    case decoding

    /// Connectivity, not a decision the server made. These are the cases the offline
    /// fallback (disk-cached circle) responds to.
    var isConnectivity: Bool {
        switch self {
        case .unreachable, .timeout, .serverUnavailable: return true
        default: return false
        }
    }

    var apiCode: String? {
        if case .api(let code, _) = self { return code }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return TrustCopy.signInExpired
        case .unreachable:
            #if DEBUG
            return TrustCopy.cannotReachHost(AppConfiguration.apiHostDescription)
            #else
            return TrustCopy.cannotReachServer
            #endif
        case .timeout:
            #if DEBUG
            return TrustCopy.signInTimedOutHost(AppConfiguration.apiHostDescription)
            #else
            return TrustCopy.signInTimedOut
            #endif
        case .serverUnavailable(let status):
            #if DEBUG
            return TrustCopy.serverUnavailableHost(status: status, host: AppConfiguration.apiHostDescription)
            #else
            return TrustCopy.serverUnavailable
            #endif
        case .api(_, let message):
            return message
        case .server(let message):
            return message
        case .decoding:
            return TrustCopy.decodingError
        }
    }
}

/// Last good `/circle` body on disk so the app opens to your circle when offline.
/// Coordinates for Available people are part of that body; the file lives in the app
/// container (Caches, not backed up) and is wiped on sign-out and account delete.
enum CircleCache {
    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = base.appendingPathComponent("trust", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("circle.json")
    }

    static func save(_ data: Data) {
        guard let fileURL else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    static func load() -> (data: Data, savedAt: Date)? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let savedAt = (attributes?[.modificationDate] as? Date) ?? Date()
        return (data, savedAt)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

@MainActor
final class TrustClient {
    var token: String?
    var snapshot: CircleSnapshot?
    private(set) var resolvedBaseURL: URL = AppConfiguration.apiBaseURL
    private(set) var reachabilityNotice: String?

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = AppConfiguration.requestTimeout
        config.timeoutIntervalForResource = AppConfiguration.requestTimeout + 5
        return URLSession(configuration: config)
    }()

    func prepare() async {
        let preferred = AppConfiguration.apiBaseURL
        #if DEBUG
        if let live = await AppConfiguration.firstReachableAPI(preferred: preferred) {
            resolvedBaseURL = live
            reachabilityNotice = nil
            return
        }
        resolvedBaseURL = preferred
        reachabilityNotice = TrustCopy.cannotReachLocal(preferred.host ?? preferred.absoluteString)
        #else
        resolvedBaseURL = preferred
        reachabilityNotice = nil
        #endif
    }

    /// `nonce` is the exact value set on `ASAuthorizationAppleIDRequest.nonce`; the server
    /// compares it with the ID token's `nonce` claim (replay hygiene). Optional for back-compat.
    func appleSession(identityToken: String, displayName: String?, nonce: String? = nil) async throws -> SessionPayload {
        struct Body: Encodable {
            var identityToken: String
            var displayName: String
            var nonce: String?
        }
        let payload: SessionPayload = try await post(
            path: "/api/v1/session/apple",
            body: Body(identityToken: identityToken, displayName: displayName ?? "You", nonce: nonce),
            authorized: false
        )
        token = payload.token
        return payload
    }

    func googleSession(idToken: String?, displayName: String?) async throws {
        struct Body: Encodable {
            var idToken: String?
            var displayName: String
            var provider: String
            var deviceId: String
        }
        let payload: SessionPayload = try await post(
            path: "/api/v1/session/google",
            body: Body(
                idToken: idToken,
                displayName: displayName ?? "You",
                provider: "google",
                deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            ),
            authorized: false
        )
        token = payload.token
    }

    #if DEBUG
    /// Local API only. Release builds do not include this call. The server returns 404 unless
    /// `Auth:AllowDevelopmentSignIn` is on, which production leaves off.
    func developmentSession(displayName: String, deviceId: String) async throws -> SessionPayload {
        struct Body: Encodable {
            var displayName: String
            var provider: String
            var deviceId: String
        }
        let payload: SessionPayload = try await post(
            path: "/api/v1/session/development",
            body: Body(displayName: displayName, provider: "development", deviceId: deviceId),
            authorized: false
        )
        token = payload.token
        return payload
    }
    #endif

    func refreshCircle() async throws -> CircleSnapshot {
        let request = try makeRequest(path: "/api/v1/circle", method: "GET", authorized: true)
        let data: Data = try await sendRaw(request)
        let payload: CirclePayload
        do {
            payload = try decoder.decode(CirclePayload.self, from: data)
        } catch {
            throw TrustClientError.decoding
        }
        CircleCache.save(data)
        let snapshot = payload.snapshot
        self.snapshot = snapshot
        return snapshot
    }

    /// Last good circle from disk, for offline launch. Nil when nothing was ever fetched.
    func cachedCircle() -> CircleSnapshot? {
        guard let cached = CircleCache.load(),
              let payload = try? decoder.decode(CirclePayload.self, from: cached.data) else {
            return nil
        }
        var snapshot = payload.snapshot
        snapshot.fetchedAt = cached.savedAt
        return snapshot
    }

    func clearCache() {
        CircleCache.clear()
        snapshot = nil
    }

    func ingest(_ point: LocationPoint, battery: Int?, charging: Bool?) async throws {
        try await ingest(points: [point], battery: battery, charging: charging)
    }

    func ingest(points: [LocationPoint], battery: Int?, charging: Bool?) async throws {
        guard let last = points.last else { return }
        struct Point: Encodable {
            var timestamp: Date
            var latitude: Double
            var longitude: Double
        }
        struct Body: Encodable {
            var timestamp: Date
            var latitude: Double
            var longitude: Double
            var batteryPercent: Int?
            var isCharging: Bool?
            var points: [Point]
        }
        try await postEmpty(
            path: "/api/v1/location",
            body: Body(
                timestamp: last.timestamp,
                latitude: last.latitude,
                longitude: last.longitude,
                batteryPercent: battery,
                isCharging: charging,
                points: points.map { Point(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude) }
            )
        )
    }

    /// Sealed only. One snapshot; the subject gets a receipt push.
    /// 409 `share_off` / `look_requires_sealed` / `no_location` surface as `.api`.
    func look(subjectID: UUID, confirmed: Bool) async throws -> LookSession {
        struct Body: Encodable {
            var subjectId: UUID
            var confirmed: Bool
        }
        let payload: LookSessionDTO = try await post(
            path: "/api/v1/looks",
            body: Body(subjectId: subjectID, confirmed: confirmed),
            authorized: true
        )
        return payload.model
    }

    /// Available only. Logs a `view` (deduped server-side), never pushes.
    /// 409 `view_requires_available` surfaces as `.api`.
    func view(subjectID: UUID) async throws -> (logged: Bool, event: LookEvent?) {
        struct Body: Encodable { var subjectId: UUID }
        let payload: ViewPayload = try await post(
            path: "/api/v1/views",
            body: Body(subjectId: subjectID),
            authorized: true
        )
        return (payload.logged, payload.event?.model)
    }


    func closeLook(subjectID: UUID?) async throws {
        var path = "/api/v1/looks/close"
        if let subjectID {
            path += "?subjectId=\(subjectID.uuidString)"
        }
        try await postEmpty(path: path, body: EmptyBody())
    }

    func extendLook(subjectID: UUID) async throws -> LookSession {
        let payload: LookSessionDTO = try await post(
            path: "/api/v1/looks/\(subjectID.uuidString)/extend",
            body: EmptyBody(),
            authorized: true
        )
        return payload.model
    }

    /// Resting `off|untilTheyLook|always`, or pause `1h|8h|1d|2d|3d`.
    /// Always without Plus → 402 `pro_required`. Pause is free and stored on the server.
    func setShare(personID: UUID, resting: ShareRestingMode?, pause: PauseDuration?) async throws {
        struct Body: Encodable {
            var resting: String?
            var pause: String?
        }
        try await patchEmpty(
            path: "/api/v1/people/\(personID.uuidString)/share",
            body: Body(resting: resting?.apiValue, pause: pause.map(TrustProductRules.pauseWireValue))
        )
    }

    func history(personID: UUID) async throws -> [LocationPoint] {
        struct Payload: Decodable { var points: [LocationDTO] }
        let payload: Payload = try await get(path: "/api/v1/people/\(personID.uuidString)/history")
        return payload.points.map(\.model)
    }

    func setHomePlace(placeID: UUID, label: String) async throws {
        struct Body: Encodable {
            var placeId: UUID
            var label: String
        }
        try await putEmpty(path: "/api/v1/me/home", body: Body(placeId: placeID, label: label))
    }

    /// Global presence triad — `home|away|hidden`. Hidden is omitted from everyone's circle.
    func postHomePresence(state: HomePresenceKind, signaledAt: Date? = nil) async throws {
        struct Body: Encodable {
            var state: String
            var signaledAt: Date?
        }
        try await postEmpty(
            path: "/api/v1/me/home/presence",
            body: Body(state: state.rawValue, signaledAt: signaledAt)
        )
    }

    func createPromise(trusteeID: UUID, deadlineAt: Date) async throws {
        struct Body: Encodable {
            var trusteeId: UUID
            var deadlineAt: Date
        }
        try await postEmpty(
            path: "/api/v1/promises",
            body: Body(trusteeId: trusteeID, deadlineAt: deadlineAt)
        )
    }

    func createInvite() async throws -> String {
        let payload: InvitePayload = try await post(path: "/api/v1/invites", body: EmptyBody(), authorized: true)
        return payload.code
    }

    func acceptInvite(code: String) async throws {
        struct Body: Encodable { var code: String }
        try await postEmpty(path: "/api/v1/invites/accept", body: Body(code: code))
    }

    func revoke(personID: UUID) async throws {
        try await postEmpty(path: "/api/v1/people/\(personID.uuidString)/revoke", body: EmptyBody())
    }

    func grantCircle(reviewUnlock: Bool, productID: String?, signedTransactionInfo: String?) async throws {
        struct Body: Encodable {
            var productId: String?
            var reviewUnlock: Bool
            var signedTransactionInfo: String?
        }
        try await postEmpty(
            path: "/api/v1/circle/entitlement",
            body: Body(productId: productID, reviewUnlock: reviewUnlock, signedTransactionInfo: signedTransactionInfo)
        )
    }

    func storeKitAccountToken() async throws -> UUID {
        struct Payload: Decodable { var appAccountToken: UUID }
        let payload: Payload = try await get(path: "/api/v1/storekit/account-token")
        return payload.appAccountToken
    }

    func verifyStoreKitTransaction(_ signedTransactionInfo: String) async throws {
        struct Body: Encodable { var signedTransactionInfo: String }
        try await postEmpty(
            path: "/api/v1/storekit/transactions",
            body: Body(signedTransactionInfo: signedTransactionInfo)
        )
    }

    func registerPushDevice(installationId: UUID, token: String, environment: String) async throws {
        struct Body: Encodable {
            var installationId: UUID
            var token: String
            var environment: String
            var bundleId: String
        }
        try await postEmpty(
            path: "/api/v1/push/devices",
            body: Body(
                installationId: installationId,
                token: token,
                environment: environment,
                bundleId: AppConfiguration.bundleIdentifier
            )
        )
    }

    func removePushDevice(installationId: UUID) async throws {
        try await deleteEmpty(path: "/api/v1/push/devices/\(installationId.uuidString)")
    }

    func deleteAccount() async throws {
        try await deleteEmpty(path: "/api/v1/account")
    }

    func rename(_ name: String) async throws {
        struct Body: Encodable { var displayName: String }
        try await patchEmpty(path: "/api/v1/me", body: Body(displayName: name))
    }

    func handleAvailability(_ handle: String) async throws -> HandleAvailabilityPayload {
        let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? handle
        return try await get(path: "/api/v1/handles/available?handle=\(encoded)")
    }

    func setHandle(_ handle: String) async throws {
        struct Body: Encodable { var handle: String }
        try await putEmpty(path: "/api/v1/me/handle", body: Body(handle: handle))
    }

    func sendPhoneCode(phone: String) async throws -> SendPhoneCodePayload {
        struct Body: Encodable { var phone: String }
        return try await post(
            path: "/api/v1/me/phone/send",
            body: Body(phone: phone),
            authorized: true
        )
    }

    func verifyPhoneCode(phone: String, code: String) async throws {
        struct Body: Encodable {
            var phone: String
            var code: String
        }
        try await postEmpty(path: "/api/v1/me/phone/verify", body: Body(phone: phone, code: code))
    }

    func addPersonByPhone(_ phone: String) async throws -> AddPersonByPhonePayload {
        struct Body: Encodable { var phone: String }
        return try await post(
            path: "/api/v1/people/phone",
            body: Body(phone: phone),
            authorized: true
        )
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", authorized: true)
        return try await send(request)
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B, authorized: Bool) async throws -> T {
        var request = try makeRequest(path: path, method: "POST", authorized: authorized)
        if !(body is EmptyBody) {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await send(request)
    }

    private func postEmpty<B: Encodable>(path: String, body: B) async throws {
        var request = try makeRequest(path: path, method: "POST", authorized: true)
        if !(body is EmptyBody) {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let _: EmptyPayload = try await send(request, allowEmpty: true)
    }

    private func patchEmpty<B: Encodable>(path: String, body: B) async throws {
        var request = try makeRequest(path: path, method: "PATCH", authorized: true)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let _: EmptyPayload = try await send(request, allowEmpty: true)
    }

    private func putEmpty<B: Encodable>(path: String, body: B) async throws {
        var request = try makeRequest(path: path, method: "PUT", authorized: true)
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let _: EmptyPayload = try await send(request, allowEmpty: true)
    }

    private func deleteEmpty(path: String) async throws {
        let request = try makeRequest(path: path, method: "DELETE", authorized: true)
        let _: EmptyPayload = try await send(request, allowEmpty: true)
    }

    private func makeRequest(path: String, method: String, authorized: Bool) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: resolvedBaseURL)?.absoluteURL else {
            throw TrustClientError.unreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = AppConfiguration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            guard let token, !token.isEmpty else { throw TrustClientError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, allowEmpty: Bool = false) async throws -> T {
        let data = try await sendRaw(request)
        if allowEmpty && (data.isEmpty || T.self == EmptyPayload.self) {
            if let empty = EmptyPayload() as? T { return empty }
        }
        if data.isEmpty, let empty = EmptyPayload() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw TrustClientError.decoding
        }
    }

    /// Performs the request and maps transport + HTTP failures to `TrustClientError`.
    /// Returns the 2xx body untouched so callers can cache or decode it.
    private func sendRaw(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            let session = self.session
            (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask {
                    try await session.data(for: request)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(AppConfiguration.requestTimeout + 2))
                    throw TrustClientError.timeout
                }
                guard let result = try await group.next() else { throw TrustClientError.timeout }
                group.cancelAll()
                return result
            }
        } catch let error as TrustClientError {
            throw error
        } catch let error as URLError where error.code == .timedOut {
            throw TrustClientError.timeout
        } catch is CancellationError {
            throw TrustClientError.timeout
        } catch {
            throw TrustClientError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw TrustClientError.unreachable }
        if [502, 503, 504].contains(http.statusCode) {
            throw TrustClientError.serverUnavailable(http.statusCode)
        }
        if http.statusCode == 401 {
            if let error = try? decoder.decode(APIErrorPayload.self, from: data),
               let code = error.code, code != "unauthorized" {
                throw TrustClientError.api(code: code, message: TrustCopy.apiError(code: code, fallback: error.message))
            }
            throw TrustClientError.unauthorized
        }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        if let error = try? decoder.decode(APIErrorPayload.self, from: data) {
            let message = TrustCopy.apiError(code: error.code, fallback: error.message)
            if let code = error.code, !code.isEmpty {
                throw TrustClientError.api(code: code, message: message)
            }
            throw TrustClientError.server(message)
        }
        throw TrustClientError.server(TrustCopy.requestFailedStatus(http.statusCode))
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = TrustJSON.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: raw))
        }
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(TrustJSON.string(from: date))
        }
        return encoder
    }
}

private struct EmptyPayload: Decodable {}
private struct EmptyBody: Encodable {}

private enum TrustJSON {
    static func date(from raw: String) -> Date? {
        if let date = iso.date(from: raw) { return date }
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return isoFractional.date(from: raw)
    }

    static func string(from date: Date) -> String {
        iso.string(from: date)
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFractional = ISO8601DateFormatter()
}

extension CirclePayload {
    var snapshot: CircleSnapshot {
        CircleSnapshot(
            you: you.model,
            members: members.map(\.model),
            coverage: CircleCoverage(
                isCovered: coverage.isCovered,
                sponsorName: coverage.sponsorName,
                actingIsSponsor: coverage.actingIsSponsor,
                serverSeatLimit: coverage.seatLimit,
                serverLookLogDays: coverage.lookLogDays
            ),
            pendingInviteCode: pendingInviteCode,
            lookLog: lookLog.map(\.model),
            retainedLookLogCount: retainedLookLogCount,
            allowsDevelopmentSignIn: allowsDevelopmentSignIn,
            allowsReviewUnlock: allowsReviewUnlock ?? false,
            yourHomePlaceID: yourHome?.place?.placeId,
            yourHomeLabel: yourHome?.place?.label,
            yourHomeState: yourHome?.state.flatMap(HomePresenceKind.init(rawValue:))
        )
    }
}

extension PersonDTO {
    var model: Person {
        Person(
            id: id,
            displayName: displayName,
            hasPro: hasCircle,
            onboardingComplete: onboardingComplete ?? (handle != nil),
            phoneVerified: phoneVerified ?? false,
            handle: handle
        )
    }
}

extension PresenceDTO {
    var model: PresenceSnapshot {
        PresenceSnapshot(
            lastActiveAt: lastActiveAt,
            batteryPercent: batteryPercent,
            isCharging: isCharging,
            gotHomeAt: gotHomeAt,
            checkedInAt: checkedInAt
        )
    }
}

extension LocationDTO {
    var model: LocationPoint {
        LocationPoint(timestamp: timestamp, latitude: latitude, longitude: longitude)
    }
}

extension ShareDTO {
    var model: PersonShareState {
        let mode: ShareRestingMode
        switch resting.lowercased() {
        case "always": mode = .always
        case "off": mode = .off
        case "paused": mode = .paused
        default: mode = .untilTheyLook
        }
        let restores: ShareRestingMode?
        switch (revertsTo ?? "").lowercased() {
        case "always": restores = .always
        case "untiltheylook", "sealed": restores = .untilTheyLook
        default: restores = nil
        }
        return PersonShareState(resting: mode, pauseUntil: pauseUntil, restoresTo: restores)
    }

    var presentationModel: SharePresentation {
        switch presentation.lowercased() {
        case "off":
            return .off
        case "always":
            return .always
        case "paused":
            let revert: ShareRestingMode
            switch (revertsTo ?? "").lowercased() {
            case "always": revert = .always
            default: revert = .untilTheyLook
            }
            if let ends = pauseUntil {
                return .paused(ends: ends, revertsTo: revert)
            }
            return .untilTheyLook
        default:
            return .untilTheyLook
        }
    }
}

extension MemberDTO {
    var model: TrustedPerson {
        TrustedPerson(
            person: person.model,
            presence: presence?.model ?? .sealed,
            share: share.model,
            inboundLive: inboundLive,
            livePoint: inboundLive ? live?.model : nil,
            outboundPresenceGranted: outboundPresenceGranted ?? false,
            inboundPresenceGranted: inboundPresenceGranted ?? false,
            homePresence: homePresence?.model,
            promise: promise?.model,
            inboundPresentation: inboundShare?.presentationModel,
            locationHistory: locationHistory
        )
    }

    /// Newest first. Uses `trail` when the server sends one, otherwise the single live fix.
    var locationHistory: [LocationVisit] {
        var points = trail?.map(\.model) ?? []
        if inboundLive, let live = live?.model, !points.contains(where: { $0.timestamp == live.timestamp && $0.latitude == live.latitude }) {
            points.append(live)
        }
        return points
            .sorted { $0.timestamp > $1.timestamp }
            .map { LocationVisit(label: TrustCopy.location, at: $0.timestamp, point: $0) }
    }
}

extension HomePresenceDTO {
    var model: HomePresenceSnapshot? {
        guard let kind = HomePresenceKind(rawValue: state) else { return nil }
        return HomePresenceSnapshot(state: kind, changedAt: changedAt, placeLabel: placeLabel)
    }
}

extension PromiseDTO {
    var model: PromiseSnapshot {
        PromiseSnapshot(
            id: id,
            subjectID: subjectId,
            trusteeID: trusteeId,
            placeLabel: placeLabel,
            deadlineAt: deadlineAt,
            status: PromiseKind(rawValue: status) ?? .active,
            resolvedAt: resolvedAt,
            youAreSubject: youAreSubject
        )
    }
}

extension LookEventDTO {
    var model: LookEvent {
        LookEvent(
            id: id,
            viewerID: viewerId,
            viewerName: viewerName,
            subjectID: subjectId,
            subjectName: subjectName,
            at: at,
            historyWindowHours: historyWindowHours,
            includedLive: includedLive,
            kind: kind.flatMap(LookKind.init(rawValue:)) ?? .look
        )
    }
}

extension LookSessionDTO {
    var model: LookSession {
        LookSession(id: event.id, event: event.model, live: live.model, trail: trail.map(\.model))
    }
}
