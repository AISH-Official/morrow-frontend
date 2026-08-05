import SwiftUI

struct WatchCheckInView: View {
    private let states = ["정상", "긴장", "피로", "집중 저하"]
    @State private var selected: String?
    @State private var saved = false
    var body: some View {
        NavigationStack {
            List(states, id: \.self) { state in
                Button { selected = state; saved = true } label: {
                    HStack { Text(state); Spacer(); if selected == state { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) } }
                }
            }
            .navigationTitle("지금 상태")
            .safeAreaInset(edge: .bottom) { if saved { Text("iPhone과 동기화 대기").font(.caption2).foregroundStyle(.secondary) } }
        }
    }
}
