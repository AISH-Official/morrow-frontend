import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var health: HealthStore
    private let analyzer = BaselineAnalyzer()
    var body: some View {
        let result = analyzer.analyze(current: health.snapshot)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("오늘의 웰니스 부하").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.summary).font(.largeTitle.bold())
                        Spacer(); Text("\(result.load)").font(.system(size: 42, weight: .bold))
                    }
                    ForEach(result.evidence, id: \.self) { Text("• \($0)").font(.subheadline).foregroundStyle(.secondary) }
                    HStack { metric("수면", "5h 48m"); metric("HRV", "41 ms") }
                    GroupBox("지금의 추천") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("7분 동안 가볍게 걸어보세요").font(.headline)
                            Text("과거의 유사한 상태에서 짧은 걷기가 도움이 됐습니다.").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                    NavigationLink("상태 직접 기록", destination: CheckInView())
                    Text("의료 진단이 아닌 일상 웰니스 분석입니다.").font(.caption2).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("Morrow")
            .task { await health.requestAuthorizationAndLoad() }
        }
    }
    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(name).font(.caption); Text(value).font(.title2.bold()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
