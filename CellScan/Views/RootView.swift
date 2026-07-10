import SwiftUI

enum Route: Hashable {
    case newPass
    case summary(UUID)
    case map(UUID)
    case combined([UUID])
    case settings
}

struct RootView: View {
    @EnvironmentObject var store: PassStore
    @EnvironmentObject var settingsStore: SettingsStore
    @StateObject private var engine = RecordingEngine()
    @State private var path: [Route] = []
    @State private var recording = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onStartPass: { path.append(.newPass) },
                onOpenPass: { path.append(.map($0)) },
                onOpenSettings: { path.append(.settings) },
                onCombine: { path.append(.combined($0)) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .newPass:
                    NewPassView(
                        engine: engine,
                        onCancel: { if !path.isEmpty { path.removeLast() } },
                        onStart: { carrier, throughput in
                            engine.start(carrier: carrier,
                                         throughputEnabled: throughput,
                                         settings: settingsStore.settings)
                            recording = true
                        }
                    )
                case .summary(let id):
                    if let pass = store.pass(with: id) {
                        SummaryView(
                            pass: pass,
                            onViewMap: { path.append(.map(id)) },
                            onDone: { path.removeAll() }
                        )
                    } else { missing }
                case .map(let id):
                    if let pass = store.pass(with: id) {
                        MapScreen(passes: [pass],
                                  title: "\(pass.carrier.displayName) · \(RelativeDate.short(pass.startedAt))")
                    } else { missing }
                case .combined(let ids):
                    let passes = ids.compactMap { store.pass(with: $0) }
                    if passes.isEmpty { missing }
                    else { MapScreen(passes: passes, title: "Combined · \(passes.count) scans") }
                case .settings:
                    SettingsView()
                }
            }
        }
        .fullScreenCover(isPresented: $recording) {
            RecordingView(engine: engine) {
                recording = false
                if let pass = engine.stop() {
                    store.add(pass)
                    path = [.summary(pass.id)]
                }
            }
        }
    }

    private var missing: some View {
        Text("Pass not found")
            .foregroundStyle(Theme.textDim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
    }
}