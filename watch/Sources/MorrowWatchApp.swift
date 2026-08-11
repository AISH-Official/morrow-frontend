import SwiftUI
import HealthKit
import UserNotifications
import WatchKit

@main
struct MorrowWatchApp: App {
    @WKExtensionDelegateAdaptor(MorrowWatchExtensionDelegate.self) private var extensionDelegate
    @StateObject private var session = WatchSessionManager()
    @StateObject private var health = WatchHealthStore()
    @StateObject private var notifications = WatchNotificationManager.shared

    var body: some Scene {
        WindowGroup {
            WatchCheckInView()
                .environmentObject(session)
                .environmentObject(health)
                .environmentObject(notifications)
        }
    }
}

struct WatchHealthSnapshot {
    var heartRate = 0.0
    var hrv = 0.0
    var steps = 0.0
    var activeEnergyKcal = 0.0
    var exerciseMinutes = 0.0
    var hasData: Bool { heartRate > 0 || hrv > 0 || steps > 0 || activeEnergyKcal > 0 || exerciseMinutes > 0 }
}

@MainActor
final class WatchHealthStore: ObservableObject {
    @Published private(set) var snapshot = WatchHealthSnapshot()
    @Published private(set) var statusText = "Watch 건강 데이터 확인 전"
    private let store = HKHealthStore()

    func requestAuthorizationAndLoad() async {
        guard HKHealthStore.isHealthDataAvailable() else { statusText = "HealthKit 사용 불가"; return }
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .heartRateVariabilitySDNN, .stepCount, .activeEnergyBurned, .appleExerciseTime]
        let types = identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:))
        do {
            try await store.requestAuthorization(toShare: [], read: Set(types))
            let start = Calendar.current.startOfDay(for: .now)
            async let heart = latest(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
            async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
            async let steps = cumulative(.stepCount, unit: .count(), from: start)
            async let energy = cumulative(.activeEnergyBurned, unit: .kilocalorie(), from: start)
            async let exercise = cumulative(.appleExerciseTime, unit: .minute(), from: start)
            let values = try await (heart, hrv, steps, energy, exercise)
            snapshot = WatchHealthSnapshot(heartRate: values.0 ?? 0, hrv: values.1 ?? 0, steps: values.2 ?? 0, activeEnergyKcal: values.3 ?? 0, exerciseMinutes: values.4 ?? 0)
            statusText = snapshot.hasData ? "Watch 직접 수집 켜짐" : "표시할 Watch 기록 없음"
        } catch { statusText = "허용된 Watch 데이터만 사용" }
    }

    private func type(_ id: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let value = HKQuantityType.quantityType(forIdentifier: id) else { throw URLError(.unsupportedURL) }
        return value
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let quantityType = try type(id)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: quantityType, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func cumulative(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async throws -> Double? {
        let quantityType = try type(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

@MainActor
final class WatchNotificationManager: ObservableObject {
    static let shared = WatchNotificationManager()
    @Published private(set) var statusText = "알림 권한 확인 전"
    private let center = UNUserNotificationCenter.current()
    private init() {}

    func configure() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            statusText = granted ? "Watch 알림 켜짐" : "Watch 설정에서 알림 허용 필요"
            guard granted else { return }
            WKExtension.shared().registerForRemoteNotifications()
            let old = ["morrow.watch.morning", "morrow.watch.evening"]
            let weekly = (1...7).flatMap { ["morrow.watch.action.morning.\($0)", "morrow.watch.action.evening.\($0)"] }
            center.removePendingNotificationRequests(withIdentifiers: old + weekly)
            let morning = [
                ("지금 물 한 잔 어때요?", "물을 마시고 손목에서 오늘 첫 상태를 기록해 보세요."),
                ("30초만 햇빛을 볼까요?", "창가나 밖에서 밝은 빛을 보고 하루 리듬을 시작해 보세요."),
                ("지금 어깨를 세 번 돌려요", "굳은 자세를 풀고 길게 숨을 한 번 내쉬어 보세요."),
                ("오늘 할 일 하나만 골라요", "가장 작은 일부터 10분 집중을 시작해 보세요."),
                ("지금 3분 걸어볼까요?", "가까운 곳까지 가볍게 움직이고 컨디션을 확인해 보세요."),
                ("주말 리듬을 가볍게 시작해요", "물 한 잔 뒤 몸의 느낌을 손목에 남겨보세요."),
                ("1분 호흡으로 시작해요", "4초 들이마시고 6초 내쉬는 호흡을 지금 시작해 보세요.")
            ]
            let evening = [
                ("지금 화면을 5분 내려놔요", "눈과 어깨를 쉬게 하고 오늘 상태를 기록해 보세요."),
                ("오늘 긴장을 1분 내려놔요", "길게 내쉬는 호흡을 여섯 번 반복해 보세요."),
                ("지금 3분 스트레칭해요", "목과 어깨를 천천히 풀고 회복 모드로 바꿔보세요."),
                ("오늘 도움 된 행동을 남겨요", "잘 맞았던 회복 행동을 기록하면 다음 추천이 좋아져요."),
                ("잠들기 전 물 한 모금", "오늘 몸의 느낌을 확인하고 무리한 활동은 마무리해요."),
                ("지금 5분 천천히 걸어요", "오늘 움직임을 부드럽게 마무리하고 호흡을 낮춰보세요."),
                ("다음 주를 위한 30초 체크인", "지금 상태를 남기고 오늘은 충분히 쉬어주세요.")
            ]
            for weekday in 1...7 {
                await weeklyAction("morrow.watch.action.morning.\(weekday)", weekday, 10, 5, morning[weekday - 1].0, morning[weekday - 1].1)
                await weeklyAction("morrow.watch.action.evening.\(weekday)", weekday, 20, 35, evening[weekday - 1].0, evening[weekday - 1].1)
            }
        } catch { statusText = "Watch 알림 설정 실패" }
    }

    func recoveryAlert(load: Int) async {
        guard load >= 70 else { return }
        let key = "morrow.watch.notifications.lastRecovery"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 6 * 60 * 60 else { return }
        let content = UNMutableNotificationContent(); content.title = "회복 신호가 높아요"; content.body = "1분 호흡 세션을 시작해 보세요."; content.sound = .default
        content.categoryIdentifier = "MORROW_ACTION"
        try? await center.add(UNNotificationRequest(identifier: "morrow.watch.recovery", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func aiInsight(title: String, body: String, generatedAt: Date) async {
        let deliveryKey = "morrow.watch.notifications.lastAIInsight"
        let lastDelivery = UserDefaults.standard.object(forKey: deliveryKey) as? Date ?? .distantPast
        guard generatedAt > lastDelivery, generatedAt.timeIntervalSince(lastDelivery) > 6 * 60 * 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["type": "AI_INSIGHT"]
        content.categoryIdentifier = "MORROW_ACTION"
        let request = UNNotificationRequest(
            identifier: "morrow.watch.ai.\(Int(generatedAt.timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        )
        do {
            try await center.add(request)
            UserDefaults.standard.set(generatedAt, forKey: deliveryKey)
        } catch {
            statusText = "AI 알림 예약 실패"
        }
    }

    private func weeklyAction(_ id: String, _ weekday: Int, _ hour: Int, _ minute: Int, _ title: String, _ body: String) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default; content.categoryIdentifier = "MORROW_ACTION"
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday), repeats: true)))
    }
}
