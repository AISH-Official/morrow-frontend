import SwiftUI
import SwiftData

struct DashboardView: View {
    let onLogout: () async -> Void
    @EnvironmentObject private var health: HealthStore
    @EnvironmentObject private var syncService: MorrowSyncService
    @Query(sort: \CheckInRecord.recordedAt, order: .reverse) private var checkIns: [CheckInRecord]
    @State private var recommendedRecovery: PhoneRecoveryLaunch?
    private let analyzer = BaselineAnalyzer()
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let result = analyzer.analyze(current: health.snapshot).using(score: syncService.recoveryScore)
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
                        MetricCard(title: "활동 에너지", value: health.snapshot.activeEnergyText, icon: "flame.fill", tint: .orange)
                        MetricCard(title: "운동", value: health.snapshot.exerciseText, icon: "figure.run", tint: Theme.mint)
                        MetricCard(title: "이동 거리", value: health.snapshot.distanceText, icon: "map.fill", tint: Theme.accent)
                        MetricCard(title: "호흡수", value: health.snapshot.respiratoryText, icon: "lungs.fill", tint: .cyan)
                    }
                    healthDetailPanel

                    if let recommendation = syncService.currentRecommendation {
                        RecommendationCard(
                            title: recommendation.title,
                            rationale: recommendation.rationale,
                            durationSeconds: recommendationDuration(recommendation),
                            source: recommendation.source,
                            onStart: { recommendedRecovery = recoveryLaunch(recommendation) }
                        )
                    } else {
                        RecommendationCard(title: "지금 상태를 기록해 보세요", rationale: "30초 체크인을 남기면 오늘의 흐름에 맞는 행동을 제안해 드려요.")
                    }

                    HStack(spacing: 10) {
                        NavigationLink(destination: RecoveryActionView()) {
                            dashboardAction("직접 1분 호흡", "수동으로 시작", "wind", Theme.mint)
                        }
                        NavigationLink(destination: RecoveryEffectReportView()) {
                            dashboardAction("회복 효과", "이번 주 학습", "chart.xyaxis.line", Theme.accent)
                        }
                    }

                    NavigationLink(destination: AssistantView()) {
                        HStack(spacing: 13) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 42, height: 42)
                                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Morrow AI와 대화")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Watch와 iPhone의 최근 흐름을 함께 살펴봐요")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textMuted)
                        }
                        .padding(13)
                        .morrowPanel(cornerRadius: 15)
                    }

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
                    NavigationLink(destination: SettingsView(onLogout: onLogout)) { Image(systemName: "slider.horizontal.3") }
                }
            }
            .tint(Theme.accent)
            .refreshable { await health.refresh() }
            .task { await health.requestAuthorizationAndLoad() }
            .sheet(item: $recommendedRecovery) { launch in
                RecoveryActionView(launch: launch)
            }
        }
    }

    private func recoveryLaunch(_ recommendation: NativeRecommendation) -> PhoneRecoveryLaunch {
        PhoneRecoveryLaunch(
            action: recommendation.action ?? actionFromTitle(recommendation.title),
            reason: recommendation.rationale,
            confidence: recommendation.source == "AI" ? "AI" : "MEDIUM",
            durationSeconds: recommendationDuration(recommendation),
            attemptId: nil,
            autoStart: false,
            suggestedTitle: recommendation.title
        )
    }

    private func recommendationDuration(_ recommendation: NativeRecommendation) -> Int {
        if let value = recommendation.durationSeconds, value >= 30 { return value }
        let pattern = try? NSRegularExpression(pattern: "(\\d{1,2})\\s*분")
        let range = NSRange(recommendation.title.startIndex..., in: recommendation.title)
        if let match = pattern?.firstMatch(in: recommendation.title, range: range),
           let minuteRange = Range(match.range(at: 1), in: recommendation.title),
           let minutes = Int(recommendation.title[minuteRange]) { return max(1, min(30, minutes)) * 60 }
        return 60
    }

    private func actionFromTitle(_ title: String) -> String {
        if title.contains("멈추") || title.contains("화면") || title.contains("눈을 쉬") { return "SCREEN_BREAK" }
        if title.contains("물") { return "WATER_WALK" }
        if title.contains("걷") || title.contains("걸어") || title.contains("산책") || title.contains("움직") { return "WALK" }
        if title.contains("집중") || title.contains("할 일") { return "FOCUS" }
        if title.contains("스트레칭") || title.contains("어깨") || title.contains("자세") { return "STRETCH" }
        return "BREATH"
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
                Text(syncService.statusText).font(.system(size: 8, weight: .medium, design: .monospaced)).lineLimit(1)
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

    @ViewBuilder private var healthDetailPanel: some View {
        if health.snapshot.sleepSession != nil || !health.snapshot.workouts.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Text("HEALTHKIT DETAILS").morrowKicker()
                if let sleep = health.snapshot.sleepSession, sleep.totalMinutes > 0 {
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "bed.double.fill").foregroundStyle(Color(red: 164 / 255, green: 146 / 255, blue: 238 / 255)).frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("수면 · \(sleep.intervalText)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("코어 \(sleep.coreMinutes)분 · 깊은 \(sleep.deepMinutes)분 · REM \(sleep.remMinutes)분 · 깨어있음 \(sleep.awakeMinutes)분")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                ForEach(health.snapshot.workouts.prefix(3)) { workout in
                    Divider().overlay(Theme.border)
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "figure.run").foregroundStyle(Theme.mint).frame(width: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(workout.activityType) · \(Int(workout.durationMinutes))분 · \(intensityLabel(workout.intensity))")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("\(workout.startAt.formatted(date: .omitted, time: .shortened))–\(workout.endAt.formatted(date: .omitted, time: .shortened)) · 평균 심박 \(Int(workout.averageHeartRate)) · 최대 \(Int(workout.maxHeartRate)) bpm")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Text("운동 강도는 심박과 분당 활동 에너지로 추정한 웰니스 참고값입니다.")
                    .font(.system(size: 9)).foregroundStyle(Theme.textMuted)
            }
            .padding(14)
            .morrowPanel(cornerRadius: 15)
        }
    }

    private func intensityLabel(_ value: String) -> String {
        switch value { case "HIGH": return "높은 강도"; case "MODERATE": return "중간 강도"; default: return "가벼운 강도" }
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

    private func dashboardAction(_ title: String, _ subtitle: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary); Text(subtitle).font(.caption2).foregroundStyle(Theme.textMuted) }
            Spacer()
        }.padding(13).frame(maxWidth: .infinity).morrowPanel(cornerRadius: 14)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(health.authorizationMessage, systemImage: "lock.shield")
            Label("의료 진단이 아닌 일상 웰니스 분석입니다.", systemImage: "info.circle")
        }
        .font(.caption2).foregroundStyle(Theme.textMuted).padding(.top, 4)
    }
}

