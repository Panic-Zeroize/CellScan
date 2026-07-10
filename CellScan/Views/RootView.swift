import SwiftUI

enum Route: Hashable {
    case newPass
    case summary(UUID)
    case map(UUID)
}

struct RootView: View {
    @EnvironmentObject var store: PassStore
    @StateObject private var engine = RecordingEngine()
    @State private var path: [Route] = []
    @State private var recording = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onStartPass: { path.append(.newPass) },
                onOpenPass: { path.append(.map($0)) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .newPass:
                    NewPassView(
                        engine: engine,
                        onCancel: { if !path.isEmpty { path.removeLast() } },
                        onStart: { carrier, throughput in
                            engine.start(carrier: carrier, throughputEnabled: throughput)
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
                    } else {
                        missing
                    }
                case .map(let id):
                    if let pass = store.pass(with: id) {
                        MapScreen(pass: pass)
                    } else {
                        missing
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $recording) {
            RecordingView(engine: engine) {
                // Stop & Save
                recording = false
                if let pass = engine.stop() {
                    store.add(pass)
                    path = [.summary(pass.id)]
                } else {
                    // Nothing captured — just return to New Pass screen.
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
