import SwiftUI
import HealthKit
import UserNotifications
import WatchKit
import WatchConnectivity

@main
struct MorrowWatchApp: App {
    @WKExtensionDelegateAdaptor(MorrowWatchExtensionDelegate.self) private var extensionDelegate
    @StateObject private var session = WatchSessionManager.shared
    @StateObject private var health = WatchHealthStore.shared
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

struct WatchHealthSnapshot: Sendable {
    var sleepMinutes = 0
    var heartRate = 0.0
    var restingHeartRate = 0.0
    var hrv = 0.0
    var steps = 0.0
    var activeEnergyKcal = 0.0
    var exerciseMinutes = 0.0
    var distanceMeters = 0.0
    var sleepSession: WatchSleepSession?
    var workouts: [WatchWorkoutDetail] = []
    var hasData: Bool { sleepMinutes > 0 || heartRate > 0 || hrv > 0 || steps > 0 || activeEnergyKcal > 0 || exerciseMinutes > 0 || !workouts.isEmpty }
}

struct WatchSleepSession: Codable, Sendable {
    let clientSleepId: String
    let startAt: Date
    let endAt: Date
    let totalMinutes: Int
    let coreMinutes: Int
    let deepMinutes: Int
    let remMinutes: Int
    let awakeMinutes: Int
    let source: String
}

struct WatchWorkoutDetail: Codable, Sendable {
    let clientWorkoutId: String
    let activityType: String
    let startAt: Date
    let endAt: Date
    let durationMinutes: Double
    let activeEnergyKcal: Double
    let distanceMeters: Double
    let averageHeartRate: Double
    let maxHeartRate: Double
    let intensity: String
    let source: String
}

@MainActor
final class WatchHealthStore: ObservableObject {
    static let shared = WatchHealthStore()

    @Published private(set) var snapshot = WatchHealthSnapshot()
    @Published private(set) var statusText = "Watch 건강 데이터 확인 전"
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var backgroundConfigured = false
    private var authorizationRequested = false
    private var observerRefreshTask: Task<Void, Never>?
    private var observerCompletions: [() -> Void] = []

    func requestAuthorizationAndLoad() async {
        guard HKHealthStore.isHealthDataAvailable() else { statusText = "HealthKit 사용 불가"; return }
        let types = healthTypes()
        do {
            if !authorizationRequested {
                try await store.requestAuthorization(toShare: [], read: types.read)
                authorizationRequested = true
            }
            snapshot = try await loadSnapshot(sleepType: types.sleep)
            configureBackgroundDelivery(types: types.observed)
            statusText = snapshot.hasData ? "Watch 직접 수집 켜짐" : "표시할 Watch 기록 없음"
        } catch { statusText = "허용된 Watch 데이터만 사용" }
    }

    @discardableResult
    func refreshFromBackground() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types = healthTypes()
        configureBackgroundDelivery(types: types.observed)
        do {
            snapshot = try await loadSnapshot(sleepType: types.sleep)
            return await synchronizeCurrentSnapshot()
        } catch {
            statusText = "Watch 백그라운드 재시도 대기 중"
            return false
        }
    }

    @discardableResult
    func synchronizeCurrentSnapshot() async -> Bool {
        guard snapshot.hasData else { return false }
        guard UserDefaults.standard.object(forKey: "morrow.sync.derivedHealth") as? Bool != false else {
            statusText = "건강 요약 동기화 꺼짐"
            return true
        }
        WatchSessionManager.shared.sendHealthSummary(snapshot)
        let uploaded = await WatchHealthUploader.shared.upload(snapshot)
        statusText = uploaded ? "Watch 백그라운드 동기화 완료" : "iPhone 전달 대기 중"
        return uploaded || WCSession.default.activationState == .activated
    }

