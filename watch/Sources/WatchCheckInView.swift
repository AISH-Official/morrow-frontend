import SwiftUI
import WatchKit

/// 워치에서 한 번의 탭으로 남기는 상태 값. iOS의 WellnessStatus와 rawValue를 공유합니다.
enum WatchStatus: String, CaseIterable, Identifiable {
    case ok = "정상"
    case tense = "긴장"
    case tired = "피로"
    case lowFocus = "집중 저하"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ok: return "face.smiling"
        case .tense: return "bolt.heart"
        case .tired: return "moon.zzz"
        case .lowFocus: return "cloud.fog"
        }
    }

    var tint: Color {
        switch self {
        case .ok: return .green
        case .tense: return .orange
        case .tired: return .indigo
        case .lowFocus: return .purple
        }
    }
}

struct WatchCheckInView: View {
    @EnvironmentObject private var session: WatchSessionManager
    @State private var selected: WatchStatus?
    @State private var showSaved = false

    var body: some View {
        NavigationStack {
            List(WatchStatus.allCases) { status in
                Button {
                    checkIn(status)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: status.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(status.tint)
                            .frame(width: 28, height: 28)
                            .background(status.tint.opacity(0.15), in: Circle())
                        Text(status.rawValue)
                            .font(.body.weight(.medium))
                        Spacer()
                        if selected == status {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(status.tint)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("지금 상태")
            .overlay { if showSaved, let selected { savedOverlay(selected) } }
        }
    }

    private func checkIn(_ status: WatchStatus) {
        selected = status
        session.send(status: status.rawValue)
        WKInterfaceDevice.current().play(.success)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.25)) { showSaved = false }
        }
    }

    private func savedOverlay(_ status: WatchStatus) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(status.tint)
            Text("\(status.rawValue) 기록됨")
                .font(.headline)
            Text("iPhone과 동기화 중")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.85))
        .transition(.opacity)
    }
}
