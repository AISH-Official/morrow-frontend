import SwiftUI

struct RecommendationCard: View {
    let title: String
    let rationale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("NEXT BEST ACTION", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text("약 7분")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 18 / 255, green: 55 / 255, blue: 67 / 255), Theme.panelBackground], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
        )
        .overlay { RoundedRectangle(cornerRadius: Theme.cardCornerRadius).stroke(Theme.accent.opacity(0.25)) }
    }
}
