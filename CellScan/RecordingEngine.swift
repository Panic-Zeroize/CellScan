import Foundation
import CoreLocation
import Combine
import UIKit

/// Orchestrates a live recording pass: pulls GPS fixes, reads the radio type,
/// runs periodic throughput probes, accumulates samples, and checkpoints the
/// pass to disk so a crash or force-quit never loses the drive.
@MainActor
final class RecordingEngine: ObservableObject {
    // Live state surfaced to the UI
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed = 0
    @Published private(set) var samples: [Sample] = []
    @Published private(set) var currentRat: RAT = .none
    /// Recent per-sample download measurements, for the speed-colored sparkline.
    @Published private(set) var sparks: [Double?] = []
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var cellCount = 0
    @Published private(set) var lastResult: ThroughputResult?
    @Published private(set) var probing = false
    /// True while recording but the latest GPS fix is missing or too old.
    @Published private(set) var waitingForGPS = false
    @Published private(set) var locationAccess: LocationAccess = .notDetermined
    @Published private(set) var gpsMessage: String?

    // Pass configuration
    @Published private(set) var carrier: Carrier = .verizon
    @Published private(set) var throughputEnabled = true

    let location = LocationManager()
    private let radio = RadioMonitor()
    private let tester = ThroughputTester()
    private let archive: PassArchive

    private var timer: Timer?
    private var passID = UUID()
    private var startedAt = Date()
    private var lastSampleLocation: CLLocation?
    private var lastResultAt: Date?
    private var probeTask: Task<Void, Never>?
    private var gridKeys = Set<String>()
    private var locationSubscription: AnyCancellable?
    private var lastSampleDate = Date.distantPast
    private var lastThroughputDate = Date.distantPast
    private var samplesSinceCheckpoint = 0
    private var lastCheckpointDate = Date.distantPast

    /// Snapshot of settings taken at the start of a pass.
    private var settings = AppSettings.default

    private var sampleInterval: Int { max(1, settings.sampleIntervalSec) }
    private var throughputInterval: Int { settings.throughputIntervalSec }
    private var throughputActive: Bool { throughputEnabled && throughputInterval > 0 }
    /// A probe result is attached to samples for this long after it completes.
    private var resultFreshness: TimeInterval { max(45, Double(throughputInterval) * 2 + 15) }
    /// A GPS fix older than this is treated as lost (tunnel, garage, no sky).
    private var maxFixAge: TimeInterval { max(10, Double(sampleInterval) * 3) }

    init(archive: PassArchive = .standard) {
        self.archive = archive
        location.$access.assign(to: &$locationAccess)
        location.$lastErrorMessage.assign(to: &$gpsMessage)
    }

    // MARK: - Control

    func requestPermission() { location.requestPermission() }

    func start(carrier: Carrier, throughputEnabled: Bool, settings: AppSettings) {
        guard !isRecording else { return }
        self.carrier = carrier
        self.throughputEnabled = throughputEnabled
        self.settings = settings.sanitized()
        reset()
        passID = UUID()
        startedAt = Date()
        isRecording = true
        waitingForGPS = true
        location.requestPermission()
        location.startUpdating()
        currentRat = radio.current()
        UIApplication.shared.isIdleTimerDisabled = true

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keep ticking while the user scrolls
        timer = t

        // Location updates also drive sampling, so recording continues with the
        // screen off (timers don't fire in the background; location callbacks do).
        locationSubscription = location.$location
            .compactMap { $0 }
            .sink { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }

        if throughputActive {
            lastThroughputDate = Date()
            runThroughput()
        }
    }

    /// Stops recording and returns the finished pass, or nil if no samples were
    /// captured (the caller should tell the user nothing was recorded).
    func stop() -> Pass? {
        guard isRecording else { return nil }
        let pass = currentPass()
        teardown()
        if pass.samples.isEmpty {
            clearCheckpoint()
            return nil
        }
        // The checkpoint is cleared by PassStore only after the pass is safely saved.
        return pass
    }

    /// Stops recording and throws the data away.
    func discard() {
        guard isRecording else { return }
        teardown()
        clearCheckpoint()
    }

    /// Writes a crash-recovery snapshot right now (e.g. when the app is backgrounded).
    func checkpointNow() {
        guard isRecording, !samples.isEmpty else { return }
        samplesSinceCheckpoint = 0
        lastCheckpointDate = Date()
        let pass = currentPass()
        let archive = self.archive
        // Best effort: a failed checkpoint only reduces crash protection, it never
        // affects the recording itself, so it is not surfaced as an error.
        Persistence.queue.async { try? archive.writeCheckpoint(pass) }
    }

    private func currentPass() -> Pass {
        Pass(id: passID,
             carrier: carrier,
             startedAt: startedAt,
             durationSec: Int(Date().timeIntervalSince(startedAt)),
             distanceMiles: distanceMeters / AppSettings.metersPerMile,
             samples: samples)
    }

