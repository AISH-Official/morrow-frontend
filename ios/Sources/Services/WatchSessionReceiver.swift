import Foundation
import Combine
import WatchConnectivity

struct IncomingWatchCheckIn: Codable {
    let status: String
    let cause: String?
    let recordedAt: Date
}

final class WatchSessionReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var inboxVersion = 0
    private let inboxKey = "morrow.watch.inbox"
    private var pendingContext: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func drain() -> [IncomingWatchCheckIn] {
        guard let data = UserDefaults.standard.data(forKey: inboxKey),
              let values = try? JSONDecoder().decode([IncomingWatchCheckIn].self, from: data) else { return [] }
        UserDefaults.standard.removeObject(forKey: inboxKey)
        return values
    }

    func sendWellnessContext(load: Int, summary: String, snapshot: HealthSnapshot, recommendation: String) {
        let context: [String: Any] = [
            "load": load,
            "summary": summary,
            "sleep": snapshot.sleepText,
            "hrv": snapshot.hrvText,
            "heart": snapshot.restingHeartRateText,
            "steps": snapshot.stepsText,
            "recommendation": recommendation,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        pendingContext = context
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let status = userInfo["status"] as? String else { return }
        let cause = userInfo["cause"] as? String
        let date = (userInfo["recordedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? .now
        var inbox = (UserDefaults.standard.data(forKey: inboxKey)).flatMap { try? JSONDecoder().decode([IncomingWatchCheckIn].self, from: $0) } ?? []
        inbox.append(IncomingWatchCheckIn(status: status, cause: cause, recordedAt: date))
        if let data = try? JSONEncoder().encode(inbox) { UserDefaults.standard.set(data, forKey: inboxKey) }
        DispatchQueue.main.async { self.inboxVersion += 1 }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated, let pendingContext else { return }
        try? session.updateApplicationContext(pendingContext)
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
