import Foundation
import Combine
import WatchConnectivity

struct WatchWellnessContext {
    var load = 78
    var summary = "리듬 회복이 필요해요"
    var sleep = "6시간 45분"
    var hrv = "38 ms"
    var heart = "72 bpm"
    var steps = "4,286"
    var recommendation = "7분 동안 가볍게 걸어보세요"
    var updatedAt = Date()
}

struct WatchRecentCheckIn {
    let status: String
    let cause: String
    let recordedAt: Date
}

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var context = WatchWellnessContext()
    @Published private(set) var recentCheckIn: WatchRecentCheckIn?
    @Published private(set) var isConnected = false

    override init() {
        super.init()
        restoreRecentCheckIn()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isConnected = WCSession.default.activationState == .activated
            }
        }
    }

    func send(status: String, cause: String) {
        let now = Date()
        recentCheckIn = WatchRecentCheckIn(status: status, cause: cause, recordedAt: now)
        UserDefaults.standard.set(status, forKey: "morrow.last.status")
        UserDefaults.standard.set(cause, forKey: "morrow.last.cause")
        UserDefaults.standard.set(now, forKey: "morrow.last.date")
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "status": status,
            "cause": cause,
            "recordedAt": ISO8601DateFormatter().string(from: now)
        ])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = activationState == .activated
            if !session.receivedApplicationContext.isEmpty { self.apply(session.receivedApplicationContext) }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isConnected = session.activationState == .activated }
    }

    private func apply(_ values: [String: Any]) {
        DispatchQueue.main.async {
            self.context = WatchWellnessContext(
                load: values["load"] as? Int ?? self.context.load,
                summary: values["summary"] as? String ?? self.context.summary,
                sleep: values["sleep"] as? String ?? self.context.sleep,
                hrv: values["hrv"] as? String ?? self.context.hrv,
                heart: values["heart"] as? String ?? self.context.heart,
                steps: values["steps"] as? String ?? self.context.steps,
                recommendation: values["recommendation"] as? String ?? self.context.recommendation,
                updatedAt: (values["updatedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? .now
            )
        }
    }

    private func restoreRecentCheckIn() {
        guard let status = UserDefaults.standard.string(forKey: "morrow.last.status"),
              let cause = UserDefaults.standard.string(forKey: "morrow.last.cause") else { return }
        recentCheckIn = WatchRecentCheckIn(status: status, cause: cause, recordedAt: UserDefaults.standard.object(forKey: "morrow.last.date") as? Date ?? .now)
    }
}
