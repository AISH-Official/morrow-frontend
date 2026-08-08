import SwiftUI

/// Web console과 Apple 앱이 공유하는 Morrow 시각 언어.
enum Theme {
    static let spacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 18
    static let chipCornerRadius: CGFloat = 10

    static let screenBackground = Color(red: 3 / 255, green: 13 / 255, blue: 19 / 255)
    static let panelBackground = Color(red: 7 / 255, green: 23 / 255, blue: 31 / 255)
    static let elevatedBackground = Color(red: 10 / 255, green: 31 / 255, blue: 40 / 255)
    static let cardBackground = panelBackground
    static let border = Color(red: 99 / 255, green: 202 / 255, blue: 222 / 255).opacity(0.16)
    static let accent = Color(red: 103 / 255, green: 222 / 255, blue: 241 / 255)
    static let mint = Color(red: 91 / 255, green: 222 / 255, blue: 172 / 255)
    static let textPrimary = Color(red: 232 / 255, green: 251 / 255, blue: 255 / 255)
    static let textSecondary = Color(red: 125 / 255, green: 160 / 255, blue: 169 / 255)
    static let textMuted = Color(red: 76 / 255, green: 109 / 255, blue: 118 / 255)
    static let panelGradient = LinearGradient(
        colors: [elevatedBackground.opacity(0.94), panelBackground.opacity(0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func morrowPanel(cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        background(Theme.panelGradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            }
    }

    func morrowKicker() -> some View {
        font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Theme.textMuted)
    }
}

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
        case .low: return "회복 여유가 충분해요"
        case .moderate: return "안정적인 리듬이에요"
        case .elevated: return "리듬 회복이 필요해요"
        case .high: return "무리하지 않는 게 좋아요"
        }
    }

    var color: Color {
        switch self {
        case .low: return Theme.mint
        case .moderate: return Theme.accent
        case .elevated: return Color(red: 223 / 255, green: 189 / 255, blue: 119 / 255)
        case .high: return Color(red: 255 / 255, green: 105 / 255, blue: 114 / 255)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [Theme.accent, color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