private struct NativeChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let content: String
}

struct AssistantView: View {
    @State private var messages = [
        NativeChatMessage(role: .assistant, content: "안녕하세요. 최근 건강 흐름이나 일상에서 궁금한 점을 편하게 물어보세요.")
    ]
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var composerFocused: Bool
    private let client = MorrowAPIClient.shared
    private let quickQuestions = ["오늘 컨디션 어때?", "최근 걸음 수 알려줘", "지금 뭘 하면 좋을까?"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    aiContextHeader
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if isSending {
                        HStack(spacing: 7) {
                            ProgressView().tint(Theme.accent)
                            Text("최근 흐름을 살펴보고 있어요")
                        }
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 8)
            }
            .background(Theme.screenBackground.ignoresSafeArea())
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { composer }
        }
        .navigationTitle("Morrow AI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.screenBackground, for: .navigationBar)
        .tint(Theme.accent)
    }

    private var aiContextHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("HEALTH-AWARE ASSISTANT", systemImage: "waveform.path.ecg")
                .morrowKicker()
                .foregroundStyle(Theme.accent)
            Text("허용한 Watch·iPhone 건강 요약과 체크인 기록을 관련 질문에만 사용해요.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(quickQuestions, id: \.self) { question in
                        Button(question) { Task { await send(question) } }
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .background(Theme.elevatedBackground, in: Capsule())
                            .overlay(Capsule().stroke(Theme.border))
                            .disabled(isSending)
                    }
                }
            }
        }
        .padding(14)
        .morrowPanel(cornerRadius: 16)
    }

    private func messageBubble(_ message: NativeChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            Text(message.content)
                .font(.body)
                .foregroundStyle(message.role == .user ? Theme.screenBackground : Theme.textPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(
                    message.role == .user ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.panelGradient),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay {
                    if message.role == .assistant {
                        RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Theme.border)
                    }
                }
            if message.role == .assistant { Spacer(minLength: 42) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            TextField("Morrow에게 물어보세요", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .disabled(isSending)
                .onSubmit { Task { await send(draft) } }
            Button { Task { await send(draft) } } label: {
                Image(systemName: "arrow.up")
                    .font(.headline)
                    .foregroundStyle(Theme.screenBackground)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 13))
            }
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @MainActor
    private func send(_ value: String) async {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSending else { return }
        messages.append(NativeChatMessage(role: .user, content: clean))
        draft = ""
        composerFocused = false
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await client.sendAssistantMessage(clean)
            messages.append(NativeChatMessage(role: .assistant, content: reply.naturalContent))
        } catch {
            messages.append(NativeChatMessage(role: .assistant, content: "지금은 AI 서버에 연결하지 못했어요. 잠시 후 다시 이야기해 주세요."))
        }
    }
}
