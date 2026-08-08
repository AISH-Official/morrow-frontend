import Foundation

struct BaselineResult {
    let load: Int
    let summary: String
    let evidence: [String]
}

struct BaselineAnalyzer {
    func analyze(current: HealthSnapshot) -> BaselineResult {
        guard current.hasHealthData else {
            return BaselineResult(load: 0, summary: "데이터를 연결해 주세요", evidence: ["HealthKit 권한 후 분석을 시작합니다"])
        }
        var load = 40
        var evidence: [String] = []
        let sleepBaseline = current.baselineSleepMinutes > 0 ? current.baselineSleepMinutes : 420
        let heartBaseline = current.baselineRestingHeartRate > 0 ? current.baselineRestingHeartRate : 68
        if current.sleepMinutes > 0, current.sleepMinutes < sleepBaseline - 30 {
            load += 18
            evidence.append("수면이 최근 기준보다 짧음")
        }
        if current.restingHeartRate > heartBaseline + 3 {
            load += 10
            evidence.append("안정 시 심박이 최근 기준보다 높음")
        }
        if current.baselineHRV > 0, current.hrv > 0, current.hrv < current.baselineHRV * 0.85 {
            load += 10
            evidence.append("HRV가 최근 기준보다 낮음")
        }
        if evidence.isEmpty { evidence.append("최근 개인 기준 범위 안에 있어요") }
        return BaselineResult(load: min(load, 100), summary: "조금 높은 편이에요", evidence: evidence)
    }
}
