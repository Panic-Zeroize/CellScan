import SwiftUI

enum Route: Hashable {
    case newPass
    case summary(UUID)
    case map(UUID)
    case export([UUID])
    case settings
}

/// Owns the engine without republishing its changes. If RootView observed the
/// engine directly, every 1 Hz tick would re-render the whole navigation stack
/// (and re-merge every pass card). Only the screens that show live recording
/// state observe the engine.
@MainActor
final class EngineHolder: ObservableObject {
    let engine = RecordingEngine()
}

struct RootView: View {
    @EnvironmentObject var store: PassStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var holder = EngineHolder()
    @State private var path: [Route] = []
    @State private var recording = false
    @State private var shownAlert: AppAlert?
    @State private var alertQueue: [AppAlert] = []

    private var engine: RecordingEngine { holder.engine }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onStartPass: { path.append(.newPass) },
                onOpenPass: { path.append(.summary($0)) },
                onOpenSettings: { path.append(.settings) },
                onExport: { path.append(.export($0)) }
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
                            onExport: { path.append(.export([id])) },
                            onDelete: {
                                store.delete(ids: [id])
                                path.removeAll()
                            },
                            onDone: { path.removeAll() }
                        )
                    } else { missing }
                case .map(let id):
                    if let pass = store.pass(with: id) {
                        MapScreen(passes: [pass],
                                  title: "\(pass.carrierLabel) · \(RelativeDate.short(pass.startedAt))")
                    } else { missing }
                case .export(let ids):
                    let passes = ids.compactMap { store.pass(with: $0) }
                    if passes.isEmpty { missing }
                    else { ExportView(passes: passes) }
                case .settings:
                    SettingsView()
                }
            }
        }
        .fullScreenCover(isPresented: $recording) {
            RecordingView(engine: engine,
                          onSave: { finishRecording() },
                          onDiscard: { discardRecording() })
        }
        .alert(item: $shownAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .onAppear { takeStoreAlert() }                       // alerts raised during launch
        .onChange(of: store.alert) { _, _ in takeStoreAlert() }
        .onChange(of: recording) { _, _ in showNextAlertIfIdle() }
        .onChange(of: shownAlert) { _, _ in showNextAlertIfIdle() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground is the most likely moment to be killed.
            if phase != .active { engine.checkpointNow() }
        }
    }

    // MARK: - Alerts

    /// Moves a store alert into local presentation state.
    private func takeStoreAlert() {
        guard let alert = store.alert else { return }
        store.alert = nil
        present(alert)
    }

    /// Queues an alert. Alerts are shown one at a time, and never over (or while
    /// dismissing) the recording cover.
    private func present(_ alert: AppAlert) {
        alertQueue.append(alert)
        showNextAlertIfIdle()
    }

    private func showNextAlertIfIdle() {
        guard !recording, shownAlert == nil, !alertQueue.isEmpty else { return }
        // Let any cover / previous alert finish animating away first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard !recording, shownAlert == nil, !alertQueue.isEmpty else { return }
            shownAlert = alertQueue.removeFirst()
        }
    }

    private func finishRecording() {
        let pass = engine.stop()
        recording = false
        if let pass {
            store.add(pass, finishingRecording: true)
            path = [.summary(pass.id)]
        } else {
            path = []
            present(AppAlert(
                title: "Nothing recorded",
                message: "No GPS samples were captured, so there was nothing to save. Make sure Location access is allowed for CellScan and the phone has a clear view of the sky, then try again."))
        }
    }

    private func discardRecording() {
        engine.discard()
        recording = false
        path = []
    }

    private var missing: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textFaint)
            Text("This pass is no longer available")
                .foregroundStyle(Theme.textDim)
            Button("Back to Passes") { path.removeAll() }
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }
}
