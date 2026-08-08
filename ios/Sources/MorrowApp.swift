import SwiftUI
import SwiftData

@main
struct MorrowApp: App {
    @StateObject private var healthStore = HealthStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(healthStore)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: CheckInRecord.self)
    }
}

private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var healthStore: HealthStore
    @StateObject private var watchReceiver = WatchSessionReceiver()
    private let analyzer = BaselineAnalyzer()

    var body: some View {
        DashboardView()
            .onAppear { watchReceiver.activate(); importWatchCheckIns(); syncWatchContext() }
            .onChange(of: watchReceiver.inboxVersion) { _, _ in importWatchCheckIns() }
            .onChange(of: healthSignature) { _, _ in syncWatchContext() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { importWatchCheckIns(); syncWatchContext() } }
    }

    private func importWatchCheckIns() {
        for incoming in watchReceiver.drain() {
            guard let status = WellnessStatus(rawValue: incoming.status) else { continue }
            let cause = incoming.cause.flatMap(WellnessCause.init(rawValue:))
            modelContext.insert(CheckInRecord(status: status, cause: cause, source: .watch, recordedAt: incoming.recordedAt))
        }
        try? modelContext.save()
    }

    private var healthSignature: String {
        "\(healthStore.snapshot.sleepMinutes)-\(healthStore.snapshot.hrv)-\(healthStore.snapshot.restingHeartRate)-\(healthStore.snapshot.steps)"
    }

    private func syncWatchContext() {
        let result = analyzer.analyze(current: healthStore.snapshot)
        watchReceiver.sendWellnessContext(
            load: result.load,
            summary: LoadLevel(load: result.load).label,
            snapshot: healthStore.snapshot,
            recommendation: "7분 동안 가볍게 걸어보세요"
        )
    }
}
