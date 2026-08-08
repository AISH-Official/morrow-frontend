import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject private var health: HealthStore
    @Query(sort: \CheckInRecord.recordedAt, order: .reverse) private var checkIns: [CheckInRecord]
    private let analyzer = BaselineAnalyzer()
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let result = analyzer.analyze(current: health.snapshot)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    LoadGaugeCard(result: result)
                    evidence(result)

                    Text("TODAY'S SIGNALS").morrowKicker().padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 10) {
                        MetricCard(title: "수면", value: health.snapshot.sleepText, icon: "bed.double.fill", tint: Color(red: 164 / 255, green: 146 / 255, blue: 238 / 255))
                        MetricCard(title: "HRV", value: health.snapshot.hrvText, icon: "waveform.path.ecg", tint: Theme.accent)
                        MetricCard(title: "안정 심박", value: health.snapshot.restingHeartRateText, icon: "heart.fill", tint: Color(red: 255 / 255, green: 105 / 255, blue: 114 / 255))
                        MetricCard(title: "걸음", value: health.snapshot.stepsText, icon: "figure.walk", tint: Theme.mint)
                    }

                    RecommendationCard(title: "7분 동안 가볍게 걸어보세요", rationale: "수면 회복이 낮은 날에는 강한 운동보다 짧은 움직임이 리듬을 되찾는 데 부담이 적어요.")

                    NavigationLink(destination: CheckInView()) {
                        HStack {
                            Image(systemName: "plus")
                            Text("30초 체크인")
                            Spacer()
                            Text("상태와 원인 기록").font(.caption).foregroundStyle(Theme.screenBackground.opacity(0.68))
                        }
                        .font(.headline)
                        .foregroundStyle(Theme.screenBackground)
                        .padding(.horizontal, 17)
                        .frame(height: 54)
                        .background(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 15))
                    }

                    recentSignals
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .toolbarBackground(Theme.screenBackground, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(destination: CheckInHistoryView()) { Image(systemName: "clock.arrow.circlepath") }
                    NavigationLink(destination: SettingsView()) { Image(systemName: "slider.horizontal.3") }
                }
            }
            .tint(Theme.accent)
            .refreshable { await health.refresh() }
            .task { await health.requestAuthorizationAndLoad() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("MORROW").font(.system(size: 20, weight: .bold, design: .monospaced)).tracking(4).foregroundStyle(Theme.textPrimary)
                Text("PERSONAL WELLNESS INTELLIGENCE").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(Theme.mint).frame(width: 6, height: 6).shadow(color: Theme.mint, radius: 5)
                Text("ON DEVICE").font(.system(size: 8, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(Capsule().stroke(Theme.border))
        }
        .padding(.top, 8)
    }

    private func evidence(_ result: BaselineResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(result.evidence, id: \.self) { item in
                    Label(item, systemImage: "waveform.path.ecg")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Theme.elevatedBackground, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                }
            }
        }
    }

    private var recentSignals: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT SIGNAL STORY").morrowKicker()
                Spacer()
                Text("\(checkIns.count) RECORDS").font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.textMuted)
            }
            if checkIns.isEmpty {
                Text("첫 체크인을 남기면 회복 흐름이 여기에 쌓여요.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary).padding(16).frame(maxWidth: .infinity, alignment: .leading).morrowPanel(cornerRadius: 14)
            } else {
                ForEach(checkIns.prefix(3)) { record in
                    HStack(spacing: 12) {
                        Image(systemName: record.status.icon).foregroundStyle(record.status.tint).frame(width: 34, height: 34).background(record.status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.status.rawValue + (record.cause.map { " · \($0.rawValue)" } ?? "")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text(record.note.isEmpty ? "직접 기록한 상태" : record.note).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        Text(record.recordedAt.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(Theme.textMuted)
                    }
                    .padding(12).morrowPanel(cornerRadius: 13)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(health.authorizationMessage, systemImage: "lock.shield")
            Label("의료 진단이 아닌 일상 웰니스 분석입니다.", systemImage: "info.circle")
        }
        .font(.caption2).foregroundStyle(Theme.textMuted).padding(.top, 4)
    }
}
