import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncService: MorrowSyncService
    @EnvironmentObject private var notifications: PhoneNotificationManager
    @AppStorage("morrow.sync.derivedHealth") private var syncDerivedHealth = true
    @AppStorage("morrow.notifications.enabled") private var notificationsEnabled = true
    @State private var showDeleteConfirmation = false
    @State private var deletionCompleted = false

    var body: some View {
        Form {
            Section("기기 연동") {
                Toggle("웹과 파생 웰니스 요약 동기화", isOn: $syncDerivedHealth)
                LabeledContent("연결 상태", value: syncService.statusText)
                Text("HealthKit 원본 샘플은 전송하지 않고, 화면에 보이는 일별 요약값과 체크인만 같은 사용자 계정으로 동기화합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("iPhone · Watch 알림") {
                Toggle("스마트 알림", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { Task { await notifications.requestAuthorization(); await notifications.scheduleDailyCheckIns() } }
                        else { notifications.disable() }
                    }
                LabeledContent("iPhone", value: notifications.statusText)
                Text("매일 오전 10시와 오후 8시 30분 체크인 알림, 회복 부하가 높을 때 최대 6시간에 한 번 회복 알림을 보냅니다. Watch 앱은 워치 자체 알림을 별도로 예약합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("데이터와 개인정보") {
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
            Section("앱 정보") {
                LabeledContent("버전", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.screenBackground)
        .confirmationDialog("모든 체크인 기록을 삭제할까요?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("전체 삭제", role: .destructive, action: deleteAll)
            Button("취소", role: .cancel) {}
        } message: {
            Text("삭제된 기록은 복구할 수 없습니다. HealthKit 원본 데이터는 삭제하지 않습니다.")
        }
        .alert("삭제했습니다", isPresented: $deletionCompleted) { Button("확인", role: .cancel) {} }
    }

    private func deleteAll() {
        let records = (try? modelContext.fetch(FetchDescriptor<CheckInRecord>())) ?? []
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
        deletionCompleted = true
    }
}

private struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("개인정보 처리방침").font(.title2.bold())
                policySection("수집 및 이용", "Morrow는 사용자가 허용한 수면, 걸음, 심박, 안정 시 심박, HRV, 활동 에너지, 운동 시간, 거리, 오른 층수, 호흡수와 산소포화도를 HealthKit에서 읽어 개인 웰니스 요약을 생성합니다. 기기에서 제공되지 않는 항목은 수집하지 않습니다.")
                policySection("저장 및 동기화", "HealthKit 원본 샘플은 서버나 iCloud에 저장하지 않습니다. 동기화를 켜면 일별 파생 요약과 사용자가 작성한 체크인을 Morrow 서버에 저장해 iPhone, Watch, 웹에서 같은 흐름을 보여줍니다.")
                policySection("공유", "건강 데이터와 체크인 기록을 광고, 판매, 제3자 마케팅 또는 범용 AI 모델 학습에 사용하거나 제공하지 않습니다.")
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
