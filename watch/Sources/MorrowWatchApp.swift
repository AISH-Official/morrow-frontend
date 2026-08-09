import SwiftUI
import HealthKit
import UserNotifications

@main
struct MorrowWatchApp: App {
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
            center.removePendingNotificationRequests(withIdentifiers: ["morrow.watch.morning", "morrow.watch.evening"])
            await daily("morrow.watch.morning", 10, 5, "오늘 컨디션은 어떤가요?", "손목에서 30초 체크인을 남겨주세요.")
            await daily("morrow.watch.evening", 20, 35, "오늘의 회복 기록", "몸의 느낌을 기록하면 내일 제안이 더 정확해져요.")
        } catch { statusText = "Watch 알림 설정 실패" }
    }

    func recoveryAlert(load: Int) async {
        guard load >= 70 else { return }
        let key = "morrow.watch.notifications.lastRecovery"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 6 * 60 * 60 else { return }
        let content = UNMutableNotificationContent(); content.title = "회복 신호가 높아요"; content.body = "1분 호흡 세션을 시작해 보세요."; content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: "morrow.watch.recovery", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        UserDefaults.standard.set(Date(), forKey: key)
    }

    private func daily(_ id: String, _ hour: Int, _ minute: Int, _ title: String, _ body: String) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)))
    }
}
