import SwiftUI

struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selection: WellnessStatus?
    @State private var note = ""
    @State private var showSaved = false
    @FocusState private var noteFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("지금 상태와 가장 가까운 것을 골라주세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WellnessStatus.allCases) { status in
                        statusCard(status)
                    }
                }

                Text("선택 입력")
                    .font(.headline)
                    .padding(.top, 4)
                TextField("짧게 상황을 남겨보세요", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($noteFocused)
                    .padding(Theme.spacing)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))

                Button(action: save) {
                    Label("기록 저장", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selection == nil)
                .padding(.top, 4)
            }
            .padding(Theme.spacing)
        }
        .background(Theme.screenBackground)
        .navigationTitle("상태 기록")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .overlay { if showSaved { savedOverlay } }
    }

    private func statusCard(_ status: WellnessStatus) -> some View {
        let isSelected = selection == status
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = status }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: status.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.white : status.tint)
                    .frame(width: 48, height: 48)
                    .background(
                        isSelected ? AnyShapeStyle(status.tint) : AnyShapeStyle(status.tint.opacity(0.12)),
                        in: Circle()
                    )
                Text(status.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(status.guide)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacing)
            .padding(.horizontal, 8)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(isSelected ? status.tint : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.rawValue), \(status.guide)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save() {
        // APIClient.createCheckIn 연결 지점
        noteFocused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { showSaved = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        }
    }

    private var savedOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("기록했어요")
                .font(.headline)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}
