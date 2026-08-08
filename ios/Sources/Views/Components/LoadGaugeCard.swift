import SwiftUI

struct LoadGaugeCard: View {
    let result: BaselineResult
    @State private var progress: Double = 0
    private var level: LoadLevel { LoadLevel(load: result.load) }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.09), lineWidth: 11)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(level.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.accent.opacity(0.24), radius: 10)
                VStack(spacing: 1) {
                    Text("\(result.load)")
                        .font(.system(size: 38, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Text("RECOVERY")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(width: 128, height: 128)

            VStack(alignment: .leading, spacing: 10) {
                Text("PERSONAL BASELINE").morrowKicker()
                Text(level.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("직접 체크인과 최근 건강 신호를 함께 살폈어요.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .morrowPanel()
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { progress = Double(result.load) / 100 } }
        .accessibilityElement(children: .combine)
    }
}
