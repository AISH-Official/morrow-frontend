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

    init() {
        isStoreScreenshotMode = ProcessInfo.processInfo.environment["MORROW_STORE_SCREENSHOTS"] == "1"
        if isStoreScreenshotMode {
            snapshot = HealthSnapshot(
                sleepMinutes: 405,
                restingHeartRate: 72,
                hrv: 38,
                steps: 4_286,
                baselineSleepMinutes: 445,
                baselineRestingHeartRate: 67,
                baselineHRV: 47,
                hasHealthData: true
            )
            authorizationMessage = "건강 데이터는 기기 안에서만 분석합니다."
            lastUpdated = .now
        }
    }

    func requestAuthorizationAndLoad() async {
        guard !isStoreScreenshotMode else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationMessage = "이 기기에서는 HealthKit을 사용할 수 없습니다."
            return
        }
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .stepCount]
        let quantityTypes = identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:))
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(quantityTypes + [sleep]))
            snapshot = try await loadSnapshot(sleepType: sleep)
            lastUpdated = .now
            authorizationMessage = snapshot.hasHealthData ? "허용된 데이터만 기기에서 분석합니다." : "표시할 HealthKit 기록이 아직 없습니다."
        } catch {
            authorizationMessage = "권한이 없는 항목을 제외하고 동작합니다."
        }
    }

    func refresh() async {
        await requestAuthorizationAndLoad()
    }

    private func loadSnapshot(sleepType: HKCategoryType) async throws -> HealthSnapshot {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -8, to: startOfToday) ?? startOfToday
        async let steps = cumulativeQuantity(.stepCount, unit: .count(), from: startOfToday, to: now)
        async let resting = latestQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        async let restingBaseline = averageQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), from: weekStart, to: startOfToday)
        async let hrvBaseline = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: weekStart, to: startOfToday)
        let sleepTotals = try await sleepMinutesByDay(type: sleepType, from: weekStart, to: now)
        let todaySleep = sleepTotals[startOfToday] ?? sleepTotals.keys.sorted().last.flatMap { sleepTotals[$0] } ?? 0
        let pastValues = sleepTotals.filter { $0.key < startOfToday && $0.value > 0 }.map(\.value)
        let sleepBaseline = pastValues.isEmpty ? 0 : pastValues.reduce(0, +) / pastValues.count
        let values = try await (steps, resting, hrv, restingBaseline, hrvBaseline)
        return HealthSnapshot(
            sleepMinutes: todaySleep,
            restingHeartRate: values.1 ?? 0,
            hrv: values.2 ?? 0,
            steps: values.0 ?? 0,
            baselineSleepMinutes: sleepBaseline,
            baselineRestingHeartRate: values.3 ?? 0,
            baselineHRV: values.4 ?? 0,
            hasHealthData: todaySleep > 0 || (values.0 ?? 0) > 0 || (values.1 ?? 0) > 0 || (values.2 ?? 0) > 0
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

    private func sleepMinutesByDay(type: HKCategoryType, from start: Date, to end: Date) async throws -> [Date: Int] {
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
        return samples.reduce(into: [:]) { totals, sample in
            guard asleepValues.contains(sample.value) else { return }
            let day = Calendar.current.startOfDay(for: sample.endDate)
            totals[day, default: 0] += max(0, Int(sample.endDate.timeIntervalSince(sample.startDate) / 60))
        }
    }
}

enum HealthStoreError: Error { case unsupportedType }
