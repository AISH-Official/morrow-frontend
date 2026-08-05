import Foundation
import HealthKit

@MainActor
final class HealthStore: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot()
    @Published private(set) var authorizationMessage = "HealthKit 연결 전"
    private let store = HKHealthStore()

    func requestAuthorizationAndLoad() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationMessage = "이 기기에서는 HealthKit을 사용할 수 없습니다."
            return
        }
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .stepCount]
        let quantityTypes = identifiers.compactMap(HKQuantityType.quantityType(forIdentifier:))
        guard let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: Set(quantityTypes + [sleep]))
            authorizationMessage = "허용된 데이터만 분석합니다."
            // MVP 확장 지점: HKSampleQuery/HKStatisticsQuery 결과를 snapshot에 반영합니다.
        } catch {
            authorizationMessage = "권한이 없는 항목을 제외하고 동작합니다."
        }
    }
}
