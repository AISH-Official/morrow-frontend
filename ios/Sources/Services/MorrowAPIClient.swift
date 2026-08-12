import Foundation
import Security
import UIKit

struct MorrowCredentials: Codable, Equatable {
    let userId: String
    let accessToken: String
    let pairingCode: String
}

struct NativeAssistantReply: Decodable {
    let content: String
    let aiMode: String
    let personalized: Bool

    var naturalContent: String {
        content.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NativeDashboardSummary: Decodable {
    let score: Int
    let wellnessLoad: String
    let hasHealthData: Bool
    let scoreConfidence: String
    let scoreReasons: [String]
    let lastUpdatedAt: String?
    let recommendation: NativeRecommendation?
}

struct NativeRecommendation: Decodable {
    let id: String
    let title: String
    let rationale: String
    let action: String?
    let durationSeconds: Int?
    let source: String?
    let personalized: Bool?
}

struct NativeServerCheckIn: Decodable {
    let id: UUID
    let clientEventId: String?
    let status: String
    let cause: String?
    let note: String
    let source: String
    let recordedAt: String

    var date: Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: recordedAt) ?? ISO8601DateFormatter().date(from: recordedAt) ?? .now
    }
}

struct AIProactiveInsight: Decodable {
    let shouldNotify: Bool
    let title: String
    let body: String
    let aiMode: String
    let reason: String
}

struct NativeRecoveryAttempt: Decodable, Identifiable {
    let id: UUID
    let action: String
    let triggerType: String
    let reason: String
    let confidence: String
    let source: String
    let status: String
    let outcome: String?
}

struct NativeWeeklyReport: Decodable {
    let totalCheckIns: Int
    let improvementRate: Double
    let changeFromPrevious: Double
    let suggestedRecoveryCount: Int
    let completedRecoveryCount: Int
    let recoveryHelpfulRate: Double
    let topHelpfulAction: String?
    let recoveryInsight: String
}

private struct AIHealthConsentResponse: Decodable { let consent: Bool }

enum MorrowRuntimeConfiguration {
    static let overrideKey = "morrow.api.baseURL.override"

    static var apiRootString: String {
        if let override = UserDefaults.standard.string(forKey: overrideKey), !override.isEmpty { return override }
        let configured = Bundle.main.object(forInfoDictionaryKey: "MORROW_API_BASE_URL") as? String
        return configured?.isEmpty == false ? configured! : "http://localhost:8080/api/v1"
    }

    static var apiRoot: URL? { URL(string: apiRootString.trimmingCharacters(in: .whitespacesAndNewlines)) }

    static func setAPIOverride(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty { UserDefaults.standard.removeObject(forKey: overrideKey) }
        else { UserDefaults.standard.set(normalized, forKey: overrideKey) }
    }
}

