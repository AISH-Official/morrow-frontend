import Foundation
import Security
import WatchKit
import UserNotifications

struct WatchServerConnection: Codable {
    let apiRoot: String
    let userId: String
    let accessToken: String
}

final class MorrowWatchExtensionDelegate: NSObject, WKExtensionDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        let recovery = UNNotificationAction(identifier: "START_RECOVERY", title: "지금 시작", options: [.foreground])
        let checkIn = UNNotificationAction(identifier: "OPEN_CHECKIN", title: "지금 기록", options: [.foreground])
        let recoveryCategory = UNNotificationCategory(identifier: "MORROW_ACTION", actions: [recovery], intentIdentifiers: [])
        let checkInCategory = UNNotificationCategory(identifier: "MORROW_CHECKIN", actions: [checkIn], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([recoveryCategory, checkInCategory])
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await WatchPushRegistrar.shared.updateDeviceToken(token) }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "morrow.watch.push.registrationError")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == "START_RECOVERY" || response.actionIdentifier == "START_BREATHING" || (response.actionIdentifier == UNNotificationDefaultActionIdentifier && info["type"] as? String == "RECOVERY") {
            UserDefaults.standard.set("RECOVERY", forKey: "morrow.watch.pendingAction")
            UserDefaults.standard.set(info["action"] as? String ?? "BREATH", forKey: "morrow.watch.recovery.action")
            UserDefaults.standard.set(info["attemptId"] as? String, forKey: "morrow.watch.recovery.attemptId")
            UserDefaults.standard.set((info["durationSeconds"] as? NSNumber)?.intValue ?? 60, forKey: "morrow.watch.recovery.duration")
            UserDefaults.standard.set(info["reason"] as? String ?? response.notification.request.content.body, forKey: "morrow.watch.recovery.reason")
            UserDefaults.standard.set(info["confidence"] as? String ?? "LOW", forKey: "morrow.watch.recovery.confidence")
        } else if response.actionIdentifier == "OPEN_CHECKIN" || (response.actionIdentifier == UNNotificationDefaultActionIdentifier && info["type"] as? String == "CHECKIN") {
            UserDefaults.standard.set("CHECKIN", forKey: "morrow.watch.pendingAction")
        }
        await MainActor.run { NotificationCenter.default.post(name: Notification.Name("morrow.watch.action"), object: nil) }
    }
}

actor WatchPushRegistrar {
    static let shared = WatchPushRegistrar()
    private var connection = WatchConnectionStore.load()
    private var token = UserDefaults.standard.string(forKey: "morrow.watch.push.token")

    func updateConnection(_ value: WatchServerConnection) async {
        connection = value
        WatchConnectionStore.save(value)
        await registerIfReady()
    }

    func clearConnection() async {
        if let connection, let token, let root = URL(string: connection.apiRoot),
           var components = URLComponents(url: root.appending(path: "notifications/devices"), resolvingAgainstBaseURL: false) {
            components.queryItems = [URLQueryItem(name: "userId", value: connection.userId), URLQueryItem(name: "deviceToken", value: token)]
            if let url = components.url {
                var request = URLRequest(url: url); request.httpMethod = "DELETE"
                request.setValue("Bearer \(connection.accessToken)", forHTTPHeaderField: "Authorization")
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        connection = nil
        WatchConnectionStore.clear()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func updateDeviceToken(_ value: String) async {
        token = value
        UserDefaults.standard.set(value, forKey: "morrow.watch.push.token")
        await registerIfReady()
    }

    private func registerIfReady() async {
        guard let connection, let token, let root = URL(string: connection.apiRoot) else { return }
        let payload = PushDeviceRequest(
            userId: connection.userId,
            deviceToken: token,
            platform: "WATCHOS",
            environment: pushEnvironment
        )
        do {
            var request = URLRequest(url: root.appending(path: "notifications/devices"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(connection.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            UserDefaults.standard.set(Date(), forKey: "morrow.watch.push.registeredAt")
            UserDefaults.standard.removeObject(forKey: "morrow.watch.push.registrationError")
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: "morrow.watch.push.registrationError")
        }
    }

    private var pushEnvironment: String {
        #if DEBUG
        return "SANDBOX"
        #else
        return "PRODUCTION"
        #endif
    }

    private struct PushDeviceRequest: Encodable {
        let userId: String
        let deviceToken: String
        let platform: String
        let environment: String
    }
}

struct WatchAssistantReply: Decodable {
    let content: String
    let aiMode: String

    var naturalContent: String {
        content.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

actor WatchAssistantClient {
    static let shared = WatchAssistantClient()

    func send(_ content: String) async throws -> WatchAssistantReply {
        guard let connection = WatchConnectionStore.load(), let root = URL(string: connection.apiRoot) else {
            throw URLError(.notConnectedToInternet)
        }
        let payload = AssistantRequest(userId: connection.userId, content: content)
        var request = URLRequest(url: root.appending(path: "assistant/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(connection.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(WatchAssistantReply.self, from: data)
    }

    private struct AssistantRequest: Encodable {
        let userId: String
        let content: String
    }
}

struct WatchRecoveryAttempt: Decodable {
    let id: UUID
    let action: String
    let status: String
    let outcome: String?
}

actor WatchRecoveryClient {
    static let shared = WatchRecoveryClient()

    func create(action: String, reason: String, confidence: String) async throws -> WatchRecoveryAttempt {
        try await request(path: "recovery-attempts", method: "POST", payload: CreateRequest(action: action, triggerType: "WATCH_STARTED", reason: reason, confidence: confidence, source: "WATCH"))
    }

    func start(id: UUID) async throws -> WatchRecoveryAttempt {
        try await request(path: "recovery-attempts/\(id.uuidString)/start", method: "PATCH", payload: EmptyRequest())
    }

    func complete(id: UUID, outcome: String) async throws -> WatchRecoveryAttempt {
        try await request(path: "recovery-attempts/\(id.uuidString)/complete", method: "PATCH", payload: CompleteRequest(outcome: outcome))
    }

    private func request<Payload: Encodable>(path: String, method: String, payload: Payload) async throws -> WatchRecoveryAttempt {
        guard let connection = WatchConnectionStore.load(), let root = URL(string: connection.apiRoot) else { throw URLError(.notConnectedToInternet) }
        var request = URLRequest(url: root.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(connection.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(WatchRecoveryAttempt.self, from: data)
    }

    private struct CreateRequest: Encodable { let action, triggerType, reason, confidence, source: String }
    private struct CompleteRequest: Encodable { let outcome: String }
    private struct EmptyRequest: Encodable {}
}

enum WatchConnectionStore {
    private static let service = "com.qlsl1198.morrowwellness.watch.auth"
    private static let account = "phone-connection"
    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func load() -> WatchServerConnection? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WatchServerConnection.self, from: data)
    }

    static func save(_ value: WatchServerConnection) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
