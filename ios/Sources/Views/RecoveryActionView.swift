import SwiftUI
import Combine

struct PhoneRecoveryLaunch: Identifiable {
    let id = UUID()
    let action: String
    let reason: String
    let confidence: String
    let durationSeconds: Int
    let attemptId: UUID?
    let autoStart: Bool

    static let breath = PhoneRecoveryLaunch(action: "BREATH", reason: "지금 시작한 1분 회복 행동이에요.", confidence: "USER", durationSeconds: 60, attemptId: nil, autoStart: false)

    static func pending() -> PhoneRecoveryLaunch {
        let defaults = UserDefaults.standard
        let storedDuration = defaults.integer(forKey: "morrow.phone.recovery.duration")
        let value = PhoneRecoveryLaunch(
            action: defaults.string(forKey: "morrow.phone.recovery.action") ?? "BREATH",
            reason: defaults.string(forKey: "morrow.phone.recovery.reason") ?? "최근 개인 기준에서 회복 행동이 필요해 보여요.",
            confidence: defaults.string(forKey: "morrow.phone.recovery.confidence") ?? "LOW",
            durationSeconds: storedDuration > 0 ? max(30, storedDuration) : 60,
            attemptId: defaults.string(forKey: "morrow.phone.recovery.attemptId").flatMap(UUID.init(uuidString:)),
            autoStart: true
        )
        ["morrow.phone.recovery.action", "morrow.phone.recovery.reason", "morrow.phone.recovery.confidence", "morrow.phone.recovery.duration", "morrow.phone.recovery.attemptId"].forEach { defaults.removeObject(forKey: $0) }
        return value
    }

    var title: String { switch action { case "WALK": "5분 걷기"; case "WATER_WALK": "물 한 잔 + 걷기"; case "STRETCH": "3분 스트레칭"; case "FOCUS": "5분 집중"; case "SCREEN_BREAK": "1분 화면 휴식"; default: "1분 호흡" } }
    var icon: String { switch action { case "WALK", "WATER_WALK": "figure.walk"; case "STRETCH": "figure.flexibility"; case "FOCUS": "scope"; case "SCREEN_BREAK": "eye"; default: "wind" } }
    var cue: String { switch action { case "WALK": "편한 속도로 걸어보세요"; case "WATER_WALK": "물 한 잔 뒤 천천히 걸어보세요"; case "STRETCH": "목과 어깨부터 천천히 풀어보세요"; case "FOCUS": "방해 요소를 닫고 한 가지만 시작하세요"; case "SCREEN_BREAK": "먼 곳을 바라보고 어깨 힘을 빼세요"; default: "4초 들이쉬고 6초 내쉬세요" } }
}

