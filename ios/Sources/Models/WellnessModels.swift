import SwiftUI

struct HealthSnapshot {
    var sleepMinutes: Int = 348
    var restingHeartRate: Double = 72
    var hrv: Double = 41
    var steps: Double = 4821

    var sleepText: String {
        let hours = sleepMinutes / 60
        let minutes = sleepMinutes % 60
        return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
    }

    var hrvText: String { "\(Int(hrv)) ms" }
    var restingHeartRateText: String { "\(Int(restingHeartRate)) bpm" }
    var stepsText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: Int(steps))) ?? "\(Int(steps))"
    }
}

enum WellnessStatus: String, CaseIterable, Codable, Identifiable {
    case ok = "정상"
    case tense = "긴장"
    case tired = "피로"
    case lowFocus = "집중 저하"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ok: return "face.smiling"
        case .tense: return "bolt.heart"
        case .tired: return "moon.zzz"
        case .lowFocus: return "cloud.fog"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return .green
        case .tense: return .orange
        case .tired: return .indigo
        case .lowFocus: return .purple
        }
    }

    var guide: String {
        switch self {
        case .ok: return "컨디션이 괜찮아요"
        case .tense: return "몸이나 마음이 긴장돼요"
        case .tired: return "쉬고 싶고 지쳐 있어요"
        case .lowFocus: return "집중이 잘 안 돼요"
        }
    }
}

struct WellnessRecommendation: Identifiable {
    let id: String
    let title: String
    let rationale: String
}
