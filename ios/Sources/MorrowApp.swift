import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct MorrowApp: App {
    @UIApplicationDelegateAdaptor(MorrowAppDelegate.self) private var appDelegate
    @StateObject private var healthStore = HealthStore()
    @StateObject private var syncService = MorrowSyncService()
    @StateObject private var notificationManager = PhoneNotificationManager()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthStore)
                .environmentObject(syncService)
                .environmentObject(notificationManager)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: CheckInRecord.self)
    }
}

private struct RootView: View {
    private enum SessionState { case checking, signedOut, authenticated }
    @State private var sessionState: SessionState = .checking

    var body: some View {
        Group {
            switch sessionState {
            case .checking:
                ZStack {
                    Theme.screenBackground.ignoresSafeArea()
                    ProgressView("계정 연결 확인 중").tint(Theme.accent).foregroundStyle(Theme.textSecondary)
                }
            case .signedOut:
                DemoLoginView { sessionState = .authenticated }
            case .authenticated:
                AuthenticatedRootView { sessionState = .signedOut }
            }
        }
        .task {
            guard sessionState == .checking else { return }
            sessionState = await MorrowAPIClient.shared.hasStoredCredentials() ? .authenticated : .signedOut
        }
    }
}

private struct DemoLoginView: View {
    @State private var accountId = ""
    @State private var isLoggingIn = false
    @State private var errorMessage = ""
    let onSuccess: () -> Void

