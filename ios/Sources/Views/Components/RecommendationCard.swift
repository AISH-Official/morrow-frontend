import SwiftUI

/// 현재 상태에 맞는 행동 추천을 강조해서 보여주는 카드.
struct RecommendationCard: View {
    let title: String
    let rationale: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("지금의 추천", systemImage: "sparkles")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(rationale)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacing)
        .background(
            LinearGradient(
                colors: [.indigo, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
        )
        .accessibilityElement(children: .combine)
    }
}