    private func teardown() {
        timer?.invalidate(); timer = nil
        locationSubscription?.cancel(); locationSubscription = nil
        probeTask?.cancel(); probeTask = nil
        probing = false
        location.stopUpdating()
        UIApplication.shared.isIdleTimerDisabled = false
        isRecording = false
        waitingForGPS = false
    }

    private func clearCheckpoint() {
        let archive = self.archive
        Persistence.queue.async { archive.clearCheckpoint() }
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
        lastSampleDate = .distantPast
        lastThroughputDate = .distantPast
        samplesSinceCheckpoint = 0
        lastCheckpointDate = Date()
        gridKeys.removeAll()
    }

    // MARK: - Sampling cadence

    private func tick() {
        guard isRecording else { return }
        let now = Date()
        // Derive elapsed from wall time so it stays accurate after background gaps.
        elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        waitingForGPS = location.location.map { now.timeIntervalSince($0.timestamp) > maxFixAge } ?? true

        if now.timeIntervalSince(lastSampleDate) >= Double(sampleInterval) {
            lastSampleDate = now
            captureSample(now: now)
        }
        if throughputActive, now.timeIntervalSince(lastThroughputDate) >= Double(throughputInterval) {
            lastThroughputDate = now
            runThroughput()
        }
    }

    private func captureSample(now: Date) {
        currentRat = radio.current()
        // No fresh fix → no sample. Re-using a stale position would stamp
        // coverage onto the wrong place (e.g. the tunnel entrance).
        guard let loc = location.location,
              now.timeIntervalSince(loc.timestamp) <= maxFixAge else { return }

        // Distance-interval gating: skip if we haven't moved far enough yet.
        if settings.minSampleDistanceM > 0, let prev = lastSampleLocation,
           loc.distance(from: prev) < settings.minSampleDistanceM {
            return
        }

        // Attach the most recent throughput result if it's still fresh.
        var down: Double?, up: Double?, latency: Double?
        if let r = lastResult, let at = lastResultAt, now.timeIntervalSince(at) < resultFreshness {
            down = r.downMbps; up = r.upMbps; latency = r.latencyMs
        }

        let sample = Sample(t: now,
                            lat: loc.coordinate.latitude,
                            lng: loc.coordinate.longitude,
                            accuracy: loc.horizontalAccuracy,
                            speedMph: loc.speed >= 0 ? loc.speed * AppSettings.mphPerMetersPerSecond : 0,
                            heading: loc.course >= 0 ? loc.course : 0,
                            rat: currentRat,
                            downMbps: down,
                            upMbps: up,
                            latencyMs: latency).sanitized()
        guard sample.hasValidCoordinate else { return }
        samples.append(sample)

        // Sparkline history — driven by measured download speed.
        sparks.append(down)
        if sparks.count > 26 { sparks.removeFirst(sparks.count - 26) }

        // Dedup cell count on the same grid as Pass.mergedCells.
        if let key = CoverageGrid.key(lat: sample.lat, lng: sample.lng, gridMeters: settings.cellMergeMeters) {
            gridKeys.insert(key)
            cellCount = gridKeys.count
        }

        // Distance
        if let prev = lastSampleLocation {
            let d = loc.distance(from: prev)
            if d.isFinite, d < 2000 { distanceMeters += d } // skip GPS jumps
        }
        lastSampleLocation = loc

        samplesSinceCheckpoint += 1
        if samplesSinceCheckpoint >= 10 || now.timeIntervalSince(lastCheckpointDate) >= 30 {
            checkpointNow()
        }
    }

    private func runThroughput() {
        guard probeTask == nil else { return }
        // Adaptive: probe less data when the last measurement was weak/dead.
        let bytes: Int
        switch lastResult?.downMbps {
        case .some(let d) where d < 10: bytes = 600_000
        case .none where lastResultAt != nil: bytes = 400_000
        default: bytes = 1_500_000
        }
        let tester = self.tester
        probing = true
        probeTask = Task { [weak self] in
            let result = await tester.measure(downloadBytes: bytes)
            guard let self, !Task.isCancelled, self.isRecording else { return }
            if let result {
                self.lastResult = result
                self.lastResultAt = Date()
            }
            self.probeTask = nil
            self.probing = false
        }
    }

    // MARK: - Display helpers

    var elapsedString: String {
        let h = elapsed / 3600, m = (elapsed % 3600) / 60, s = elapsed % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

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
        guard let s = location.location?.speed, s >= 0 else { return settings.speedString(mph: 0) }
        return settings.speedString(mph: s * AppSettings.mphPerMetersPerSecond)
    }
    var latencyString: String {
        if !throughputActive { return "off" }
        guard let l = lastResult?.latencyMs else {
            return lastResultAt == nil ? (probing ? "testing…" : "—") : "timeout"
        }
        return String(format: "%.0f ms", l)
    }
    var downloadString: String {
        if !throughputActive { return "off" }
        guard let d = lastResult?.downMbps else {
            return lastResultAt == nil ? (probing ? "testing…" : "—") : "no data"
        }
        return d >= 10 ? String(format: "%.0f Mbps", d) : String(format: "%.1f Mbps", d)
    }
}
