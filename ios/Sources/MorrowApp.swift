import SwiftUI

@main
struct MorrowApp: App {
    @StateObject private var healthStore = HealthStore()
    var body: some Scene {
        WindowGroup { DashboardView().environmentObject(healthStore) }
    }
}
