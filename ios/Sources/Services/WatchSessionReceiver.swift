import Foundation
import Combine
import WatchConnectivity

struct IncomingWatchCheckIn: Codable {
    let eventId: UUID
    let status: String
    let cause: String?
    let recordedAt: Date
}

struct IncomingWatchHealthSummary: Codable {
    let sleepMinutes: Int
    let heartRate: Double
    let restingHeartRate: Double
    let hrv: Double
    let steps: Double
    let activeEnergyKcal: Double
    let exerciseMinutes: Double
    let distanceMeters: Double
    let sleepSession: SleepSessionDetail?
    let workouts: [WorkoutDetail]
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

    func sendWellnessContext(score: Int, summary: String, snapshot: HealthSnapshot, recommendation: NativeRecommendation?, syncDerivedHealth: Bool) {
        var context: [String: Any] = pendingContext ?? [:]
        context["score"] = score
        context["summary"] = summary
        context["sleep"] = snapshot.sleepText
        context["hrv"] = snapshot.hrvText
        context["heart"] = snapshot.restingHeartRateText
        context["steps"] = snapshot.stepsText
        context["energy"] = snapshot.activeEnergyText
        context["exercise"] = snapshot.exerciseText
        context["respiratory"] = snapshot.respiratoryText
        context["recommendation"] = recommendation?.title ?? "지금 상태를 기록하면 맞춤 행동을 제안해요"
        context["recommendationReason"] = recommendation?.rationale ?? ""
        context["recommendationAction"] = recommendation?.action ?? ""
        context["recommendationDuration"] = recommendation?.durationSeconds ?? 0
        context["recommendationSource"] = recommendation?.source ?? "RULE"
        context["syncDerivedHealth"] = syncDerivedHealth
        context["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        pendingContext = context
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func sendConnectionContext(apiRoot: String, credentials: MorrowCredentials) {
        var context = pendingContext ?? [:]
        context.removeValue(forKey: "loggedOut")
        context["apiRoot"] = apiRoot
        context["userId"] = credentials.userId
        context["accessToken"] = credentials.accessToken
        context["pairingCode"] = credentials.pairingCode
        pendingContext = context
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func sendLogoutContext() {
        var context = pendingContext ?? [:]
        context.removeValue(forKey: "apiRoot")
        context.removeValue(forKey: "userId")
        context.removeValue(forKey: "accessToken")
        context.removeValue(forKey: "pairingCode")
        context["loggedOut"] = true
        pendingContext = context
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func sendAIInsight(title: String, body: String, generatedAt: Date) {
        var context = pendingContext ?? [:]
        context["aiInsightTitle"] = title
        context["aiInsightBody"] = body
        context["aiInsightAt"] = ISO8601DateFormatter().string(from: generatedAt)
        pendingContext = context
        guard WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["kind"] as? String == "healthSummary" {
            let date = (userInfo["recordedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? .now
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sleepData = (userInfo["sleepSessionJSON"] as? String)?.data(using: .utf8)
            let workoutData = (userInfo["workoutsJSON"] as? String)?.data(using: .utf8)
            let sleep = sleepData.flatMap { try? decoder.decode(SleepSessionDetail.self, from: $0) }
            let workouts = workoutData.flatMap { try? decoder.decode([WorkoutDetail].self, from: $0) } ?? []
            let summary = IncomingWatchHealthSummary(
                sleepMinutes: userInfo["sleepMinutes"] as? Int ?? sleep?.totalMinutes ?? 0,
                heartRate: userInfo["heartRate"] as? Double ?? 0,
                restingHeartRate: userInfo["restingHeartRate"] as? Double ?? 0,
                hrv: userInfo["hrv"] as? Double ?? 0,
                steps: userInfo["steps"] as? Double ?? 0,
                activeEnergyKcal: userInfo["activeEnergyKcal"] as? Double ?? 0,
                exerciseMinutes: userInfo["exerciseMinutes"] as? Double ?? 0,
                distanceMeters: userInfo["distanceMeters"] as? Double ?? 0,
                sleepSession: sleep,
                workouts: workouts,
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
        let eventId = (userInfo["eventId"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        inbox.append(IncomingWatchCheckIn(eventId: eventId, status: status, cause: cause, recordedAt: date))
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
