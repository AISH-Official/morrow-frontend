import Foundation
import Combine
import WatchConnectivity

struct IncomingWatchCheckIn: Codable {
    let status: String
    let cause: String?
    let recordedAt: Date
}

struct IncomingWatchHealthSummary: Codable {
    let heartRate: Double
    let hrv: Double
    let steps: Double
    let activeEnergyKcal: Double
    let exerciseMinutes: Double
    let recordedAt: Date
}

final class WatchSessionReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var inboxVersion = 0
    @Published private(set) var healthInboxVersion = 0
    private let inboxKey = "morrow.watch.inbox"
    private let healthInboxKey = "morrow.watch.health.inbox"
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

    func drainHealthSummaries() -> [IncomingWatchHealthSummary] {
        guard let data = UserDefaults.standard.data(forKey: healthInboxKey),
              let values = try? JSONDecoder().decode([IncomingWatchHealthSummary].self, from: data) else { return [] }
        UserDefaults.standard.removeObject(forKey: healthInboxKey)
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
            "energy": snapshot.activeEnergyText,
            "exercise": snapshot.exerciseText,
            "respiratory": snapshot.respiratoryText,
            "recommendation": recommendation,
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        pendingContext = context
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["kind"] as? String == "healthSummary" {
            let date = (userInfo["recordedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? .now
            let summary = IncomingWatchHealthSummary(
                heartRate: userInfo["heartRate"] as? Double ?? 0,
                hrv: userInfo["hrv"] as? Double ?? 0,
                steps: userInfo["steps"] as? Double ?? 0,
                activeEnergyKcal: userInfo["activeEnergyKcal"] as? Double ?? 0,
                exerciseMinutes: userInfo["exerciseMinutes"] as? Double ?? 0,
                recordedAt: date
            )
            var inbox = (UserDefaults.standard.data(forKey: healthInboxKey)).flatMap { try? JSONDecoder().decode([IncomingWatchHealthSummary].self, from: $0) } ?? []
            inbox.append(summary)
            if let data = try? JSONEncoder().encode(inbox) { UserDefaults.standard.set(data, forKey: healthInboxKey) }
            DispatchQueue.main.async { self.healthInboxVersion += 1 }
            return
        }
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
