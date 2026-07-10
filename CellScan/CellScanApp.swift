import SwiftUI

@main
struct CellScanApp: App {
    @StateObject private var store = PassStore()
    @StateObject private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
