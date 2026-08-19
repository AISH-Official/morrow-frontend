import SwiftUI
import WatchKit

private enum WatchTheme {
    static let accent = Color(red: 103 / 255, green: 222 / 255, blue: 241 / 255)
    static let mint = Color(red: 91 / 255, green: 222 / 255, blue: 172 / 255)
    static let panel = Color(red: 7 / 255, green: 23 / 255, blue: 31 / 255)
    static let border = accent.opacity(0.2)
    static let muted = Color(red: 105 / 255, green: 139 / 255, blue: 148 / 255)
}

enum WatchStatus: String, CaseIterable, Identifiable {
    case ok = "정상", tense = "긴장", tired = "피로", lowFocus = "집중 저하"
    var id: String { rawValue }
    var icon: String { switch self { case .ok: "face.smiling"; case .tense: "bolt.heart"; case .tired: "moon.zzz"; case .lowFocus: "cloud.fog" } }
    var tint: Color { switch self { case .ok: WatchTheme.mint; case .tense: .orange; case .tired: WatchTheme.accent; case .lowFocus: .purple } }
}

enum WatchCause: String, CaseIterable, Identifiable {
    case sleep = "수면", work = "업무", study = "학업", relationship = "관계", physical = "신체", unknown = "잘 모르겠음"
    var id: String { rawValue }
    var icon: String { switch self { case .sleep: "bed.double.fill"; case .work: "briefcase.fill"; case .study: "book.fill"; case .relationship: "person.2.fill"; case .physical: "figure.walk"; case .unknown: "ellipsis.circle.fill" } }
}

struct WatchCheckInView: View {
    @EnvironmentObject private var session: WatchSessionManager
    @EnvironmentObject private var health: WatchHealthStore
    @EnvironmentObject private var notifications: WatchNotificationManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationPath: [String] = []

