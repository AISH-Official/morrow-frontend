import Foundation

struct HealthSnapshot {
    var sleepMinutes: Int = 348
    var restingHeartRate: Double = 72
    var hrv: Double = 41
    var steps: Double = 4821
}

enum WellnessStatus: String, CaseIterable, Codable {
    case ok = "정상"
    case tense = "긴장"
    case tired = "피로"
    case lowFocus = "집중 저하"
}

struct WellnessRecommendation: Identifiable {
    let id: String
    let title: String
    let rationale: String
}
