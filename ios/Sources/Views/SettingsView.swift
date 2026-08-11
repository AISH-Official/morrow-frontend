import SwiftUI
import SwiftData

struct SettingsView: View {
    let onLogout: () async -> Void
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: MorrowSyncService
    @EnvironmentObject private var notifications: PhoneNotificationManager
    @AppStorage("morrow.sync.derivedHealth") private var syncDerivedHealth = true
    @AppStorage("morrow.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("morrow.primaryRecoveryContext") private var primaryRecoveryContext = ""
    @State private var showDeleteConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var isLoggingOut = false
    @State private var deletionCompleted = false
    @State private var apiURL = MorrowRuntimeConfiguration.apiRootString
    @State private var pairingCode = "연결 중"
    @State private var connectionMessage = ""
    @State private var aiHealthConsent = false

    var body: some View {
        Form {
            Section("나의 회복 상황") {
                Text("Morrow가 먼저 살필 상황을 하나 고르면 알림과 회복 행동의 우선순위를 여기에 맞춥니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(recoveryContexts, id: \.self) { context in
                    Button {
                        saveRecoveryContext(context)
                    } label: {
                        HStack {
                            Text(context)
                            Spacer()
                            if primaryRecoveryContext == context {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Section("기기 연동") {
                Toggle("웹과 파생 웰니스 요약 동기화", isOn: $syncDerivedHealth)
                LabeledContent("연결 상태", value: syncService.statusText)
                Text("HealthKit 원본 샘플은 전송하지 않고, 화면에 보이는 일별 요약값과 체크인만 같은 사용자 계정으로 동기화합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("서버 API 주소", text: $apiURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("서버 주소 저장 및 다시 연결") { reconnectServer() }
                LabeledContent("웹 연결 코드", value: pairingCode)
                if !connectionMessage.isEmpty { Text(connectionMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("iPhone · Watch 알림") {
                Toggle("스마트 알림", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { Task { await notifications.requestAuthorization(); await notifications.scheduleDailyCheckIns() } }
                        else { notifications.disable() }
                    }
                LabeledContent("iPhone", value: notifications.statusText)
                Text("기본 체크인 알림과 함께 AI가 최근 건강 요약과 체크인 흐름에서 도움이 된다고 판단한 맞춤 알림을 최대 6시간에 한 번 보냅니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("데이터와 개인정보") {
                Toggle("AI 답변에 건강 요약 사용", isOn: $aiHealthConsent)
                    .onChange(of: aiHealthConsent) { _, value in Task { _ = try? await MorrowAPIClient.shared.updateAIHealthConsent(value) } }
                Text("직접 허용한 경우에만 파생 건강 요약을 AI 답변 컨텍스트에 포함합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                Label("HealthKit 원본은 기기에서만 읽고 분석합니다.", systemImage: "lock.shield")
                Label("건강 데이터와 체크인 기록을 광고나 판매에 사용하지 않습니다.", systemImage: "hand.raised")
                NavigationLink("개인정보 처리방침", destination: PrivacyPolicyView())
                Button("저장된 체크인 전체 삭제", role: .destructive) { showDeleteConfirmation = true }
            }
            Section("서비스 범위") {
                Text("Morrow는 일상적인 웰니스 자기관리를 돕는 도구이며 의료 진단, 치료 또는 응급 서비스를 제공하지 않습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("계정") {
                Button(role: .destructive) { showLogoutConfirmation = true } label: {
                    HStack {
                        Label(isLoggingOut ? "로그아웃 중" : "로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                        Spacer()
                        if isLoggingOut { ProgressView() }
                    }
                }
                .disabled(isLoggingOut)
                Text("이 iPhone과 연결된 Apple Watch의 로그인 정보만 지워지며 서버의 건강 기록은 삭제되지 않습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("앱 정보") {
                LabeledContent("버전", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.screenBackground)
        .confirmationDialog("모든 체크인 기록을 삭제할까요?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("모든 기기와 서버에서 삭제", role: .destructive) { Task { await deleteAll() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제된 기록은 복구할 수 없습니다. HealthKit 원본 데이터는 삭제하지 않습니다.")
        }
        .confirmationDialog("로그아웃할까요?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button("로그아웃", role: .destructive) {
                isLoggingOut = true
                Task { await onLogout() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("건강 기록은 유지되고 이 기기의 인증정보만 제거됩니다.")
        }
        .alert("삭제했습니다", isPresented: $deletionCompleted) { Button("확인", role: .cancel) {} }
        .task { await loadConnection() }
    }

    @MainActor
    private func deleteAll() async {
        do { try await MorrowAPIClient.shared.clearWellnessData() }
        catch { connectionMessage = "서버 기록을 삭제하지 못했습니다. 연결을 확인해 주세요."; return }
        let records = (try? modelContext.fetch(FetchDescriptor<CheckInRecord>())) ?? []
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
        deletionCompleted = true
    }

    private func reconnectServer() {
        MorrowRuntimeConfiguration.setAPIOverride(apiURL)
        Task {
            await MorrowAPIClient.shared.resetForServerChange()
            await loadConnection()
        }
    }

    private var recoveryContexts: [String] {
        ["수면이 부족한 아침", "업무·학업 집중 저하", "오래 앉아 있을 때", "발표·회의 전 긴장"]
    }

    private func saveRecoveryContext(_ context: String) {
        guard primaryRecoveryContext != context else { return }
        primaryRecoveryContext = context
        Task {
            try? await MorrowAPIClient.shared.addPersonalMemory(
                type: "GOAL",
                summary: "주요 회복 상황: \(context)"
            )
        }
    }

    @MainActor
    private func loadConnection() async {
        apiURL = MorrowRuntimeConfiguration.apiRootString
        do {
            let credentials = try await MorrowAPIClient.shared.refreshPairingCode()
            aiHealthConsent = (try? await MorrowAPIClient.shared.aiHealthConsent()) ?? false
            pairingCode = credentials.pairingCode
            connectionMessage = "사용자 \(credentials.userId) 연결 코드 · 10분 동안 유효"
        } catch {
            pairingCode = "연결 실패"
            connectionMessage = "Mac의 LAN 주소를 포함한 API 주소를 입력하세요. 예: http://192.168.0.10:8080/api/v1"
        }
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("개인정보 처리방침").font(.title2.bold())
                policySection("수집 및 이용", "Morrow는 사용자가 허용한 수면, 걸음, 심박, 안정 시 심박, HRV, 활동 에너지, 운동 시간, 거리, 오른 층수, 호흡수와 산소포화도를 HealthKit에서 읽어 개인 웰니스 요약을 생성합니다. 기기에서 제공되지 않는 항목은 수집하지 않습니다.")
                policySection("저장 및 동기화", "HealthKit 원본 샘플은 서버나 iCloud에 저장하지 않습니다. 동기화를 켜면 일별 파생 요약과 사용자가 작성한 체크인을 Morrow 서버에 저장해 iPhone, Watch, 웹에서 같은 흐름을 보여줍니다.")
                policySection("AI 사용", "사용자가 승인한 파생 건강 요약과 체크인 맥락은 대화 답변과 맞춤 알림을 생성할 때 설정된 AI 제공자에게 전송됩니다. 광고, 판매, 제3자 마케팅이나 Morrow의 범용 모델 학습에는 사용하지 않습니다.")
                policySection("삭제와 제어", "설정에서 로컬 체크인 기록을 삭제하고 파생 요약 동기화를 끌 수 있습니다. 서버 데이터는 웹의 데이터 삭제 기능에서 지울 수 있으며 HealthKit 접근 권한은 iPhone 설정에서 언제든 변경할 수 있습니다.")
                policySection("안내", "Morrow는 의료기기나 응급 서비스가 아니며 질환을 진단하거나 치료하지 않습니다. 긴급한 도움이 필요하면 지역 응급기관이나 의료 전문가에게 연락하세요.")
                policySection("문의", "개인정보 관련 문의: github.com/qlsl1198")
                Text("시행일: 2026년 8월 8일")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("개인정보")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.body).foregroundStyle(.secondary)
        }
    }
}
