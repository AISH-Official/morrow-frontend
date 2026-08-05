import Foundation

struct BaselineResult {
    let load: Int
    let summary: String
    let evidence: [String]
}

struct BaselineAnalyzer {
    func analyze(current: HealthSnapshot) -> BaselineResult {
        // 해커톤 MVP의 결정적 규칙. 이후 Core ML/시계열 모델로 교체할 수 있습니다.
        var load = 40
        var evidence: [String] = []
        if current.sleepMinutes < 390 { load += 18; evidence.append("수면이 개인 기준보다 짧음") }
        if current.restingHeartRate > 68 { load += 10; evidence.append("안정 시 심박이 개인 기준보다 높음") }
        return BaselineResult(load: min(load, 100), summary: "조금 높은 편이에요", evidence: evidence)
    }
}
