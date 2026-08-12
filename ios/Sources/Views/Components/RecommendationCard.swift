import SwiftUI

struct RecommendationCard: View {
    let title: String
    let rationale: String
    var durationSeconds: Int? = nil
    var source: String? = nil
    var onStart: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("NEXT BEST ACTION", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(metaText)
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted)
            }
            Text(title).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(rationale).font(.footnote).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle")
                Text("부담이 적고 지금 바로 실행할 수 있어요")
            }
            .font(.caption2)
            .foregroundStyle(Theme.mint)
            if let onStart {
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("지금 바로 실행")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.screenBackground)
                    .padding(.horizontal, 15)
                    .frame(height: 46)
                    .background(
                        LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("이 추천 행동과 타이머를 엽니다")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 18 / 255, green: 55 / 255, blue: 67 / 255), Theme.panelBackground], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: Theme.cardCornerRadius).stroke(Theme.accent.opacity(0.25)) }
    }

    private var metaText: String {
        guard let durationSeconds else { return "체크인 후 추천" }
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        let duration = seconds == 0 ? "약 \(max(1, minutes))분" : "\(minutes)분 \(seconds)초"
        let origin = source == "AI" ? "AI 맞춤" : source == "LEARNED" ? "효과 학습" : "상태 맞춤"
        return "\(origin) · \(duration)"
    }
}
