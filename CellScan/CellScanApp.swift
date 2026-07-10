import SwiftUI

@main
struct CellScanApp: App {
    @StateObject private var store = PassStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
