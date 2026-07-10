import Foundation
import CoreLocation
import Combine

/// Orchestrates a live recording pass: pulls GPS fixes, reads the radio type,
/// runs periodic throughput probes, and accumulates samples.
@MainActor
final class RecordingEngine: ObservableObject {
    // Live state surfaced to the UI
    @Published var isRecording = false
    @Published var elapsed = 0
    @Published var samples: [Sample] = []
    @Published var currentRat: RAT = .none
    @Published var sparks: [RAT] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var cellCount = 0
    @Published var lastResult: ThroughputResult?

    // Pass configuration
    @Published var carrier: Carrier = .verizon
    @Published var throughputEnabled = true

    let location = LocationManager()
    private let radio = RadioMonitor()
    private let tester = ThroughputTester()

    private var timer: Timer?
    private var startedAt = Date()
    private var lastSampleLocation: CLLocation?
    private var lastResultAt: Date?
    private var throughputRunning = false
    private var gridKeys = Set<String>()

    private let sampleInterval = 3      // seconds between GPS samples
    private let throughputInterval = 20 // seconds between speed probes

    // MARK: - Control

    func requestPermission() { location.requestPermission() }

    func start(carrier: Carrier, throughputEnabled: Bool) {
        self.carrier = carrier
        self.throughputEnabled = throughputEnabled
        reset()
        isRecording = true
        startedAt = Date()
        location.requestPermission()
        location.startUpdating()
        currentRat = radio.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if throughputEnabled { runThroughput() }
    }

    /// Stops recording and returns the finished pass (nil if nothing was captured).
    func stop() -> Pass? {
        timer?.invalidate(); timer = nil
        location.stopUpdating()
        isRecording = false
        guard !samples.isEmpty else { return nil }
        return Pass(carrier: carrier,
                    startedAt: startedAt,
                    durationSec: elapsed,
                    distanceMiles: distanceMeters / 1609.344,
                    samples: samples)
    }

    private func reset() {
        elapsed = 0
        samples = []
        sparks = []
        distanceMeters = 0
        cellCount = 0
        lastResult = nil
        lastResultAt = nil
        lastSampleLocation = nil
        gridKeys.removeAll()
    }

    // MARK: - Timer

    private func tick() {
        elapsed += 1
        if elapsed % sampleInterval == 0 { captureSample() }
        if throughputEnabled, elapsed % throughputInterval == 0 { runThroughput() }
    }

    private func captureSample() {
        currentRat = radio.refresh()
        guard let loc = location.location else { return }

        // Attach the most recent throughput result if it's still fresh.
        var down: Double?, up: Double?, latency: Double?
        if let r = lastResult, let at = lastResultAt,
           Date().timeIntervalSince(at) < 45 {
            down = r.downMbps; up = r.upMbps; latency = r.latencyMs
        }

        let speedMph = max(0, loc.speed) * 2.2369362920544
        let heading = loc.course >= 0 ? loc.course : 0

        let sample = Sample(t: Date(),
                            lat: loc.coordinate.latitude,
                            lng: loc.coordinate.longitude,
                            accuracy: max(0, loc.horizontalAccuracy),
                            speedMph: speedMph,
                            heading: heading,
                            rat: currentRat,
                            downMbps: down,
                            upMbps: up,
                            latencyMs: latency)
        samples.append(sample)

        // Sparkline history
        sparks.append(currentRat)
        if sparks.count > 26 { sparks.removeFirst(sparks.count - 26) }

        // Dedup cell count on a ~120 m grid (matches Pass.cells)
        let key = "\(Int(sample.lat * 900))_\(Int(sample.lng * 900))"
        gridKeys.insert(key)
        cellCount = gridKeys.count

        // Distance
        if let prev = lastSampleLocation {
            let d = loc.distance(from: prev)
            if d.isFinite, d < 2000 { distanceMeters += d } // skip GPS jumps
        }
        lastSampleLocation = loc
    }

    private func runThroughput() {
        guard !throughputRunning else { return }
        throughputRunning = true
        // Adaptive: probe less data when the last measurement was weak/dead.
        let bytes: Int
        switch lastResult?.downMbps {
        case .some(let d) where d < 10: bytes = 600_000
        case .none where lastResultAt != nil: bytes = 400_000
        default: bytes = 1_500_000
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.tester.measure(downloadBytes: bytes)
            self.lastResult = result
            self.lastResultAt = Date()
            self.throughputRunning = false
        }
    }

    // MARK: - Display helpers

    var elapsedString: String {
        let m = elapsed / 60, s = elapsed % 60
        return String(format: "%02d:%02d", m, s)
    }
    var distanceMiles: Double { distanceMeters / 1609.344 }

    var lastLatString: String {
        location.location.map { String(format: "%.5f", $0.coordinate.latitude) } ?? "—"
    }
    var lastLngString: String {
        location.location.map { String(format: "%.5f", $0.coordinate.longitude) } ?? "—"
    }
    var accuracyString: String {
        location.location.map { String(format: "±%.0f m", max(0, $0.horizontalAccuracy)) } ?? "—"
    }
    var speedString: String {
        guard let s = location.location?.speed, s >= 0 else { return "0 mph" }
        return String(format: "%.0f mph", s * 2.2369362920544)
    }
    var latencyString: String {
        guard let l = lastResult?.latencyMs else { return currentRat == .none ? "timeout" : "—" }
        return String(format: "%.0f ms", l)
    }
    var downString: String {
        guard let d = lastResult?.downMbps else { return "—" }
        return String(format: "%.0f Mb", d)
    }
}
