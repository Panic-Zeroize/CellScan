#if DEBUG
import Foundation
import UIKit

/// End-to-end smoke test, DEBUG builds only (compiled out of Release).
///
/// CI launches the app in the iOS Simulator with `-smokeTest <seconds>` after
/// granting location access and starting a simulated drive (`simctl location`).
/// The app then records a real pass through the real pipeline — CLLocationManager,
/// background location updates, live throughput probes, PassStore persistence,
/// checkpointing and CSV export — with no taps, and writes
/// `Documents/smoke-result.json` plus `Documents/smoke.csv` for CI to verify.
@MainActor
enum SmokeTest {
    static var requestedSeconds: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-smokeTest") else { return nil }
        let value = i + 1 < args.count ? Int(args[i + 1]) : nil
        return max(10, value ?? 60)
    }

    struct Tick: Codable {
        var second: Int
        var appState: String
        var samples: Int
        var waitingForGPS: Bool
        var probing: Bool
    }

    struct Result: Codable {
        var finishedAt: Date
        var requestedSeconds: Int
        var locationAccess: String
        var samples: Int
        var foregroundSamples: Int
        var backgroundSamples: Int
        var samplesWithThroughput: Int
        var cells: Int
        var distanceMiles: Double
        var savedPassFound: Bool
        var checkpointRemoved: Bool
        var csvRows: Int
        var csvHeader: String
        var ticks: [Tick]
        var error: String?
    }

    static func run(engine: RecordingEngine,
                    store: PassStore,
                    onRecordingStarted: () -> Void,
                    onFinished: (UUID?) -> Void) async {
        guard let seconds = requestedSeconds else { return }
        let archive = PassArchive.standard
        var result = Result(finishedAt: Date(), requestedSeconds: seconds, locationAccess: "",
                            samples: 0, foregroundSamples: 0, backgroundSamples: 0,
                            samplesWithThroughput: 0, cells: 0, distanceMiles: 0,
                            savedPassFound: false, checkpointRemoved: false,
                            csvRows: 0, csvHeader: "", ticks: [], error: nil)

        // Permission is granted by CI (`simctl privacy`); give CoreLocation a moment.
        engine.requestPermission()
        for _ in 0..<20 where engine.locationAccess != .granted {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        result.locationAccess = "\(engine.locationAccess)"

        var settings = AppSettings()
        settings.sampleIntervalSec = 1
        settings.throughputIntervalSec = 10
        engine.start(carrier: .tmobile, throughputEnabled: true, settings: settings)
        onRecordingStarted()

        var lastCount = 0
        for second in 1...seconds {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let state = UIApplication.shared.applicationState
            let count = engine.samples.count
            let delta = max(0, count - lastCount)
            if state == .background { result.backgroundSamples += delta } else { result.foregroundSamples += delta }
            lastCount = count
            result.ticks.append(Tick(second: second,
                                     appState: state == .background ? "background" : (state == .active ? "active" : "inactive"),
                                     samples: count,
                                     waitingForGPS: engine.waitingForGPS,
                                     probing: engine.probing))
        }

        guard let pass = engine.stop() else {
            result.error = "No samples were recorded."
            write(result, to: archive)
            onFinished(nil)
            return
        }
        store.add(pass, finishingRecording: true)
        Persistence.queue.sync {}   // wait for the save + checkpoint clear to land

        let csv = CSV.document(for: [pass])
        try? Data(csv.utf8).write(to: archive.directory.appendingPathComponent("smoke.csv"), options: .atomic)

        result.samples = pass.samples.count
        result.samplesWithThroughput = pass.samples.filter { $0.downMbps != nil }.count
        result.cells = pass.mergedCells().count
        result.distanceMiles = pass.distanceMiles
        result.savedPassFound = archive.load().passes.contains { $0.id == pass.id }
        result.checkpointRemoved = !FileManager.default.fileExists(atPath: archive.checkpointURL.path)
        let lines = csv.split(separator: "\n")
        result.csvHeader = lines.first.map(String.init) ?? ""
        result.csvRows = max(0, lines.count - 1)
        result.finishedAt = Date()
        write(result, to: archive)
        onFinished(pass.id)
    }

    private static func write(_ result: Result, to archive: PassArchive) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(result) {
            try? data.write(to: archive.directory.appendingPathComponent("smoke-result.json"), options: .atomic)
        }
    }
}
#endif
