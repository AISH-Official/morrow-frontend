import SwiftUI
import SwiftData

struct CheckInHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CheckInRecord.recordedAt, order: .reverse) private var records: [CheckInRecord]

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView("아직 기록이 없어요", systemImage: "square.and.pencil", description: Text("현재 상태를 짧게 기록하면 이곳에서 흐름을 확인할 수 있습니다."))
            } else {
                List {
                    ForEach(records) { record in
                        HStack(spacing: 12) {
                            Image(systemName: record.status.icon)
                                .foregroundStyle(record.status.tint)
                                .frame(width: 36, height: 36)
                                .background(record.status.tint.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.status.rawValue).font(.headline)
                                    if let cause = record.cause {
                                        Text("· \(cause.rawValue)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(record.source == .watch ? "Watch" : "iPhone")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                                if !record.note.isEmpty { Text(record.note).font(.subheadline).lineLimit(2) }
                                Text(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.panelBackground)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("상태 기록")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Theme.screenBackground)
    }

    private func delete(at offsets: IndexSet) {
        for offset in offsets { modelContext.delete(records[offset]) }
        try? modelContext.save()
    }
}
