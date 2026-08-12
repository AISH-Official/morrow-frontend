import UIKit
import UserNotifications

final class MorrowAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let recovery = UNNotificationAction(identifier: "START_RECOVERY", title: "지금 시작", options: [.foreground])
        let checkIn = UNNotificationAction(identifier: "OPEN_CHECKIN", title: "지금 기록", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "MORROW_ACTION", actions: [recovery], intentIdentifiers: []),
            UNNotificationCategory(identifier: "MORROW_CHECKIN", actions: [checkIn], intentIdentifiers: [])
        ])
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: "morrow.push.token")
        Task { try? await MorrowAPIClient.shared.registerPushToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set(error.localizedDescription, forKey: "morrow.push.registrationError")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == "START_RECOVERY" || response.actionIdentifier == "START_BREATHING" || (response.actionIdentifier == UNNotificationDefaultActionIdentifier && info["type"] as? String == "RECOVERY") {
            UserDefaults.standard.set("RECOVERY", forKey: "morrow.phone.pendingAction")
            UserDefaults.standard.set(info["action"] as? String ?? "BREATH", forKey: "morrow.phone.recovery.action")
            UserDefaults.standard.set(info["attemptId"] as? String, forKey: "morrow.phone.recovery.attemptId")
            UserDefaults.standard.set((info["durationSeconds"] as? NSNumber)?.intValue ?? 60, forKey: "morrow.phone.recovery.duration")
            UserDefaults.standard.set(info["reason"] as? String ?? response.notification.request.content.body, forKey: "morrow.phone.recovery.reason")
            UserDefaults.standard.set(info["confidence"] as? String ?? "LOW", forKey: "morrow.phone.recovery.confidence")
        } else if response.actionIdentifier == "OPEN_CHECKIN" || (response.actionIdentifier == UNNotificationDefaultActionIdentifier && info["type"] as? String == "CHECKIN") {
            UserDefaults.standard.set("CHECKIN", forKey: "morrow.phone.pendingAction")
        }
        await MainActor.run { NotificationCenter.default.post(name: Notification.Name("morrow.phone.action"), object: nil) }
    }
}
