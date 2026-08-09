import Foundation
import Security
import UIKit

struct MorrowCredentials: Codable, Equatable {
    let userId: String
    let accessToken: String
    let pairingCode: String
}

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

    func credentials() async throws -> MorrowCredentials {
        if let cachedCredentials { return cachedCredentials }
        if let stored = DeviceCredentialStore.load() { cachedCredentials = stored; return stored }
        guard let root = MorrowRuntimeConfiguration.apiRoot else { throw URLError(.badURL) }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? persistentInstallationId()
        let configuredUser = Bundle.main.object(forInfoDictionaryKey: "MORROW_USER_ID") as? String
        let payload = RegisterDeviceRequest(deviceId: "ios-\(deviceId)", deviceName: UIDevice.current.name, platform: "IOS", userId: configuredUser)
        var request = URLRequest(url: root.appending(path: "auth/device"))
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try encoder.encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let value = try decoder.decode(MorrowCredentials.self, from: data)
        cachedCredentials = value; DeviceCredentialStore.save(value); return value
    }

    func send<T: Encodable>(_ value: T, path: String, method: String = "POST") async throws {
        let body = try encoder.encode(value)
        try await performSend(body: body, path: path, method: method, canRefresh: true)
    }

    func registerPushToken(_ token: String) async throws {
        let credentials = try await credentials()
        try await send(PushDeviceRequest(userId: credentials.userId, deviceToken: token, platform: "IOS", environment: pushEnvironment), path: "notifications/devices")
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
        request.httpBody = try encoder.encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        let value = try decoder.decode(MorrowCredentials.self, from: data)
        cachedCredentials = value
        DeviceCredentialStore.save(value)
        return value
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

    private func persistentInstallationId() -> String {
        let key = "morrow.installation.id"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString; UserDefaults.standard.set(value, forKey: key); return value
    }

    private struct RegisterDeviceRequest: Encodable { let deviceId, deviceName, platform: String; let userId: String? }
    private struct PairDeviceRequest: Encodable { let pairingCode, deviceId, deviceName, platform: String }
    private struct PushDeviceRequest: Encodable { let userId, deviceToken, platform, environment: String }
}

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
