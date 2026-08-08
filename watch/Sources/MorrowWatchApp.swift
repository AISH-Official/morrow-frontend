import SwiftUI

@main
struct MorrowWatchApp: App {
    @StateObject private var session = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchCheckInView()
                .environmentObject(session)
        }
    }
}
