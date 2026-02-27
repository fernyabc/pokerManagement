import SwiftUI
import SwiftData

@main
struct pokerManagementApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: HandHistory.self)
    }
}