    func prepareBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        configureBackgroundDelivery(types: healthTypes().observed)
    }

    private func loadSnapshot(sleepType: HKCategoryType) async throws -> WatchHealthSnapshot {
        let start = Calendar.current.startOfDay(for: .now)
        let detailStart = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? start
        async let heart = latest(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let restingHeart = latest(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let steps = cumulative(.stepCount, unit: .count(), from: start)
        async let energy = cumulative(.activeEnergyBurned, unit: .kilocalorie(), from: start)
        async let exercise = cumulative(.appleExerciseTime, unit: .minute(), from: start)
        async let distance = cumulative(.distanceWalkingRunning, unit: .meter(), from: start)
        async let sleep = detailedSleepSession(type: sleepType, from: detailStart, to: .now)
        async let workouts = workoutDetails(from: detailStart, to: .now)
        let values = try await (heart, restingHeart, hrv, steps, energy, exercise, distance, sleep, workouts)
        return WatchHealthSnapshot(
            sleepMinutes: values.7?.totalMinutes ?? 0, heartRate: values.0 ?? 0, restingHeartRate: values.1 ?? 0,
            hrv: values.2 ?? 0, steps: values.3 ?? 0, activeEnergyKcal: values.4 ?? 0,
            exerciseMinutes: values.5 ?? 0, distanceMeters: values.6 ?? 0,
            sleepSession: values.7, workouts: values.8
        )
    }

    private func configureBackgroundDelivery(types: [HKSampleType]) {
        guard !backgroundConfigured else { return }
        backgroundConfigured = true
        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in self?.enqueueObservedChange(completion: completion) }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    private func enqueueObservedChange(completion: @escaping () -> Void) {
        observerCompletions.append(completion)
        observerRefreshTask?.cancel()
        observerRefreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard let self else { return }
            _ = await self.refreshFromBackground()
            let completions = self.observerCompletions
            self.observerCompletions.removeAll()
            completions.forEach { $0() }
        }
    }

    private func healthTypes() -> (read: Set<HKObjectType>, observed: [HKSampleType], sleep: HKCategoryType) {
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .stepCount, .activeEnergyBurned, .appleExerciseTime, .distanceWalkingRunning]
        let quantityTypes = identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:))
        let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let workout = HKObjectType.workoutType()
        var readTypes = Set<HKObjectType>(quantityTypes.map { $0 as HKObjectType })
        readTypes.insert(sleep)
        readTypes.insert(workout)
        return (readTypes, quantityTypes.map { $0 as HKSampleType } + [sleep, workout], sleep)
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

    private func detailedSleepSession(type: HKCategoryType, from start: Date, to end: Date) async throws -> WatchSleepSession? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, values, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: values as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        guard let lastAsleep = samples.filter({ asleepValues.contains($0.value) }).max(by: { $0.endDate < $1.endDate }) else { return nil }
        let windowStart = lastAsleep.endDate.addingTimeInterval(-18 * 60 * 60)
        let sourceIdentifier = lastAsleep.sourceRevision.source.bundleIdentifier
        let sessionSamples = samples.filter { $0.sourceRevision.source.bundleIdentifier == sourceIdentifier && $0.endDate > windowStart && $0.startDate <= lastAsleep.endDate }
        let asleep = sessionSamples.filter { asleepValues.contains($0.value) }
        guard let startAt = asleep.map(\.startDate).min(), let endAt = asleep.map(\.endDate).max() else { return nil }
        func minutes(_ values: Set<Int>) -> Int { sessionSamples.filter { values.contains($0.value) }.reduce(0) { $0 + max(0, Int($1.endDate.timeIntervalSince($1.startDate) / 60)) } }
        return WatchSleepSession(
            clientSleepId: "sleep-\(Int(startAt.timeIntervalSince1970))-\(Int(endAt.timeIntervalSince1970))",
            startAt: startAt, endAt: endAt, totalMinutes: minutes(asleepValues),
            coreMinutes: minutes([HKCategoryValueSleepAnalysis.asleepCore.rawValue]),
            deepMinutes: minutes([HKCategoryValueSleepAnalysis.asleepDeep.rawValue]),
            remMinutes: minutes([HKCategoryValueSleepAnalysis.asleepREM.rawValue]),
            awakeMinutes: minutes([HKCategoryValueSleepAnalysis.awake.rawValue]), source: "WATCH"
        )
    }

    private func workoutDetails(from start: Date, to end: Date) async throws -> [WatchWorkoutDetail] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 12, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        var result: [WatchWorkoutDetail] = []
        for workout in workouts {
            let heart = try await workoutHeartRates(from: workout.startDate, to: workout.endDate)
            let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
            let duration = workout.duration / 60
            result.append(WatchWorkoutDetail(
                clientWorkoutId: workout.uuid.uuidString, activityType: workout.workoutActivityType.morrowName,
                startAt: workout.startDate, endAt: workout.endDate, durationMinutes: duration,
                activeEnergyKcal: energy, distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                averageHeartRate: heart.average, maxHeartRate: heart.maximum,
                intensity: workoutIntensity(averageHeartRate: heart.average, energy: energy, durationMinutes: duration), source: "WATCH"
            ))
        }
        return result
    }

    private func workoutHeartRates(from start: Date, to end: Date) async throws -> (average: Double, maximum: Double) {
        let heartType = try type(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: heartType, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax]) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                let unit = HKUnit.count().unitDivided(by: .minute())
                continuation.resume(returning: (result?.averageQuantity()?.doubleValue(for: unit) ?? 0, result?.maximumQuantity()?.doubleValue(for: unit) ?? 0))
            }
            store.execute(query)
        }
    }

    private func workoutIntensity(averageHeartRate: Double, energy: Double, durationMinutes: Double) -> String {
        let energyPerMinute = durationMinutes > 0 ? energy / durationMinutes : 0
        if averageHeartRate >= 140 || energyPerMinute >= 8 { return "HIGH" }
        if averageHeartRate >= 110 || energyPerMinute >= 4 { return "MODERATE" }
        return "LIGHT"
    }
}