    var body: some View {
        NavigationStack(path: $notificationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    brandHeader
                    recoveryHero
                    signalGrid
                    recommendation
                    actionGrid
                    recentCheckIn
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 12)
            }
            .containerBackground(.black, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { route in
                if route == "RECOVERY" { RecoverySessionView(autoStart: true, launch: .pending()) }
                else { QuickCheckInView() }
            }
        }
        .tint(WatchTheme.accent)
        .task {
            await health.requestAuthorizationAndLoad()
            _ = await health.synchronizeCurrentSnapshot()
            await notifications.configure()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                openPendingNotificationAction()
                Task { _ = await health.refreshFromBackground() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("morrow.watch.action"))) { _ in openPendingNotificationAction() }
        .onAppear { openPendingNotificationAction() }
        .onOpenURL { url in if url.host == "recovery" { notificationPath = ["RECOVERY"] } }
    }

    private func openPendingNotificationAction() {
        guard let action = UserDefaults.standard.string(forKey: "morrow.watch.pendingAction") else { return }
        UserDefaults.standard.removeObject(forKey: "morrow.watch.pendingAction")
        notificationPath = [action]
    }

    private var brandHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("MORROW").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                Text("WELLNESS INTELLIGENCE").font(.system(size: 6, design: .monospaced)).tracking(0.8).foregroundStyle(WatchTheme.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(session.isServerConnected ? WatchTheme.mint : .orange).frame(width: 6, height: 6).shadow(color: session.isServerConnected ? WatchTheme.mint : .orange, radius: 4)
                Text(session.isServerConnected ? "CLOUD" : session.isConnected ? "PHONE" : "LOCAL").font(.system(size: 6, weight: .medium, design: .monospaced)).foregroundStyle(WatchTheme.muted)
            }
        }
    }

    private var recoveryHero: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(WatchTheme.accent.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: Double(session.context.score) / 100).stroke(WatchTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90)).shadow(color: WatchTheme.accent.opacity(0.35), radius: 5)
                Text("\(session.context.score)").font(.system(size: 22, weight: .medium, design: .monospaced))
            }
            .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text("RECOVERY LOAD").font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(WatchTheme.muted)
                Text(session.context.summary).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10).background(WatchTheme.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(WatchTheme.border))
    }

    private var signalGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            miniSignal("수면", session.context.sleep, "bed.double.fill")
            miniSignal("HRV", health.snapshot.hrv > 0 ? "\(Int(health.snapshot.hrv)) ms" : session.context.hrv, "waveform.path.ecg")
            miniSignal("심박", health.snapshot.heartRate > 0 ? "\(Int(health.snapshot.heartRate)) bpm" : session.context.heart, "heart.fill")
            miniSignal("걸음", health.snapshot.steps > 0 ? formatted(health.snapshot.steps) : session.context.steps, "figure.walk")
            miniSignal("활동", health.snapshot.activeEnergyKcal > 0 ? "\(Int(health.snapshot.activeEnergyKcal)) kcal" : session.context.energy, "flame.fill")
            miniSignal("운동", health.snapshot.exerciseMinutes > 0 ? "\(Int(health.snapshot.exerciseMinutes))분" : session.context.exercise, "figure.run")
        }
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))"
    }

    private func miniSignal(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundStyle(WatchTheme.accent)
            Text(title).font(.system(size: 7, design: .monospaced)).foregroundStyle(WatchTheme.muted)
            Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(7).background(WatchTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var recommendation: some View {
        Group {
            if session.context.recommendationAction.isEmpty {
                recommendationContent
            } else {
                NavigationLink(destination: RecoverySessionView(launch: .recommended(session.context))) {
                    recommendationContent
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(LinearGradient(colors: [WatchTheme.accent.opacity(0.18), WatchTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(WatchTheme.border))
    }

    private var recommendationContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label("NEXT BEST ACTION", systemImage: "sparkles").font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(WatchTheme.accent)
                Spacer()
                if !session.context.recommendationAction.isEmpty { Image(systemName: "play.circle.fill").foregroundStyle(WatchTheme.mint) }
            }
            Text(session.context.recommendation).font(.system(size: 13, weight: .semibold))
            if session.context.recommendationDuration > 0 {
                Text("\(session.context.recommendationSource == "AI" ? "AI 맞춤" : "개인화") · \(max(1, session.context.recommendationDuration / 60))분")
                    .font(.system(size: 7, design: .monospaced)).foregroundStyle(WatchTheme.muted)
            }
        }
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
            NavigationLink(destination: QuickCheckInView()) { action("체크인", "plus.circle.fill", WatchTheme.accent) }.buttonStyle(.plain)
            NavigationLink(destination: RecoverySessionView(launch: .breath)) { action("1분 회복", "wind", WatchTheme.mint) }.buttonStyle(.plain)
            NavigationLink(destination: WatchAssistantView()) { action("AI 대화", "sparkles", WatchTheme.accent) }.buttonStyle(.plain)
            Button {
                Task { await health.requestAuthorizationAndLoad(); _ = await health.synchronizeCurrentSnapshot() }
            } label: { action("데이터 갱신", "arrow.clockwise.heart.fill", .orange) }.buttonStyle(.plain)
            NavigationLink(destination: WatchNotificationSettingsView()) { action("알림", "bell.badge.fill", .purple) }.buttonStyle(.plain)
        }
    }

    private func action(_ title: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 6) { Image(systemName: icon).font(.title3).foregroundStyle(tint); Text(title).font(.caption2.weight(.semibold)) }
            .frame(maxWidth: .infinity).frame(height: 58).background(WatchTheme.panel, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(tint.opacity(0.2)))
    }

    @ViewBuilder private var recentCheckIn: some View {
        if let recent = session.recentCheckIn {
            HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(WatchTheme.mint); VStack(alignment: .leading) { Text("최근 \(recent.status) · \(recent.cause)").font(.caption2.weight(.semibold)); Text(recent.recordedAt.formatted(date: .omitted, time: .shortened)).font(.system(size: 8, design: .monospaced)).foregroundStyle(WatchTheme.muted) }; Spacer() }
                .padding(9).background(WatchTheme.panel, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct WatchNotificationSettingsView: View {
    @EnvironmentObject private var notifications: WatchNotificationManager
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "bell.badge.fill").font(.system(size: 32)).foregroundStyle(WatchTheme.accent)
                Text(notifications.statusText).font(.headline).multilineTextAlignment(.center)
                Text("매일 체크인과 AI가 최근 흐름에서 필요하다고 판단한 맞춤 알림을 Watch에서 받아요.").font(.caption2).foregroundStyle(WatchTheme.muted).multilineTextAlignment(.center)
                Button("알림 다시 설정") { Task { await notifications.configure() } }.buttonStyle(.borderedProminent).tint(WatchTheme.accent)
            }.padding(.vertical, 10)
        }.navigationTitle("알림")
    }
}

