import SwiftUI
import WidgetKit

private struct RecoveryEntry: TimelineEntry {
    let date: Date
}

private struct RecoveryProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryEntry { RecoveryEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) { completion(RecoveryEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryEntry>) -> Void) {
        completion(Timeline(entries: [RecoveryEntry(date: .now)], policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

@main
struct MorrowRecoveryWidget: Widget {
    private let kind = "MorrowRecoveryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RecoveryProvider()) { _ in
            RecoveryWidgetView()
                .containerBackground(for: .widget) { Color(red: 5 / 255, green: 20 / 255, blue: 27 / 255) }
                .widgetURL(URL(string: "morrow://recovery"))
        }
        .configurationDisplayName("지금 회복")
        .description("손목에서 바로 1분 회복 행동을 시작합니다.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct RecoveryWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "wind").font(.headline)
                    Text("1분").font(.caption2.bold())
                }
            }
            .widgetAccentable()
        case .accessoryInline:
            Label("Morrow · 지금 1분 회복", systemImage: "wind")
        default:
            HStack(spacing: 8) {
                Image(systemName: "wind")
                    .font(.title3)
                    .foregroundStyle(Color(red: 91 / 255, green: 222 / 255, blue: 172 / 255))
                VStack(alignment: .leading, spacing: 2) {
                    Text("MORROW").font(.system(size: 8, weight: .semibold, design: .monospaced))
                    Text("지금 1분 회복").font(.caption.bold())
                }
            }
        }
    }
}