private extension HKWorkoutActivityType {
    var morrowName: String {
        switch self {
        case .walking: return "걷기"
        case .running: return "달리기"
        case .cycling: return "사이클링"
        case .swimming: return "수영"
        case .hiking: return "하이킹"
        case .yoga: return "요가"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "근력 운동"
        case .highIntensityIntervalTraining: return "고강도 인터벌"
        case .dance: return "댄스"
        case .stairClimbing: return "계단 오르기"
        case .elliptical: return "일립티컬"
        case .rowing: return "로잉"
        case .coreTraining: return "코어 운동"
        case .cooldown: return "쿨다운"
        default: return "기타 운동"
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
        content.userInfo = ["type": "RECOVERY", "action": "BREATH", "durationSeconds": 60, "reason": "회복 부하가 평소보다 높아요.", "confidence": "MEDIUM"]
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
        let metadata = recoveryMetadata(title + " " + body)
        content.userInfo = ["type": "RECOVERY", "action": metadata.action, "durationSeconds": metadata.duration, "reason": body, "confidence": "AI"]
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
        let metadata = recoveryMetadata(title + " " + body)
        content.userInfo = ["type": "RECOVERY", "action": metadata.action, "durationSeconds": metadata.duration, "reason": body, "confidence": "ROUTINE"]
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute, weekday: weekday), repeats: true)))
    }

    private func recoveryMetadata(_ text: String) -> (action: String, duration: Int) {
        if text.contains("걷") { return ("WALK", 300) }
        if text.contains("스트레칭") || text.contains("어깨") { return ("STRETCH", 180) }
        if text.contains("집중") || text.contains("할 일") { return ("FOCUS", 300) }
        if text.contains("화면") || text.contains("눈") { return ("SCREEN_BREAK", 60) }
        if text.contains("물") { return ("WATER_WALK", 180) }
        return ("BREATH", 60)
    }
}
