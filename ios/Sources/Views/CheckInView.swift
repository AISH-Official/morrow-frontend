import SwiftUI

struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var selection: WellnessStatus?
    @State private var cause: WellnessCause?
    @State private var note = ""
    @State private var showSaved = false
    @FocusState private var noteFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("30-SECOND CHECK-IN").morrowKicker()
                Text("지금 어떤 상태인가요?")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("생체 신호보다 직접 입력한 상태를 우선해요.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WellnessStatus.allCases) { status in
                        statusCard(status)
                    }
                }

                Text("무엇과 가장 관련 있나요?")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                    ForEach(WellnessCause.allCases) { item in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { cause = item }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(item.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(cause == item ? Theme.screenBackground : Theme.textSecondary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(cause == item ? Theme.accent : Theme.elevatedBackground, in: Capsule())
                                .overlay(Capsule().stroke(cause == item ? Theme.accent : Theme.border))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(cause == item ? .isSelected : [])
                    }
                }

                Text("선택 입력")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
                TextField("짧게 상황을 남겨보세요", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($noteFocused)
                    .padding(Theme.spacing)
                    .foregroundStyle(Theme.textPrimary)
                    .background(Theme.panelBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).stroke(Theme.border))

                Button(action: save) {
                    Label("기록 저장", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.screenBackground)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 15))
                .disabled(selection == nil)
                .padding(.top, 4)
            }
            .padding(Theme.spacing)
        }
        .background(Theme.screenBackground)
        .navigationTitle("체크인")
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
                    .foregroundStyle(Theme.textPrimary)
                Text(status.guide)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spacing)
            .padding(.horizontal, 8)
            .morrowPanel()
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
        guard let selection else { return }
        modelContext.insert(CheckInRecord(status: selection, cause: cause, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        try? modelContext.save()
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
        .background(Theme.elevatedBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).stroke(Theme.border))
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}