actor MorrowAPIClient {
    static let shared = MorrowAPIClient()
    private let encoder: JSONEncoder = { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }()
    private let decoder = JSONDecoder()
    private var cachedCredentials: MorrowCredentials?

    func hasStoredCredentials() -> Bool {
        cachedCredentials != nil || DeviceCredentialStore.load() != nil
    }

    func login(accountId: String, password: String) async throws -> MorrowCredentials {
        try await authenticate(accountId: accountId, password: password, path: "auth/account-login")
    }

    func signup(accountId: String, password: String) async throws -> MorrowCredentials {
        try await authenticate(accountId: accountId, password: password, path: "auth/signup")
    }

    private func authenticate(accountId: String, password: String, path: String) async throws -> MorrowCredentials {
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? persistentInstallationId()
        let payload = PasswordAccountRequest(
            accountId: accountId,
            password: password,
            deviceId: "ios-\(deviceId)",
            deviceName: UIDevice.current.name,
            platform: "IOS"
        )
        var request = URLRequest(url: root.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let value = try decoder.decode(MorrowCredentials.self, from: data)
        cachedCredentials = value
        DeviceCredentialStore.save(value)
        return value
    }

    func logout() async {
        let credentials = cachedCredentials ?? DeviceCredentialStore.load()
        guard let credentials, let root = MorrowRuntimeConfiguration.apiRoot else { cachedCredentials = nil; DeviceCredentialStore.clear(); return }
        if let token = UserDefaults.standard.string(forKey: "morrow.push.token"),
           var components = URLComponents(url: root.appending(path: "notifications/devices"), resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "userId", value: credentials.userId), URLQueryItem(name: "deviceToken", value: token)]
            if let url = components.url {
                var unregister = URLRequest(url: url); unregister.httpMethod = "DELETE"; unregister.timeoutInterval = 5
                unregister.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
                _ = try? await URLSession.shared.data(for: unregister)
            }
        }
        var request = URLRequest(url: root.appending(path: "auth/logout"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        cachedCredentials = nil
        DeviceCredentialStore.clear()
    }

    func credentials() async throws -> MorrowCredentials {
        if let cachedCredentials { return cachedCredentials }
        if let stored = DeviceCredentialStore.load() { cachedCredentials = stored; return stored }
        throw MorrowAuthenticationError.loginRequired
    }

    func send<T: Encodable>(_ value: T, path: String, method: String = "POST") async throws {
        let body = try encoder.encode(value)
        try await performSend(body: body, path: path, method: method, canRefresh: true)
    }

    func registerPushToken(_ token: String) async throws {
        let credentials = try await credentials()
        try await send(PushDeviceRequest(userId: credentials.userId, deviceToken: token, platform: "IOS", environment: pushEnvironment), path: "notifications/devices")
    }

    func sendAssistantMessage(_ content: String) async throws -> NativeAssistantReply {
        let credentials = try await credentials()
        return try await sendAndDecode(
            AssistantMessageRequest(userId: credentials.userId, content: content),
            path: "assistant/messages"
        )
    }

    func proactiveInsight() async throws -> AIProactiveInsight {
        let credentials = try await credentials()
        return try await sendAndDecode(
            ProactiveInsightRequest(userId: credentials.userId),
            path: "assistant/proactive-insight"
        )
    }

    func createRecoveryAttempt(action: String, triggerType: String, reason: String, confidence: String, source: String = "IPHONE") async throws -> NativeRecoveryAttempt {
        try await sendAndDecode(RecoveryCreateRequest(action: action, triggerType: triggerType, reason: reason, confidence: confidence, source: source), path: "recovery-attempts")
    }

    func startRecoveryAttempt(_ id: UUID) async throws -> NativeRecoveryAttempt {
        try await sendAndDecode(EmptyPayload(), path: "recovery-attempts/\(id.uuidString)/start", method: "PATCH")
    }

    func completeRecoveryAttempt(_ id: UUID, outcome: String) async throws -> NativeRecoveryAttempt {
        try await sendAndDecode(RecoveryCompleteRequest(outcome: outcome), path: "recovery-attempts/\(id.uuidString)/complete", method: "PATCH")
    }

    func weeklyReport() async throws -> NativeWeeklyReport { try await getAndDecode(path: "reports/weekly") }

    func addPersonalMemory(type: String, summary: String) async throws {
        let credentials = try await credentials()
        try await send(
            PersonalMemoryRequest(userId: credentials.userId, type: type, summary: summary),
            path: "personalization/memories"
        )
    }

    func dashboard(canRefresh: Bool = true) async throws -> NativeDashboardSummary {
        let credentials = try await credentials()
        guard let root = MorrowRuntimeConfiguration.apiRoot,
              var components = URLComponents(url: root.appending(path: "dashboard"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "userId", value: credentials.userId)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if canRefresh, let http = response as? HTTPURLResponse, http.statusCode == 401 {
            cachedCredentials = nil
            DeviceCredentialStore.clear()
            return try await dashboard(canRefresh: false)
        }
        try validate(response)
        return try decoder.decode(NativeDashboardSummary.self, from: data)
    }

    func checkIns() async throws -> [NativeServerCheckIn] {
        try await getAndDecode(path: "check-ins")
    }

    func createCheckIn<T: Encodable>(_ value: T) async throws -> NativeServerCheckIn {
        try await sendAndDecode(value, path: "check-ins")
    }

    func deleteCheckIn(_ id: UUID) async throws {
        try await send(EmptyPayload(), path: "check-ins/\(id.uuidString)", method: "DELETE")
    }

    func clearWellnessData() async throws {
        try await send(EmptyPayload(), path: "users/me/data", method: "DELETE")
    }

    func aiHealthConsent() async throws -> Bool {
        let value: AIHealthConsentResponse = try await getAndDecode(path: "privacy/ai-health-consent")
        return value.consent
    }

    func updateAIHealthConsent(_ consent: Bool) async throws -> Bool {
        let credentials = try await credentials()
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        var request = URLRequest(url: root.appending(path: "privacy/ai-health-consent"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(AIHealthConsentRequest(consent: consent))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try decoder.decode(AIHealthConsentResponse.self, from: data).consent
    }

    func connectionContext() async throws -> (apiRoot: String, credentials: MorrowCredentials) {
        (MorrowRuntimeConfiguration.apiRootString, try await credentials())
    }

    func resetForServerChange() {
        cachedCredentials = nil
        DeviceCredentialStore.clear()
    }

    func pair(using pairingCode: String) async throws -> MorrowCredentials {
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        let current = try await credentials()
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? persistentInstallationId()
        let payload = PairDeviceRequest(
            pairingCode: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceId: "ios-\(deviceId)",
            deviceName: UIDevice.current.name,
            platform: "IOS"
        )
        var request = URLRequest(url: root.appending(path: "auth/pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let value = try decoder.decode(MorrowCredentials.self, from: data)
        cachedCredentials = value
        DeviceCredentialStore.save(value)
        return value
    }

    func refreshPairingCode() async throws -> MorrowCredentials {
        let current = try await credentials()
        guard let root = MorrowRuntimeConfiguration.apiRoot,
              var components = URLComponents(url: root.appending(path: "auth/pairing-code"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "deviceId", value: currentDeviceId)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let value = try decoder.decode(MorrowCredentials.self, from: data)
        cachedCredentials = value
        DeviceCredentialStore.save(value)
        return value
    }

    private var currentDeviceId: String {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? persistentInstallationId()
        return "ios-\(deviceId)"
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "SANDBOX"
        #else
        return "PRODUCTION"
        #endif
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }

    private func performSend(body: Data, path: String, method: String, canRefresh: Bool) async throws {
        let credentials = try await credentials()
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        var request = URLRequest(url: root.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (_, response) = try await URLSession.shared.data(for: request)
        if canRefresh, let http = response as? HTTPURLResponse, http.statusCode == 401 {
            cachedCredentials = nil
            DeviceCredentialStore.clear()
            try await performSend(body: body, path: path, method: method, canRefresh: false)
            return
        }
        try validate(response)
    }

    private func sendAndDecode<Body: Encodable, Response: Decodable>(
        _ value: Body,
        path: String,
        method: String = "POST",
        canRefresh: Bool = true
    ) async throws -> Response {
        let credentials = try await credentials()
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        var request = URLRequest(url: root.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(value)
        let (data, response) = try await URLSession.shared.data(for: request)
        if canRefresh, let http = response as? HTTPURLResponse, http.statusCode == 401 {
            cachedCredentials = nil
            DeviceCredentialStore.clear()
            return try await sendAndDecode(value, path: path, method: method, canRefresh: false)
        }
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func getAndDecode<Response: Decodable>(path: String, canRefresh: Bool = true) async throws -> Response {
        let credentials = try await credentials()
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        var request = URLRequest(url: root.appending(path: path))
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if canRefresh, let http = response as? HTTPURLResponse, http.statusCode == 401 {
            cachedCredentials = nil
            DeviceCredentialStore.clear()
            return try await getAndDecode(path: path, canRefresh: false)
        }
        try validate(response)
        return try decoder.decode(Response.self, from: data)
    }

    private func persistentInstallationId() -> String {
        let key = "morrow.installation.id"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString; UserDefaults.standard.set(value, forKey: key); return value
    }

    private struct PairDeviceRequest: Encodable { let pairingCode, deviceId, deviceName, platform: String }
    private struct PushDeviceRequest: Encodable { let userId, deviceToken, platform, environment: String }
    private struct AssistantMessageRequest: Encodable { let userId, content: String }
    private struct ProactiveInsightRequest: Encodable { let userId: String }
    private struct PasswordAccountRequest: Encodable { let accountId, password, deviceId, deviceName, platform: String }
    private struct EmptyPayload: Encodable {}
    private struct AIHealthConsentRequest: Encodable { let consent: Bool }
    private struct RecoveryCreateRequest: Encodable { let action, triggerType, reason, confidence, source: String }
    private struct RecoveryCompleteRequest: Encodable { let outcome: String }
    private struct PersonalMemoryRequest: Encodable { let userId, type, summary: String }
}

enum MorrowAuthenticationError: Error { case loginRequired }

private enum DeviceCredentialStore {
    private static let service = "com.qlsl1198.morrowwellness.auth"
    private static let account = "device-session"

    static func load() -> MorrowCredentials? {
        var query = baseQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return try? JSONDecoder().decode(MorrowCredentials.self, from: data)
    }

    static func save(_ value: MorrowCredentials) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery; query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() { SecItemDelete(baseQuery as CFDictionary) }
    private static var baseQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
}
