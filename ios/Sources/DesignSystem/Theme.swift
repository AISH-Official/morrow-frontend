import SwiftUI

/// Morrow 공통 디자인 토큰. 시스템 컬러 기반이라 다크 모드를 자동 지원합니다.
enum Theme {
    static let spacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let chipCornerRadius: CGFloat = 10

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)
}

/// 웰니스 부하(0~100)를 사용자에게 전달하는 시맨틱 레벨.
enum LoadLevel {
    case low, moderate, elevated, high

    init(load: Int) {
        switch load {
        case ..<35: self = .low
        case ..<55: self = .moderate
        case ..<75: self = .elevated
        default: self = .high
        }
    }

    var label: String {
        switch self {
        case .low: return "안정적이에요"
        case .moderate: return "무난한 편이에요"
        case .elevated: return "조금 높은 편이에요"
        case .high: return "휴식이 필요해요"
        }
    }

    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .teal
        case .elevated: return .orange
        case .high: return .red
        }
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.85), color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
