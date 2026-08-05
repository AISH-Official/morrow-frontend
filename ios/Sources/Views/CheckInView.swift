import SwiftUI

struct CheckInView: View {
    @State private var selection: WellnessStatus?
    @State private var note = ""
    var body: some View {
        Form {
            Section("현재 상태") { ForEach(WellnessStatus.allCases, id: \.self) { item in Button { selection = item } label: { HStack { Text(item.rawValue); Spacer(); if selection == item { Image(systemName: "checkmark") } } } } }
            Section("선택 입력") { TextField("짧게 상황을 남겨보세요", text: $note) }
            Section { Button("기록 저장") { /* APIClient.createCheckIn 연결 지점 */ }.disabled(selection == nil) }
        }.navigationTitle("상태 기록")
    }
}
