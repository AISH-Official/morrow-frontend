import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var health: HealthStore
    private let analyzer = BaselineAnalyzer()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let result = analyzer.analyze(current: health.snapshot)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    header

                    LoadGaugeCard(result: result)

                    Text("오늘의 지표")
                        .font(.headline)
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 12) {
                        MetricCard(title: "수면", value: health.snapshot.sleepText, icon: "bed.double.fill", tint: .indigo)
                        MetricCard(title: "HRV", value: health.snapshot.hrvText, icon: "waveform.path.ecg", tint: .pink)
                        MetricCard(title: "안정 심박", value: health.snapshot.restingHeartRateText, icon: "heart.fill", tint: .red)
                        MetricCard(title: "걸음", value: health.snapshot.stepsText, icon: "figure.walk", tint: .green)
                    }

                    RecommendationCard(
                        title: "7분 동안 가볍게 걸어보세요",
                        rationale: "과거의 유사한 상태에서 짧은 걷기가 도움이 됐습니다."
                    )
                    .padding(.top, 4)

                    NavigationLink(destination: CheckInView()) {
                        Label("지금 상태 기록하기", systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)

                    footer
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.bottom, Theme.spacing)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Morrow")
            .task { await health.requestAuthorizationAndLoad() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.locale(Locale(identifier: "ko_KR")).month(.wide).day().weekday(.wide)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("오늘의 웰니스")
                .font(.title2.bold())
        }
        .padding(.top, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(health.authorizationMessage, systemImage: "heart.text.square")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("의료 진단이 아닌 일상 웰니스 분석입니다.", systemImage: "info.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }
}
