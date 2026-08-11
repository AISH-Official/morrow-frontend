import UIKit
import UserNotifications

final class MorrowAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let breathe = UNNotificationAction(identifier: "START_BREATHING", title: "1분 호흡 시작", options: [.foreground])
        let checkIn = UNNotificationAction(identifier: "OPEN_CHECKIN", title: "지금 기록", options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "MORROW_ACTION", actions: [breathe, checkIn], intentIdentifiers: [])
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
        if response.actionIdentifier == "START_BREATHING" { UserDefaults.standard.set("BREATH", forKey: "morrow.phone.pendingAction") }
        else if response.actionIdentifier == "OPEN_CHECKIN" { UserDefaults.standard.set("CHECKIN", forKey: "morrow.phone.pendingAction") }
    }
}
