import Foundation
import Combine
import HealthKit

@MainActor
final class HealthStore: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot()
    @Published private(set) var authorizationMessage = "HealthKit 연결 전"
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    private let store = HKHealthStore()
    private let isStoreScreenshotMode: Bool
    private var observerQueries: [HKObserverQuery] = []
    private var backgroundConfigured = false

    init() {
        isStoreScreenshotMode = ProcessInfo.processInfo.environment["MORROW_STORE_SCREENSHOTS"] == "1"
        if isStoreScreenshotMode {
            snapshot = HealthSnapshot(
                sleepMinutes: 405,
                heartRate: 76,
                restingHeartRate: 72,
                hrv: 38,
                steps: 4_286,
                activeEnergyKcal: 318,
                exerciseMinutes: 24,
                distanceMeters: 3_400,
                flightsClimbed: 7,
                respiratoryRate: 15.2,
                oxygenSaturationPercent: 98,
                baselineSleepMinutes: 445,
                baselineRestingHeartRate: 67,
                baselineHRV: 47,
                hasHealthData: true
            )
            authorizationMessage = "원본은 기기에서만 읽고, 승인된 파생 요약만 AI와 동기화합니다."
            lastUpdated = .now
        }
    }

    func requestAuthorizationAndLoad() async {
        guard !isStoreScreenshotMode else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationMessage = "이 기기에서는 HealthKit을 사용할 수 없습니다."
            return
        }
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .stepCount,
            .activeEnergyBurned, .appleExerciseTime, .distanceWalkingRunning, .flightsClimbed,
            .respiratoryRate, .oxygenSaturation
        ]
        let quantityTypes = identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:))
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let workout = HKObjectType.workoutType()
        var readTypes = Set<HKObjectType>(quantityTypes.map { $0 as HKObjectType })
        readTypes.insert(sleep)
        readTypes.insert(workout)
        let observedTypes: [HKSampleType] = quantityTypes.map { $0 as HKSampleType } + [sleep, workout]
        isLoading = true
        defer { isLoading = false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            snapshot = try await loadSnapshot(sleepType: sleep)
            configureBackgroundDelivery(types: observedTypes)
            lastUpdated = .now
            authorizationMessage = snapshot.hasHealthData ? "허용된 데이터만 기기에서 분석합니다." : "표시할 HealthKit 기록이 아직 없습니다."
        } catch {
            authorizationMessage = "권한이 없는 항목을 제외하고 동작합니다."
        }
    }

    func refresh() async {
        await requestAuthorizationAndLoad()
    }

    private func configureBackgroundDelivery(types: [HKSampleType]) {
        guard !backgroundConfigured else { return }
        backgroundConfigured = true
        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor in
                    await self?.refresh()
                    completion()
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    private func loadSnapshot(sleepType: HKCategoryType) async throws -> HealthSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -8, to: startOfToday) ?? startOfToday
        async let steps = cumulativeQuantity(.stepCount, unit: .count(), from: startOfToday, to: now)
        async let activeEnergy = cumulativeQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: startOfToday, to: now)
        async let exercise = cumulativeQuantity(.appleExerciseTime, unit: .minute(), from: startOfToday, to: now)
        async let distance = cumulativeQuantity(.distanceWalkingRunning, unit: .meter(), from: startOfToday, to: now)
        async let flights = cumulativeQuantity(.flightsClimbed, unit: .count(), from: startOfToday, to: now)
        async let heart = latestQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let resting = latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let respiratory = latestQuantity(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let oxygen = latestQuantity(.oxygenSaturation, unit: .percent())
        async let restingBaseline = averageQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: weekStart, to: startOfToday)
        async let hrvBaseline = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: weekStart, to: startOfToday)
        let sleepSamples = try await sleepSamples(type: sleepType, from: weekStart, to: now)
        let sleepTotals = sleepMinutesByDay(samples: sleepSamples)
        let recentSleep = detailedSleepSession(samples: sleepSamples)
        let recentWorkouts = try await workoutDetails(from: calendar.date(byAdding: .day, value: -2, to: now) ?? startOfToday, to: now)
        let todaySleep = sleepTotals[startOfToday] ?? sleepTotals.keys.sorted().last.flatMap { sleepTotals[$0] } ?? 0
        let pastValues = sleepTotals.filter { $0.key < startOfToday && $0.value > 0 }.map(\.value)
        let sleepBaseline = pastValues.isEmpty ? 0 : pastValues.reduce(0, +) / pastValues.count
        let values = try await (steps, activeEnergy, exercise, distance, flights, heart, resting, hrv, respiratory, oxygen, restingBaseline, hrvBaseline)
        return HealthSnapshot(
            sleepMinutes: todaySleep,
            heartRate: values.5 ?? 0,
            restingHeartRate: values.6 ?? 0,
            hrv: values.7 ?? 0,
            steps: values.0 ?? 0,
            activeEnergyKcal: values.1 ?? 0,
            exerciseMinutes: values.2 ?? 0,
            distanceMeters: values.3 ?? 0,
            flightsClimbed: values.4 ?? 0,
            respiratoryRate: values.8 ?? 0,
            oxygenSaturationPercent: (values.9 ?? 0) * 100,
            baselineSleepMinutes: sleepBaseline,
            baselineRestingHeartRate: values.10 ?? 0,
            baselineHRV: values.11 ?? 0,
            sleepSession: recentSleep,
            workouts: recentWorkouts,
            hasHealthData: todaySleep > 0 || (values.0 ?? 0) > 0 || (values.5 ?? 0) > 0 || (values.7 ?? 0) > 0
        )
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) throws -> HKQuantityType {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthStoreError.unsupportedType
        }
        return type
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let type = try quantityType(identifier)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func cumulativeQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        let type = try quantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func averageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        let type = try quantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func sleepSamples(type: HKCategoryType, from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, values, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: values as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
    }

    private func sleepMinutesByDay(samples: [HKCategorySample]) -> [Date: Int] {
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return samples.reduce(into: [:]) { totals, sample in
            guard asleepValues.contains(sample.value) else { return }
            let day = Calendar.current.startOfDay(for: sample.endDate)
            totals[day, default: 0] += max(0, Int(sample.endDate.timeIntervalSince(sample.startDate) / 60))
        }
    }

    private func detailedSleepSession(samples: [HKCategorySample]) -> SleepSessionDetail? {
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
        func minutes(_ values: Set<Int>) -> Int {
            sessionSamples.filter { values.contains($0.value) }.reduce(0) { $0 + max(0, Int($1.endDate.timeIntervalSince($1.startDate) / 60)) }
        }
        let total = minutes(asleepValues)
        let identifier = "sleep-\(Int(startAt.timeIntervalSince1970))-\(Int(endAt.timeIntervalSince1970))"
        return SleepSessionDetail(
            clientSleepId: identifier, startAt: startAt, endAt: endAt, totalMinutes: total,
            coreMinutes: minutes([HKCategoryValueSleepAnalysis.asleepCore.rawValue]),
            deepMinutes: minutes([HKCategoryValueSleepAnalysis.asleepDeep.rawValue]),
            remMinutes: minutes([HKCategoryValueSleepAnalysis.asleepREM.rawValue]),
            awakeMinutes: minutes([HKCategoryValueSleepAnalysis.awake.rawValue]), source: "IPHONE"
        )
    }

    private func workoutDetails(from start: Date, to end: Date) async throws -> [WorkoutDetail] {
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 12, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        var values: [WorkoutDetail] = []
        for workout in workouts {
            let heart = try await workoutHeartRates(from: workout.startDate, to: workout.endDate)
            let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0
            let durationMinutes = workout.duration / 60
            values.append(WorkoutDetail(
                clientWorkoutId: workout.uuid.uuidString, activityType: workout.workoutActivityType.morrowName,
                startAt: workout.startDate, endAt: workout.endDate, durationMinutes: durationMinutes,
                activeEnergyKcal: energy, distanceMeters: workout.totalDistance?.doubleValue(for: .meter()) ?? 0,
                averageHeartRate: heart.average, maxHeartRate: heart.maximum,
                intensity: workoutIntensity(averageHeartRate: heart.average, energy: energy, durationMinutes: durationMinutes),
                source: workout.device?.name?.localizedCaseInsensitiveContains("watch") == true ? "WATCH" : "IPHONE"
            ))
        }
        return values
    }

    private func workoutHeartRates(from start: Date, to end: Date) async throws -> (average: Double, maximum: Double) {
        let type = try quantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: [.discreteAverage, .discreteMax]) { _, result, error in
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

enum HealthStoreError: Error { case unsupportedType }

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
