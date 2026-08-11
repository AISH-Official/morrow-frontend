import Foundation

struct BaselineResult {
    let score: Int
    let summary: String
    let evidence: [String]

    func using(score: Int?) -> BaselineResult {
        guard let score else { return self }
        return BaselineResult(score: score, summary: summary, evidence: evidence)
    }
}

struct BaselineAnalyzer {
    func analyze(current: HealthSnapshot) -> BaselineResult {
        guard current.hasHealthData else {
            return BaselineResult(score: 70, summary: "데이터를 연결해 주세요", evidence: ["HealthKit 권한 후 분석을 시작합니다"])
        }
        var score = 82
        var evidence: [String] = []
        let sleepBaseline = current.baselineSleepMinutes > 0 ? current.baselineSleepMinutes : 420
        let heartBaseline = current.baselineRestingHeartRate > 0 ? current.baselineRestingHeartRate : 72
        let hrvBaseline = current.baselineHRV > 0 ? current.baselineHRV : 45
        if current.sleepMinutes > 0 {
            let difference = sleepBaseline - current.sleepMinutes
            if difference > 0 { score -= min(30, Int(ceil(Double(difference) / 3))) }
            else { score += min(5, abs(difference) / 30) }
        }
        if current.sleepMinutes > 0, current.sleepMinutes < sleepBaseline - 30 {
            evidence.append("수면이 최근 기준보다 짧음")
        }
        if current.restingHeartRate > heartBaseline + 3 {
            score -= min(16, Int(((current.restingHeartRate - heartBaseline) * 2).rounded()))
            evidence.append("안정 시 심박이 최근 기준보다 높음")
        } else if current.restingHeartRate > 0, current.restingHeartRate <= heartBaseline {
            score += min(4, Int(((heartBaseline - current.restingHeartRate) * 0.3).rounded()))
        }
        if current.hrv > 0, current.hrv < hrvBaseline {
            score -= min(20, Int(((hrvBaseline - current.hrv) * 0.6).rounded()))
            evidence.append("HRV가 최근 기준보다 낮음")
        } else if current.hrv > 0 {
            score += min(5, Int(((current.hrv - hrvBaseline) * 0.2).rounded()))
        }
        if current.exerciseMinutes >= 40 { score += 8 }
        else if current.exerciseMinutes >= 20 { score += 5 }
        if evidence.isEmpty { evidence.append("최근 개인 기준 범위 안에 있어요") }
        return BaselineResult(score: max(0, min(score, 100)), summary: "개인 기준선과 비교한 회복 점수예요", evidence: evidence)
    }
}
