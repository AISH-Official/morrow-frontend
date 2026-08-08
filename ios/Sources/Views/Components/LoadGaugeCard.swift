import SwiftUI

/// 오늘의 웰니스 부하를 원형 게이지와 근거 칩으로 보여주는 카드.
struct LoadGaugeCard: View {
    let result: BaselineResult
    @State private var progress: Double = 0

    private var level: LoadLevel { LoadLevel(load: result.load) }

    var body: some View {
        VStack(spacing: Theme.spacing) {
            ZStack {
                Circle()
                    .stroke(level.color.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(level.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(result.load)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("/ 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 150)
            .padding(.top, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("오늘의 웰니스 부하 \(result.load)점, \(level.label)")

            Text(level.label)
                .font(.title3.bold())
                .foregroundStyle(level.color)

            if !result.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.evidence, id: \.self) { item in
                        Label(item, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Theme.screenBackground,
                                in: RoundedRectangle(cornerRadius: Theme.chipCornerRadius)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.spacing)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) {
                progress = Double(result.load) / 100
            }
        }
    }
}
