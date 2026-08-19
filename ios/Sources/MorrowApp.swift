import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct MorrowApp: App {
    @UIApplicationDelegateAdaptor(MorrowAppDelegate.self) private var appDelegate
    @StateObject private var healthStore = HealthStore.shared
    @StateObject private var syncService = MorrowSyncService.shared
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
                AccountAccessView { sessionState = .authenticated }
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

private struct AccountAccessView: View {
    @State private var isSignup = false
    @State private var accountId = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
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
                    Text(isSignup ? "CREATE ACCOUNT" : "ACCOUNT LOGIN").morrowKicker()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Picker("계정", selection: $isSignup) {
                        Text("로그인").tag(false)
                        Text("회원가입").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isSignup) { _, _ in
                        password = ""
                        passwordConfirmation = ""
                        errorMessage = ""
                    }
                    Label(isSignup ? "나만의 계정 만들기" : "내 계정으로 연결하기", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    TextField("아이디", text: $accountId)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .loginField()
                    SecureField("비밀번호 8자 이상", text: $password)
                        .textContentType(isSignup ? .newPassword : .password)
                        .loginField()
                    if isSignup {
                        SecureField("비밀번호 확인", text: $passwordConfirmation)
                            .textContentType(.newPassword)
                            .loginField()
                    }
                    if !errorMessage.isEmpty {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                    Button { Task { await submit() } } label: {
                        HStack {
                            if isLoggingIn { ProgressView().tint(Theme.screenBackground) }
                            Text(isLoggingIn ? "계정 확인 중" : isSignup ? "계정 만들기" : "로그인")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundStyle(Theme.screenBackground)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isLoggingIn || accountId.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || password.count < 8 || (isSignup && passwordConfirmation.count < 8))
                }
                .padding(18)
                .morrowPanel(cornerRadius: 20)
                Text(isSignup ? "새 계정의 건강 기록은 다른 사용자와 분리됩니다. 기존 테스트 계정은 그대로 유지됩니다." : "기존 테스트 계정을 포함해 가입한 계정으로 로그인할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                Spacer()
            }
            .padding(22)
        }
        .preferredColorScheme(.dark)
    }

    @MainActor
    private func submit() async {
        isLoggingIn = true
        errorMessage = ""
        defer { isLoggingIn = false }
        if isSignup && password != passwordConfirmation {
            errorMessage = "비밀번호 확인이 일치하지 않습니다."
            return
        }
        do {
            let cleanAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSignup {
                _ = try await MorrowAPIClient.shared.signup(accountId: cleanAccountId, password: password)
            } else {
                _ = try await MorrowAPIClient.shared.login(accountId: cleanAccountId, password: password)
            }
            onSuccess()
        } catch {
            errorMessage = isSignup ? "이미 사용 중인 아이디인지 확인해 주세요." : "아이디 또는 비밀번호를 확인해 주세요."
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
    @State private var pendingRecovery: PhoneRecoveryLaunch?
    @State private var showNotificationCheckIn = false
    private let analyzer = BaselineAnalyzer()

    var body: some View {
        DashboardView(onLogout: logout)
            .onAppear {
                watchReceiver.activate(); importWatchCheckIns(); syncWatchContext(); handlePendingNotificationAction()
                Task { await configureNotifications(); await synchronize() }
            }
            .onChange(of: watchReceiver.inboxVersion) { _, _ in importWatchCheckIns() }
            .onChange(of: watchReceiver.healthInboxVersion) { _, _ in importWatchHealth() }
            .onChange(of: healthSignature) { _, _ in syncWatchContext(); Task { await synchronize() } }
            .onChange(of: checkInSignature) { _, _ in Task { await synchronize() } }
            .onChange(of: syncService.recoveryScore) { _, _ in syncWatchContext() }
            .onChange(of: syncService.currentRecommendation?.id) { _, _ in syncWatchContext() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    importWatchCheckIns(); syncWatchContext(); handlePendingNotificationAction()
                    Task { await healthStore.refresh(); await synchronize() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("morrow.phone.action"))) { _ in handlePendingNotificationAction() }
            .sheet(item: $pendingRecovery) { RecoveryActionView(launch: $0) }
            .sheet(isPresented: $showNotificationCheckIn) { NavigationStack { CheckInView() } }
    }

    @MainActor
    private func logout() async {
        await MorrowAPIClient.shared.logout()
        await notificationManager.disable(unregisterServer: false)
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

    private func handlePendingNotificationAction() {
        guard let action = UserDefaults.standard.string(forKey: "morrow.phone.pendingAction") else { return }
        UserDefaults.standard.removeObject(forKey: "morrow.phone.pendingAction")
        if action == "RECOVERY" { pendingRecovery = .pending() }
        else if action == "CHECKIN" { showNotificationCheckIn = true }
    }

    private func importWatchHealth() {
        guard syncDerivedHealth else { _ = watchReceiver.drainHealthSummaries(); return }
        let summaries = watchReceiver.drainHealthSummaries()
        guard let latest = summaries.max(by: { $0.recordedAt < $1.recordedAt }) else { return }
        Task { await syncService.synchronizeWatch(latest) }
    }

    private var healthSignature: String {
        let sleep = healthStore.snapshot.sleepSession?.clientSleepId ?? "no-sleep"
        let workouts = healthStore.snapshot.workouts.map(\.clientWorkoutId).joined(separator: ",")
        return "\(healthStore.snapshot.sleepMinutes)-\(healthStore.snapshot.hrv)-\(healthStore.snapshot.restingHeartRate)-\(healthStore.snapshot.steps)-\(healthStore.snapshot.activeEnergyKcal)-\(healthStore.snapshot.exerciseMinutes)-\(sleep)-\(workouts)"
    }

    private var checkInSignature: String { checkIns.map { $0.id.uuidString }.joined(separator: "-") }

    private func syncWatchContext() {
        let result = analyzer.analyze(current: healthStore.snapshot)
        let score = syncService.recoveryScore ?? result.score
        watchReceiver.sendWellnessContext(
            score: score,
            summary: RecoveryLevel(score: score).label,
            snapshot: healthStore.snapshot,
            recommendation: syncService.currentRecommendation,
            syncDerivedHealth: syncDerivedHealth
        )
        Task {
            if let connection = try? await MorrowAPIClient.shared.connectionContext() {
                watchReceiver.sendConnectionContext(apiRoot: connection.apiRoot, credentials: connection.credentials)
            }
        }
    }

    private func synchronize() async {
        await syncService.synchronize(checkIns: checkIns, snapshot: syncDerivedHealth ? healthStore.snapshot : nil, modelContext: modelContext)
    }

    private func configureNotifications() async {
        guard notificationsEnabled else { return }
        await notificationManager.requestAuthorization()
        await notificationManager.scheduleDailyCheckIns()
    }

}

@MainActor
final class MorrowSyncService: ObservableObject {
    static let shared = MorrowSyncService()

    enum State { case idle, syncing, synced(Date), failed(String) }
    @Published private(set) var state: State = .idle
    @Published private(set) var recoveryScore: Int?
    @Published private(set) var currentRecommendation: NativeRecommendation?
    private let client = MorrowAPIClient.shared
    private var isSynchronizing = false
    private var resyncRequested = false

    var statusText: String {
        switch state {
        case .idle: return "동기화 대기"
        case .syncing: return "폰 · 워치 · 웹 동기화 중"
        case .synced(let date): return "웹 동기화 · \(date.formatted(date: .omitted, time: .shortened))"
        case .failed: return "서버 연결 필요"
        }
    }

    func synchronize(checkIns: [CheckInRecord], snapshot: HealthSnapshot?, modelContext: ModelContext) async {
        if isSynchronizing { resyncRequested = true; return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        repeat {
            resyncRequested = false
            state = .syncing
            do {
                let current = try modelContext.fetch(FetchDescriptor<CheckInRecord>())
                for record in current where !record.isSynced { try await upload(record) }
                if let snapshot, snapshot.hasHealthData { try await upload(snapshot) }
                try await mergeServerCheckIns(modelContext: modelContext)
                let dashboard = try await client.dashboard()
                recoveryScore = dashboard.score
                currentRecommendation = dashboard.recommendation
                try modelContext.save()
                state = .synced(.now)
            } catch {
                state = .failed(error.localizedDescription)
            }
        } while resyncRequested
    }

    func synchronizeWatch(_ summary: IncomingWatchHealthSummary) async {
        state = .syncing
        do {
            let credentials = try await client.credentials()
            let bucket = Int(summary.recordedAt.timeIntervalSince1970 / 300)
            let payload = HealthPayload(
                userId: credentials.userId, clientSnapshotId: "watch-\(bucket)", source: "WATCH", sleepMinutes: summary.sleepMinutes,
                heartRate: summary.heartRate, restingHeartRate: summary.restingHeartRate, hrv: summary.hrv, steps: summary.steps,
                activeEnergyKcal: summary.activeEnergyKcal, exerciseMinutes: summary.exerciseMinutes,
                distanceMeters: summary.distanceMeters, flightsClimbed: 0, respiratoryRate: 0, oxygenSaturationPercent: 0,
                recordedAt: summary.recordedAt, sleepSession: summary.sleepSession, workouts: summary.workouts
            )
            try await post(payload, path: "health/snapshots")
            let dashboard = try await client.dashboard()
            recoveryScore = dashboard.score
            currentRecommendation = dashboard.recommendation
            state = .synced(.now)
        } catch { state = .failed(error.localizedDescription) }
    }

    @discardableResult
    func synchronizeHealthSnapshot(_ snapshot: HealthSnapshot) async -> Bool {
        guard snapshot.hasHealthData else { return false }
        state = .syncing
        do {
            try await upload(snapshot)
            let dashboard = try await client.dashboard()
            recoveryScore = dashboard.score
            currentRecommendation = dashboard.recommendation
            state = .synced(.now)
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
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
            oxygenSaturationPercent: snapshot.oxygenSaturationPercent, recordedAt: .now,
            sleepSession: snapshot.sleepSession, workouts: snapshot.workouts
        )
        try await post(payload, path: "health/snapshots")
    }

    private func post<T: Encodable>(_ value: T, path: String) async throws {
        try await client.send(value, path: path)
    }

    private func mergeServerCheckIns(modelContext: ModelContext) async throws {
        let remote = try await client.checkIns()
        let remoteIds = Set(remote.map(\.id))
        var local = try modelContext.fetch(FetchDescriptor<CheckInRecord>())
        var canonicalByServerId: [UUID: CheckInRecord] = [:]
        for record in local {
            guard let serverId = record.serverId else { continue }
            if canonicalByServerId[serverId] != nil { modelContext.delete(record) }
            else { canonicalByServerId[serverId] = record }
        }
        local = try modelContext.fetch(FetchDescriptor<CheckInRecord>())
        for value in remote {
            let matched = local.first(where: { $0.serverId == value.id || $0.id.uuidString == value.clientEventId })
            if let matched {
                matched.serverId = value.id
                matched.isSynced = true
                continue
            }
            guard let status = WellnessStatus(apiValue: value.status) else { continue }
            let record = CheckInRecord(
                id: value.clientEventId.flatMap(UUID.init(uuidString:)) ?? value.id,
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
        local = try modelContext.fetch(FetchDescriptor<CheckInRecord>())
        for record in local where record.isSynced && record.serverId != nil && !remoteIds.contains(record.serverId!) {
            modelContext.delete(record)
        }
    }

    private struct CheckInPayload: Encodable { let userId, clientEventId, status: String; let cause: String?; let note, source: String; let recordedAt: Date }
    private struct HealthPayload: Encodable { let userId, clientSnapshotId, source: String; let sleepMinutes: Int; let heartRate, restingHeartRate, hrv, steps, activeEnergyKcal, exerciseMinutes, distanceMeters, flightsClimbed, respiratoryRate, oxygenSaturationPercent: Double; let recordedAt: Date; let sleepSession: SleepSessionDetail?; let workouts: [WorkoutDetail] }
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
        content.userInfo = ["type": "RECOVERY", "action": "BREATH", "durationSeconds": 60, "reason": summary, "confidence": "MEDIUM"]
        try? await center.add(UNNotificationRequest(identifier: "morrow.recovery", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
        UserDefaults.standard.set(Date(), forKey: key)
    }

    func disable(unregisterServer: Bool = true) async {
        if unregisterServer { await MorrowAPIClient.shared.unregisterPushToken() }
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        UIApplication.shared.unregisterForRemoteNotifications()
        statusText = "Morrow 알림 꺼짐"
    }

}