private struct WatchAIMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let content: String
}

private struct WatchAssistantView: View {
    @EnvironmentObject private var session: WatchSessionManager
    @State private var question = ""
    @State private var isSending = false
    @State private var messages = [
        WatchAIMessage(role: .assistant, content: "최근 건강 흐름에 대해 무엇이든 물어보세요.")
    ]
    private let suggestions = ["지금 컨디션은?", "걸음 수 알려줘", "회복 방법 추천해줘"]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    connectionBadge
                    ForEach(messages.suffix(6)) { message in
                        Text(message.content)
                            .font(.caption2)
                            .foregroundStyle(message.role == .user ? .black : .white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                            .background(message.role == .user ? WatchTheme.accent : WatchTheme.panel, in: RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(message.role == .user ? .clear : WatchTheme.border))
                            .id(message.id)
                    }
                    if isSending {
                        HStack { ProgressView(); Text("분석 중").font(.caption2).foregroundStyle(WatchTheme.muted) }
                    }
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { Task { await send(suggestion) } }
                            .buttonStyle(.bordered)
                            .tint(WatchTheme.accent)
                            .disabled(isSending || !session.isServerConnected)
                    }
                    HStack {
                        TextField("질문 입력", text: $question)
                        Button { Task { await send(question) } } label: { Image(systemName: "arrow.up.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(WatchTheme.accent)
                            .disabled(isSending || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.isServerConnected)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .navigationTitle("Morrow AI")
    }

    private var connectionBadge: some View {
        Label(session.isServerConnected ? "AI CLOUD 연결됨" : "iPhone에서 계정 연결 필요", systemImage: session.isServerConnected ? "cloud.fill" : "iphone.slash")
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(session.isServerConnected ? WatchTheme.mint : .orange)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchTheme.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    @MainActor
    private func send(_ value: String) async {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSending, session.isServerConnected else { return }
        messages.append(WatchAIMessage(role: .user, content: clean))
        question = ""
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await WatchAssistantClient.shared.send(clean)
            messages.append(WatchAIMessage(role: .assistant, content: reply.naturalContent))
            WKInterfaceDevice.current().play(.success)
        } catch {
            messages.append(WatchAIMessage(role: .assistant, content: "지금은 AI에 연결하지 못했어요. iPhone 연결을 확인해 주세요."))
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

private struct QuickCheckInView: View {
    @EnvironmentObject private var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStatus: WatchStatus?
    @State private var savedCause: WatchCause?
    @State private var showSaved = false

    var body: some View {
        Group { if let selectedStatus { causeList(for: selectedStatus) } else { statusList } }
            .navigationTitle(selectedStatus == nil ? "지금 상태" : "주요 원인")
            .overlay { if showSaved, let status = selectedStatus, let cause = savedCause { savedOverlay(status, cause) } }
    }

    private var statusList: some View {
        List(WatchStatus.allCases) { status in
            Button { selectedStatus = status; WKInterfaceDevice.current().play(.click) } label: {
                HStack { Image(systemName: status.icon).foregroundStyle(status.tint).frame(width: 26); Text(status.rawValue); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(WatchTheme.muted) }
            }
            .listRowBackground(WatchTheme.panel)
        }
    }

    private func causeList(for status: WatchStatus) -> some View {
        List(WatchCause.allCases) { cause in
            Button { save(status, cause) } label: { HStack { Image(systemName: cause.icon).foregroundStyle(status.tint).frame(width: 26); Text(cause.rawValue); Spacer() } }.listRowBackground(WatchTheme.panel)
        }
    }

    private func save(_ status: WatchStatus, _ cause: WatchCause) {
        savedCause = cause; session.send(status: status.rawValue, cause: cause.rawValue); WKInterfaceDevice.current().play(.success)
        withAnimation { showSaved = true }
        Task { try? await Task.sleep(for: .seconds(1.2)); dismiss() }
    }

    private func savedOverlay(_ status: WatchStatus, _ cause: WatchCause) -> some View {
        VStack(spacing: 8) { Image(systemName: "checkmark.circle.fill").font(.system(size: 38)).foregroundStyle(status.tint); Text("\(status.rawValue) 기록됨").font(.headline); Text("\(cause.rawValue) · iPhone 동기화").font(.caption2).foregroundStyle(WatchTheme.muted) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.94))
    }
}

private struct RecoveryLaunchContext {
    let action: String
    let reason: String
    let confidence: String
    let durationSeconds: Int
    let attemptId: UUID?
    var suggestedTitle: String? = nil

    static let breath = RecoveryLaunchContext(action: "BREATH", reason: "지금 손목에서 시작한 1분 회복이에요.", confidence: "USER", durationSeconds: 60, attemptId: nil)
    static func pending() -> RecoveryLaunchContext {
        let defaults = UserDefaults.standard
        let storedDuration = defaults.integer(forKey: "morrow.watch.recovery.duration")
        let value = RecoveryLaunchContext(
            action: defaults.string(forKey: "morrow.watch.recovery.action") ?? "BREATH",
            reason: defaults.string(forKey: "morrow.watch.recovery.reason") ?? "최근 흐름에 맞춰 제안한 회복 행동이에요.",
            confidence: defaults.string(forKey: "morrow.watch.recovery.confidence") ?? "LOW",
            durationSeconds: storedDuration > 0 ? max(30, storedDuration) : 60,
            attemptId: defaults.string(forKey: "morrow.watch.recovery.attemptId").flatMap(UUID.init(uuidString:))
        )
        ["morrow.watch.recovery.action", "morrow.watch.recovery.reason", "morrow.watch.recovery.confidence", "morrow.watch.recovery.duration", "morrow.watch.recovery.attemptId"].forEach { defaults.removeObject(forKey: $0) }
        return value
    }
    static func recommended(_ context: WatchWellnessContext) -> RecoveryLaunchContext {
        RecoveryLaunchContext(
            action: context.recommendationAction,
            reason: context.recommendationReason.isEmpty ? "최근 흐름에 맞춰 제안한 회복 행동이에요." : context.recommendationReason,
            confidence: context.recommendationSource == "AI" ? "AI" : "MEDIUM",
            durationSeconds: max(30, context.recommendationDuration),
            attemptId: nil,
            suggestedTitle: context.recommendation
        )
    }
    var title: String {
        if let suggestedTitle, !suggestedTitle.isEmpty { return suggestedTitle }
        let duration = max(1, durationSeconds / 60)
        return switch action { case "WALK": "\(duration)분 걷기"; case "WATER_WALK": "\(duration)분 물 한 잔 + 걷기"; case "STRETCH": "\(duration)분 스트레칭"; case "FOCUS": "\(duration)분 집중"; case "SCREEN_BREAK": "\(duration)분 잠시 멈추기"; default: "\(duration)분 호흡" }
    }
    var icon: String { switch action { case "WALK", "WATER_WALK": "figure.walk"; case "STRETCH": "figure.flexibility"; case "FOCUS": "scope"; case "SCREEN_BREAK": "eye"; default: "wind" } }
    var cue: String { switch action { case "WALK": "편한 속도로 걷기"; case "WATER_WALK": "물 한 잔 뒤 천천히 걷기"; case "STRETCH": "목과 어깨 천천히 풀기"; case "FOCUS": "한 가지 일만 시작하기"; case "SCREEN_BREAK": "화면과 하던 일을 잠시 멈추기"; default: "길게 내쉬기" } }
}

private struct RecoverySessionView: View {
    let autoStart: Bool
    let launch: RecoveryLaunchContext
    @State private var remaining: Int
    @State private var running = false
    @State private var attemptId: UUID?
    @State private var resultMessage = ""
    @State private var isSubmitting = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(autoStart: Bool = false, launch: RecoveryLaunchContext = .breath) {
        self.autoStart = autoStart
        self.launch = launch
        _remaining = State(initialValue: max(30, launch.durationSeconds))
        _attemptId = State(initialValue: launch.attemptId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Label(launch.title, systemImage: launch.icon).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(WatchTheme.mint)
                Text(launch.reason).font(.system(size: 9)).foregroundStyle(WatchTheme.muted).multilineTextAlignment(.center).lineLimit(3)
                ZStack {
                    Circle().stroke(WatchTheme.mint.opacity(0.12), lineWidth: 9)
                    Circle().trim(from: 0, to: progress).stroke(WatchTheme.mint, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.linear, value: remaining)
                    VStack { Text(timeText).font(.system(size: 25, weight: .medium, design: .monospaced)); Text(running ? activeCue : launch.title).font(.caption2).foregroundStyle(WatchTheme.muted).multilineTextAlignment(.center).lineLimit(2) }
                }.frame(width: 108, height: 108)
                if remaining > 0 {
                    Button(running ? "잠시 멈춤" : "시작") { running.toggle(); WKInterfaceDevice.current().play(.click) }.buttonStyle(.borderedProminent).tint(WatchTheme.mint)
                } else if resultMessage.isEmpty {
                    Text("조금 나아졌나요?").font(.headline)
                    HStack(spacing: 5) {
                        outcomeButton("나아짐", "IMPROVED", WatchTheme.mint)
                        outcomeButton("그대로", "SAME", WatchTheme.accent)
                        outcomeButton("불편", "WORSE", .orange)
                    }
                } else {
                    Label(resultMessage, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(WatchTheme.mint).multilineTextAlignment(.center)
                }
            }
        }
        .onReceive(timer) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { running = false; WKInterfaceDevice.current().play(.success) }
            else if launch.action == "BREATH", remaining % 4 == 0 { WKInterfaceDevice.current().play(.directionUp) }
        }
        .task { await prepareAttempt(); if autoStart { running = true } }
        .navigationTitle(launch.title)
    }

    private var progress: Double { Double(max(0, launch.durationSeconds - remaining)) / Double(max(1, launch.durationSeconds)) }
    private var timeText: String { String(format: "%d:%02d", remaining / 60, remaining % 60) }
    private var activeCue: String { launch.action == "BREATH" ? (((launch.durationSeconds - remaining) / 4).isMultiple(of: 2) ? "천천히 들이쉬기" : "길게 내쉬기") : launch.cue }
    private func outcomeButton(_ title: String, _ outcome: String, _ tint: Color) -> some View {
        Button(title) { Task { await submit(outcome) } }.buttonStyle(.bordered).tint(tint).font(.system(size: 9)).disabled(isSubmitting)
    }
    @MainActor private func prepareAttempt() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if let attemptId { _ = try await WatchRecoveryClient.shared.start(id: attemptId) }
            else { attemptId = try await WatchRecoveryClient.shared.create(action: launch.action, reason: launch.reason, confidence: launch.confidence).id }
        } catch {}
    }
    @MainActor private func submit(_ outcome: String) async {
        isSubmitting = true
        defer { isSubmitting = false }
        if let attemptId { _ = try? await WatchRecoveryClient.shared.complete(id: attemptId, outcome: outcome) }
        resultMessage = outcome == "IMPROVED" ? "이 방법을 다음에도 우선할게요" : outcome == "SAME" ? "다음에는 다른 방법을 시험할게요" : "이 행동은 다음 추천에서 피할게요"
        WKInterfaceDevice.current().play(outcome == "IMPROVED" ? .success : .click)
    }
}