    var body: some View {
        ZStack {
            Theme.screenBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Spacer()
                VStack(alignment: .leading, spacing: 7) {
                    Text("MORROW").font(.system(size: 25, weight: .bold, design: .monospaced)).tracking(5).foregroundStyle(Theme.textPrimary)
                    Text("ACCOUNT LOGIN").morrowKicker()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("아이디로 시작하기", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    TextField("아이디", text: $accountId)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .loginField()
                    if !errorMessage.isEmpty {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await login() } } label: {
                        HStack {
                            if isLoggingIn { ProgressView().tint(Theme.screenBackground) }
                            Text(isLoggingIn ? "로그인 중" : "로그인")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundStyle(Theme.screenBackground)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isLoggingIn || accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(18)
                .morrowPanel(cornerRadius: 20)
                Text("처음에는 아이디만 입력합니다. 웹 연결 코드는 로그인 후 설정에서 한 번만 연결하세요.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(22)
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func login() async {
        isLoggingIn = true
        errorMessage = ""
        defer { isLoggingIn = false }
        do {
            _ = try await MorrowAPIClient.shared.login(accountId: accountId.trimmingCharacters(in: .whitespacesAndNewlines))
            onSuccess()
        } catch {
            errorMessage = "아이디를 확인하거나 잠시 후 다시 시도해 주세요."
        }
    }
}

private extension View {
    func loginField() -> some View {
        padding(.horizontal, 14)
            .frame(height: 50)
            .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border))
            .foregroundStyle(Theme.textPrimary)
    }
}

private struct AuthenticatedRootView: View {
    let onLogout: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var healthStore: HealthStore
    @EnvironmentObject private var syncService: MorrowSyncService
    @EnvironmentObject private var notificationManager: PhoneNotificationManager
    @Query(sort: \CheckInRecord.recordedAt, order: .reverse) private var checkIns: [CheckInRecord]
    @AppStorage("morrow.sync.derivedHealth") private var syncDerivedHealth = true
    @AppStorage("morrow.notifications.enabled") private var notificationsEnabled = true
    @StateObject private var watchReceiver = WatchSessionReceiver()
    private let analyzer = BaselineAnalyzer()

    var body: some View {
        DashboardView(onLogout: logout)
            .onAppear {
                watchReceiver.activate(); importWatchCheckIns(); syncWatchContext()
                Task { await configureNotifications(); await synchronize() }
            }
            .onChange(of: watchReceiver.inboxVersion) { _, _ in importWatchCheckIns() }
            .onChange(of: watchReceiver.healthInboxVersion) { _, _ in importWatchHealth() }
            .onChange(of: healthSignature) { _, _ in syncWatchContext(); Task { await synchronize() } }
            .onChange(of: checkInSignature) { _, _ in Task { await synchronize() } }
            .onChange(of: syncService.recoveryScore) { _, _ in syncWatchContext() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { importWatchCheckIns(); syncWatchContext(); Task { await synchronize() } } }
    }

    @MainActor
    private func logout() async {
        await MorrowAPIClient.shared.logout()
        notificationManager.disable()
        watchReceiver.sendLogoutContext()
        onLogout()
    }

    private func importWatchCheckIns() {
        for incoming in watchReceiver.drain() {
            guard !checkIns.contains(where: { $0.id == incoming.eventId }) else { continue }
            guard let status = WellnessStatus(rawValue: incoming.status) else { continue }
            let cause = incoming.cause.flatMap(WellnessCause.init(rawValue:))
            modelContext.insert(CheckInRecord(id: incoming.eventId, status: status, cause: cause, source: .watch, recordedAt: incoming.recordedAt))
        }
        try? modelContext.save()
        Task { await synchronize() }
    }

    private func importWatchHealth() {
        guard syncDerivedHealth else { _ = watchReceiver.drainHealthSummaries(); return }
        let summaries = watchReceiver.drainHealthSummaries()
        guard let latest = summaries.max(by: { $0.recordedAt < $1.recordedAt }) else { return }
        Task { await syncService.synchronizeWatch(latest) }
    }

    private var healthSignature: String {
        "\(healthStore.snapshot.sleepMinutes)-\(healthStore.snapshot.hrv)-\(healthStore.snapshot.restingHeartRate)-\(healthStore.snapshot.steps)-\(healthStore.snapshot.activeEnergyKcal)-\(healthStore.snapshot.exerciseMinutes)"
    }

    private var checkInSignature: String { checkIns.map { $0.id.uuidString }.joined(separator: "-") }

    private func syncWatchContext() {
        let result = analyzer.analyze(current: healthStore.snapshot)
        let score = syncService.recoveryScore ?? result.score
        watchReceiver.sendWellnessContext(
            score: score,
            summary: RecoveryLevel(score: score).label,
            snapshot: healthStore.snapshot,
            recommendation: syncService.currentRecommendation?.title ?? "지금 상태를 기록하면 맞춤 행동을 제안해요"
        )
        Task {
            if let connection = try? await MorrowAPIClient.shared.connectionContext() {
                watchReceiver.sendConnectionContext(apiRoot: connection.apiRoot, credentials: connection.credentials)
            }
        }
    }

    private func synchronize() async {
        await syncService.synchronize(checkIns: checkIns, snapshot: syncDerivedHealth ? healthStore.snapshot : nil, modelContext: modelContext)
        guard notificationsEnabled, let insight = await notificationManager.evaluateAIInsight() else { return }
        watchReceiver.sendAIInsight(title: insight.title, body: insight.body, generatedAt: .now)
    }

    private func configureNotifications() async {
        guard notificationsEnabled else { return }
        await notificationManager.requestAuthorization()
        await notificationManager.scheduleDailyCheckIns()
    }

}

@MainActor
final class MorrowSyncService: ObservableObject {
    enum State { case idle, syncing, synced(Date), failed(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var recoveryScore: Int?
    @Published private(set) var currentRecommendation: NativeRecommendation?
    private let client = MorrowAPIClient.shared

    var statusText: String {
        switch state {
        case .idle: return "동기화 대기"
        case .syncing: return "폰 · 워치 · 웹 동기화 중"
        case .synced(let date): return "웹 동기화 · \(date.formatted(date: .omitted, time: .shortened))"
        case .failed: return "서버 연결 필요"
        }
    }

    func synchronize(checkIns: [CheckInRecord], snapshot: HealthSnapshot?, modelContext: ModelContext) async {
        state = .syncing
        do {
            for record in checkIns where !record.isSynced { try await upload(record) }
            if let snapshot, snapshot.hasHealthData { try await upload(snapshot) }
            try await mergeServerCheckIns(into: checkIns, modelContext: modelContext)
            let dashboard = try await client.dashboard()
            recoveryScore = dashboard.score
            currentRecommendation = dashboard.recommendation
            try? modelContext.save()
            state = .synced(.now)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func synchronizeWatch(_ summary: IncomingWatchHealthSummary) async {
        state = .syncing
        do {
            let credentials = try await client.credentials()
            let bucket = Int(summary.recordedAt.timeIntervalSince1970 / 300)
            let payload = HealthPayload(
                userId: credentials.userId, clientSnapshotId: "watch-\(bucket)", source: "WATCH", sleepMinutes: 0,
                heartRate: summary.heartRate, restingHeartRate: 0, hrv: summary.hrv, steps: summary.steps,
                activeEnergyKcal: summary.activeEnergyKcal, exerciseMinutes: summary.exerciseMinutes,
                distanceMeters: 0, flightsClimbed: 0, respiratoryRate: 0, oxygenSaturationPercent: 0,
                recordedAt: summary.recordedAt
            )
            try await post(payload, path: "health/snapshots")
            let dashboard = try await client.dashboard()
            recoveryScore = dashboard.score
            currentRecommendation = dashboard.recommendation
            state = .synced(.now)
        } catch { state = .failed(error.localizedDescription) }
    }

    private func upload(_ record: CheckInRecord) async throws {
        let credentials = try await client.credentials()
        let payload = CheckInPayload(
            userId: credentials.userId, clientEventId: record.id.uuidString,
            status: record.status.apiValue, cause: record.cause?.apiValue,
            note: record.note, source: record.source == .watch ? "WATCH" : "IPHONE", recordedAt: record.recordedAt
        )
        let saved = try await client.createCheckIn(payload)
        record.serverId = saved.id
        record.isSynced = true
    }

    private func upload(_ snapshot: HealthSnapshot) async throws {
        let credentials = try await client.credentials()
        let bucket = Int(Date().timeIntervalSince1970 / 300)
        let payload = HealthPayload(
            userId: credentials.userId, clientSnapshotId: "iphone-\(bucket)", source: "IPHONE",
            sleepMinutes: snapshot.sleepMinutes, heartRate: snapshot.heartRate, restingHeartRate: snapshot.restingHeartRate,
            hrv: snapshot.hrv, steps: snapshot.steps, activeEnergyKcal: snapshot.activeEnergyKcal,
            exerciseMinutes: snapshot.exerciseMinutes, distanceMeters: snapshot.distanceMeters,
            flightsClimbed: snapshot.flightsClimbed, respiratoryRate: snapshot.respiratoryRate,
            oxygenSaturationPercent: snapshot.oxygenSaturationPercent, recordedAt: .now
        )
        try await post(payload, path: "health/snapshots")
    }

    private func post<T: Encodable>(_ value: T, path: String) async throws {
        try await client.send(value, path: path)
    }

    private func mergeServerCheckIns(into local: [CheckInRecord], modelContext: ModelContext) async throws {
        let remote = try await client.checkIns()
        let remoteIds = Set(remote.map(\.id))
        for value in remote {
            let matched = local.first(where: { $0.serverId == value.id || $0.id.uuidString == value.clientEventId })
            if let matched {
                matched.serverId = value.id
                matched.isSynced = true
                continue
            }
            guard let status = WellnessStatus(apiValue: value.status) else { continue }
            let record = CheckInRecord(
                id: value.clientEventId.flatMap(UUID.init(uuidString:)) ?? UUID(),
                status: status,
                cause: value.cause.flatMap(WellnessCause.init(apiValue:)),
                note: value.note,
                source: CheckInSource(apiValue: value.source),
                recordedAt: value.date,
                serverId: value.id,
                isSynced: true
            )
            modelContext.insert(record)
        }
        for record in local where record.isSynced && record.serverId != nil && !remoteIds.contains(record.serverId!) {
            modelContext.delete(record)
        }
    }

    private struct CheckInPayload: Encodable { let userId, clientEventId, status: String; let cause: String?; let note, source: String; let recordedAt: Date }
    private struct HealthPayload: Encodable { let userId, clientSnapshotId, source: String; let sleepMinutes: Int; let heartRate, restingHeartRate, hrv, steps, activeEnergyKcal, exerciseMinutes, distanceMeters, flightsClimbed, respiratoryRate, oxygenSaturationPercent: Double; let recordedAt: Date }
}

private extension WellnessStatus {
    var apiValue: String { switch self { case .ok: "OK"; case .tense: "TENSE"; case .tired: "TIRED"; case .lowFocus: "LOW_FOCUS"; case .uncomfortable: "UNCOMFORTABLE" } }
    init?(apiValue: String) { switch apiValue { case "OK": self = .ok; case "TENSE": self = .tense; case "TIRED": self = .tired; case "LOW_FOCUS": self = .lowFocus; case "UNCOMFORTABLE": self = .uncomfortable; default: return nil } }
}

private extension WellnessCause {
    var apiValue: String { switch self { case .sleep: "SLEEP"; case .work: "WORK"; case .study: "STUDY"; case .relationship: "RELATIONSHIP"; case .physical: "PHYSICAL"; case .unknown: "UNKNOWN" } }
    init?(apiValue: String) { switch apiValue { case "SLEEP": self = .sleep; case "WORK": self = .work; case "STUDY": self = .study; case "RELATIONSHIP": self = .relationship; case "PHYSICAL": self = .physical; case "UNKNOWN": self = .unknown; default: return nil } }
}

private extension CheckInSource {
    init(apiValue: String) { switch apiValue { case "WATCH": self = .watch; case "WEB": self = .web; default: self = .iPhone } }
}

@MainActor
final class PhoneNotificationManager: ObservableObject {
    @Published private(set) var statusText = "알림 권한 확인 전"
    private let center = UNUserNotificationCenter.current()
    private let analysisKey = "morrow.notifications.ai.lastAnalysis"
    private let notificationKey = "morrow.notifications.ai.lastDelivery"

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            statusText = granted ? "iPhone 알림 켜짐" : "iPhone 설정에서 알림을 허용해 주세요"
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch { statusText = "알림 권한을 확인할 수 없습니다" }
    }

    func scheduleDailyCheckIns() async {
        let old = ["morrow.checkin.morning", "morrow.checkin.evening"]
        let weekly = (1...7).flatMap { ["morrow.phone.action.morning.\($0)", "morrow.phone.action.evening.\($0)"] }
        center.removePendingNotificationRequests(withIdentifiers: old + weekly)
        let morning = ["물 한 잔과 30초 체크인", "창가에서 30초 햇빛 보기", "어깨 세 번 돌리고 길게 내쉬기", "할 일 하나만 골라 10분 시작", "가까운 곳까지 3분 걷기", "물 한 잔 뒤 몸 상태 확인", "1분 호흡으로 천천히 시작"]
        let evening = ["화면을 5분 내려놓기", "길게 내쉬는 호흡 여섯 번", "목과 어깨 3분 스트레칭", "도움 된 회복 행동 하나 기록", "잠들기 전 물 한 모금", "5분 천천히 걷고 마무리", "다음 주를 위한 30초 체크인"]
        for weekday in 1...7 {
            await scheduleWeekly(identifier: "morrow.phone.action.morning.\(weekday)", weekday: weekday, hour: 10, minute: 0, title: "지금 바로 해볼 한 가지", body: morning[weekday - 1])
            await scheduleWeekly(identifier: "morrow.phone.action.evening.\(weekday)", weekday: weekday, hour: 20, minute: 30, title: "오늘의 회복 행동", body: evening[weekday - 1])
        }
    }

    func scheduleRecoveryAlertIfNeeded(load: Int, summary: String) async {
        guard load >= 70 else { return }
        let key = "morrow.notifications.lastRecovery"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 6 * 60 * 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = summary
        content.body = "회복 부하가 높아요. 7분 가볍게 걷거나 1분 호흡으로 리듬을 낮춰보세요."
        content.sound = .default
        content.categoryIdentifier = "MORROW_ACTION"
        try? await center.add(UNNotificationRequest(identifier: "morrow.recovery", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func evaluateAIInsight() async -> AIProactiveInsight? {
        let lastAnalysis = UserDefaults.standard.object(forKey: analysisKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAnalysis) > 90 * 60 else { return nil }
        UserDefaults.standard.set(Date(), forKey: analysisKey)
        guard let insight = try? await MorrowAPIClient.shared.proactiveInsight(), insight.shouldNotify else { return nil }

        let lastDelivery = UserDefaults.standard.object(forKey: notificationKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastDelivery) > 6 * 60 * 60 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = insight.title
        content.body = insight.body
        content.sound = .default
        content.userInfo = ["type": "AI_INSIGHT", "reason": insight.reason]
        content.categoryIdentifier = "MORROW_ACTION"
        let request = UNNotificationRequest(
            identifier: "morrow.ai.insight.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        do {
            try await center.add(request)
        } catch {
            return nil
        }
        UserDefaults.standard.set(Date(), forKey: notificationKey)
        return insight
    }

    func disable() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        UIApplication.shared.unregisterForRemoteNotifications()
        statusText = "Morrow 알림 꺼짐"
    }

    private func scheduleDaily(identifier: String, hour: Int, minute: Int, title: String, body: String) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func scheduleWeekly(identifier: String, weekday: Int, hour: Int, minute: Int, title: String, body: String) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default; content.categoryIdentifier = "MORROW_ACTION"
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(weekday: weekday, hour: hour, minute: minute), repeats: true)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
