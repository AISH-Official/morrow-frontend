import SwiftUI
import SwiftData

struct HealthSnapshot {
    var sleepMinutes: Int = 0
    var restingHeartRate: Double = 0
    var hrv: Double = 0
    var steps: Double = 0
    var baselineSleepMinutes: Int = 0
    var baselineRestingHeartRate: Double = 0
    var baselineHRV: Double = 0
    var hasHealthData = false

    var sleepText: String {
        let hours = sleepMinutes / 60
        let minutes = sleepMinutes % 60
        guard sleepMinutes > 0 else { return "--" }
        return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
    }

    var hrvText: String { hrv > 0 ? "\(Int(hrv)) ms" : "--" }
    var restingHeartRateText: String { restingHeartRate > 0 ? "\(Int(restingHeartRate)) bpm" : "--" }
    var stepsText: String {
        guard steps > 0 else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: Int(steps))) ?? "\(Int(steps))"
    }
}

enum CheckInSource: String, Codable, CaseIterable {
    case iPhone
    case watch
}

@Model
final class CheckInRecord {
    @Attribute(.unique) var id: UUID
    var statusRaw: String
    var note: String
    var causeRaw: String?
    var sourceRaw: String
    var recordedAt: Date

    init(status: WellnessStatus, cause: WellnessCause? = nil, note: String = "", source: CheckInSource = .iPhone, recordedAt: Date = .now) {
        self.id = UUID()
        self.statusRaw = status.rawValue
        self.note = note
        self.causeRaw = cause?.rawValue
        self.sourceRaw = source.rawValue
        self.recordedAt = recordedAt
    }

    var status: WellnessStatus { WellnessStatus(rawValue: statusRaw) ?? .ok }
    var source: CheckInSource { CheckInSource(rawValue: sourceRaw) ?? .iPhone }
    var cause: WellnessCause? { causeRaw.flatMap(WellnessCause.init(rawValue:)) }
}

enum WellnessCause: String, CaseIterable, Codable, Identifiable {
    case sleep = "수면"
    case work = "업무"
    case study = "학업"
    case relationship = "관계"
    case physical = "신체"
    case unknown = "잘 모르겠음"

    var id: String { rawValue }
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
