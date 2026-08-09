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

    var body: some View {
        NavigationStack {
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
        }
        .tint(WatchTheme.accent)
        .task {
            await health.requestAuthorizationAndLoad()
            session.sendHealthSummary(health.snapshot)
            await notifications.configure()
            await notifications.recoveryAlert(load: session.context.load)
        }
        .onChange(of: session.context.load) { _, load in Task { await notifications.recoveryAlert(load: load) } }
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
                Circle().trim(from: 0, to: Double(session.context.load) / 100).stroke(WatchTheme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90)).shadow(color: WatchTheme.accent.opacity(0.35), radius: 5)
                Text("\(session.context.load)").font(.system(size: 22, weight: .medium, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 5) {
            Label("NEXT BEST ACTION", systemImage: "sparkles").font(.system(size: 7, weight: .semibold, design: .monospaced)).foregroundStyle(WatchTheme.accent)
            Text(session.context.recommendation).font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(LinearGradient(colors: [WatchTheme.accent.opacity(0.18), WatchTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(WatchTheme.border))
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
            NavigationLink(destination: QuickCheckInView()) { action("체크인", "plus.circle.fill", WatchTheme.accent) }.buttonStyle(.plain)
            NavigationLink(destination: RecoverySessionView()) { action("1분 회복", "wind", WatchTheme.mint) }.buttonStyle(.plain)
            Button {
                Task { await health.requestAuthorizationAndLoad(); session.sendHealthSummary(health.snapshot) }
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
                Text("매일 체크인 2회와 높은 회복 부하 알림을 Watch에서 직접 예약합니다.").font(.caption2).foregroundStyle(WatchTheme.muted).multilineTextAlignment(.center)
                Button("알림 다시 설정") { Task { await notifications.configure() } }.buttonStyle(.borderedProminent).tint(WatchTheme.accent)
            }.padding(.vertical, 10)
        }.navigationTitle("알림")
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

private struct RecoverySessionView: View {
    @State private var remaining = 60
    @State private var running = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            Text("RESET SESSION").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.2).foregroundStyle(WatchTheme.muted)
            ZStack {
                Circle().stroke(WatchTheme.mint.opacity(0.12), lineWidth: 9)
                Circle().trim(from: 0, to: Double(60 - remaining) / 60).stroke(WatchTheme.mint, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90)).animation(.linear, value: remaining)
                VStack { Text("\(remaining)").font(.system(size: 30, weight: .medium, design: .monospaced)); Text(running ? breathCue : "1분 회복").font(.caption2).foregroundStyle(WatchTheme.muted) }
            }.frame(width: 112, height: 112)
            Button(running ? "잠시 멈춤" : remaining == 0 ? "다시 시작" : "시작") {
                if remaining == 0 { remaining = 60 }
                running.toggle(); WKInterfaceDevice.current().play(.click)
            }.buttonStyle(.borderedProminent).tint(WatchTheme.mint)
        }
        .onReceive(timer) { _ in
            guard running, remaining > 0 else { return }
            remaining -= 1
            if remaining == 0 { running = false; WKInterfaceDevice.current().play(.success) }
            else if remaining % 4 == 0 { WKInterfaceDevice.current().play(.directionUp) }
        }
        .navigationTitle("1분 회복")
    }

    private var breathCue: String { ((60 - remaining) / 4).isMultiple(of: 2) ? "천천히 들이쉬기" : "길게 내쉬기" }
}
