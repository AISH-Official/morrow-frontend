import Foundation
import Combine
import WatchConnectivity

struct WatchWellnessContext {
    var score = 0
    var summary = "iPhone 데이터를 기다리는 중"
    var sleep = "--"
    var hrv = "--"
    var heart = "--"
    var steps = "--"
    var energy = "--"
    var exercise = "--"
    var respiratory = "--"
    var recommendation = "상태를 기록하면 맞춤 행동을 제안해요"
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
    @Published private(set) var isServerConnected = false
    @Published private(set) var pairingCode = ""

    override init() {
        super.init()
        restoreRecentCheckIn()
        isServerConnected = WatchConnectionStore.load() != nil
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
        let eventId = UUID()
        recentCheckIn = WatchRecentCheckIn(status: status, cause: cause, recordedAt: now)
        UserDefaults.standard.set(status, forKey: "morrow.last.status")
        UserDefaults.standard.set(cause, forKey: "morrow.last.cause")
        UserDefaults.standard.set(now, forKey: "morrow.last.date")
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "eventId": eventId.uuidString,
            "status": status,
            "cause": cause,
            "recordedAt": ISO8601DateFormatter().string(from: now)
        ])
    }

    func sendHealthSummary(_ snapshot: WatchHealthSnapshot) {
        guard WCSession.default.activationState == .activated, snapshot.hasData else { return }
        WCSession.default.transferUserInfo([
            "kind": "healthSummary",
            "heartRate": snapshot.heartRate,
            "hrv": snapshot.hrv,
            "steps": snapshot.steps,
            "activeEnergyKcal": snapshot.activeEnergyKcal,
            "exerciseMinutes": snapshot.exerciseMinutes,
            "recordedAt": ISO8601DateFormatter().string(from: Date())
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
        if values["loggedOut"] as? Bool == true {
            Task { await WatchPushRegistrar.shared.clearConnection() }
            DispatchQueue.main.async {
                self.isServerConnected = false
                self.pairingCode = ""
            }
            return
        }
        if let apiRoot = values["apiRoot"] as? String,
           let userId = values["userId"] as? String,
           let accessToken = values["accessToken"] as? String {
            let connection = WatchServerConnection(apiRoot: apiRoot, userId: userId, accessToken: accessToken)
            Task { await WatchPushRegistrar.shared.updateConnection(connection) }
        }
        if let title = values["aiInsightTitle"] as? String,
           let body = values["aiInsightBody"] as? String,
           let dateValue = values["aiInsightAt"] as? String,
           let generatedAt = ISO8601DateFormatter().date(from: dateValue) {
            Task { await WatchNotificationManager.shared.aiInsight(title: title, body: body, generatedAt: generatedAt) }
        }
        DispatchQueue.main.async {
            self.isServerConnected = values["apiRoot"] as? String != nil && values["accessToken"] as? String != nil
            self.pairingCode = values["pairingCode"] as? String ?? self.pairingCode
            self.context = WatchWellnessContext(
                score: values["score"] as? Int ?? values["load"] as? Int ?? self.context.score,
                summary: values["summary"] as? String ?? self.context.summary,
                sleep: values["sleep"] as? String ?? self.context.sleep,
                hrv: values["hrv"] as? String ?? self.context.hrv,
                heart: values["heart"] as? String ?? self.context.heart,
                steps: values["steps"] as? String ?? self.context.steps,
                energy: values["energy"] as? String ?? self.context.energy,
                exercise: values["exercise"] as? String ?? self.context.exercise,
                respiratory: values["respiratory"] as? String ?? self.context.respiratory,
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