struct RecoveryActionView: View {
    let launch: PhoneRecoveryLaunch
    @Environment(\.dismiss) private var dismiss
    @State private var remaining: Int
    @State private var running: Bool
    @State private var attemptId: UUID?
    @State private var resultMessage = ""
    @State private var isSubmitting = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(launch: PhoneRecoveryLaunch = .breath) {
        self.launch = launch
        _remaining = State(initialValue: max(30, launch.durationSeconds))
        _running = State(initialValue: launch.autoStart)
        _attemptId = State(initialValue: launch.attemptId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Label("WHY NOW · \(confidenceLabel)", systemImage: "waveform.path.ecg")
                            .morrowKicker().foregroundStyle(Theme.accent)
                        Text(launch.reason).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                    }
                    .padding(16).frame(maxWidth: .infinity).morrowPanel(cornerRadius: 17)

                    ZStack {
                        Circle().stroke(Theme.mint.opacity(0.12), lineWidth: 16)
                        Circle().trim(from: 0, to: progress).stroke(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 16, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.linear, value: remaining)
                        VStack(spacing: 8) {
                            Image(systemName: launch.icon).font(.title2).foregroundStyle(Theme.mint)
                            Text(timeText).font(.system(size: 42, weight: .medium, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                            Text(running ? activeCue : launch.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 250, height: 250)

                    if remaining > 0 {
                        Text(launch.cue).font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        Button(running ? "잠시 멈춤" : "지금 시작") { running.toggle(); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            .font(.headline).foregroundStyle(Theme.screenBackground).frame(maxWidth: .infinity).frame(height: 52)
                            .background(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 15))
                    } else if resultMessage.isEmpty {
                        VStack(spacing: 12) {
                            Text("실행 전보다 조금 나아졌나요?").font(.headline).foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 8) {
                                outcomeButton("나아졌어요", "IMPROVED", Theme.mint)
                                outcomeButton("그대로예요", "SAME", Theme.accent)
                                outcomeButton("더 불편해요", "WORSE", .orange)
                            }
                        }.padding(16).morrowPanel(cornerRadius: 17)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Theme.mint)
                            Text(resultMessage).font(.headline).multilineTextAlignment(.center)
                            Text("이번 결과가 다음 추천에 반영됩니다.").font(.caption).foregroundStyle(Theme.textSecondary)
                        }.padding(20).frame(maxWidth: .infinity).morrowPanel(cornerRadius: 17)
                    }
                }
                .padding(20)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .navigationTitle(launch.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } } }
        }
        .task { await prepareAttempt() }
        .onReceive(timer) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { running = false; UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private var confidenceLabel: String { switch launch.confidence { case "HIGH": "높은 신뢰도"; case "MEDIUM": "보통 신뢰도"; case "USER": "직접 시작"; case "AI": "AI 분석"; default: "학습 중" } }
    private var progress: Double { Double(max(0, launch.durationSeconds - remaining)) / Double(max(1, launch.durationSeconds)) }
    private var timeText: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }
    private var activeCue: String { launch.action == "BREATH" ? (((launch.durationSeconds - remaining) / 4).isMultiple(of: 2) ? "천천히 들이쉬기" : "길게 내쉬기") : launch.cue }

    private func outcomeButton(_ title: String, _ outcome: String, _ tint: Color) -> some View {
        Button(title) { Task { await submit(outcome) } }.font(.caption.weight(.semibold)).foregroundStyle(tint).padding(.vertical, 11).frame(maxWidth: .infinity).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.25))).disabled(isSubmitting)
    }

    @MainActor private func prepareAttempt() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if let attemptId { _ = try await MorrowAPIClient.shared.startRecoveryAttempt(attemptId) }
            else { attemptId = try await MorrowAPIClient.shared.createRecoveryAttempt(action: launch.action, triggerType: "IPHONE_STARTED", reason: launch.reason, confidence: launch.confidence).id }
        } catch {}
    }

    @MainActor private func submit(_ outcome: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        if let attemptId { _ = try? await MorrowAPIClient.shared.completeRecoveryAttempt(attemptId, outcome: outcome) }
        resultMessage = outcome == "IMPROVED" ? "이 방법을 다음에도 우선 제안할게요." : outcome == "SAME" ? "다음에는 다른 행동을 시험해 볼게요." : "이 행동은 다음 추천에서 피할게요."
        UINotificationFeedbackGenerator().notificationOccurred(outcome == "IMPROVED" ? .success : .warning)
    }
}

struct RecoveryEffectReportView: View {
    @State private var report: NativeWeeklyReport?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("RECOVERY EFFECT LOOP").morrowKicker().foregroundStyle(Theme.accent)
                    Text("이번 주에 무엇이 실제로 도움이 됐을까요?").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                    Text("실행 뒤 직접 남긴 변화만 효과로 계산합니다.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                if let report {
                    HStack(spacing: 10) {
                        reportMetric("제안", "\(report.suggestedRecoveryCount)회", "bell.badge")
                        reportMetric("완료", "\(report.completedRecoveryCount)회", "checkmark.circle")
                        reportMetric("나아짐", "\(Int(report.recoveryHelpfulRate.rounded()))%", "chart.line.uptrend.xyaxis")
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Label("이번 주 가장 잘 맞은 행동", systemImage: "sparkles").morrowKicker().foregroundStyle(Theme.mint)
                        Text(report.topHelpfulAction ?? "효과 피드백을 더 모으는 중").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                        Text(report.recoveryInsight).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }.padding(17).morrowPanel(cornerRadius: 17)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("WEEKLY FLOW").morrowKicker()
                        Text(report.totalCheckIns == 0 ? "체크인을 남기면 상태 변화도 함께 비교할 수 있어요." : "체크인 \(report.totalCheckIns)회 · 지난주 대비 \(signed(report.changeFromPrevious))점")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }.padding(17).frame(maxWidth: .infinity, alignment: .leading).morrowPanel(cornerRadius: 17)
                } else if isLoading {
                    ProgressView("효과 기록 불러오는 중").tint(Theme.accent).frame(maxWidth: .infinity).padding(40)
                } else {
                    Text("서버에 연결한 뒤 다시 확인해 주세요.").foregroundStyle(Theme.textSecondary).padding(18).frame(maxWidth: .infinity).morrowPanel(cornerRadius: 17)
                }
            }.padding(18)
        }
        .background(Theme.screenBackground.ignoresSafeArea())
        .navigationTitle("회복 효과")
        .navigationBarTitleDisplayMode(.inline)
        .task { do { report = try await MorrowAPIClient.shared.weeklyReport() } catch {}; isLoading = false }
    }

    private func reportMetric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Image(systemName: icon).foregroundStyle(Theme.accent); Text(label).font(.caption).foregroundStyle(Theme.textMuted); Text(value).font(.headline).foregroundStyle(Theme.textPrimary) }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading).morrowPanel(cornerRadius: 14)
    }
    private func signed(_ value: Double) -> String { value >= 0 ? "+\(Int(value.rounded()))" : "\(Int(value.rounded()))" }
}
