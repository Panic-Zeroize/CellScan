import Foundation

// Pure data model. Foundation-only on purpose: it is compiled into the app and
// into the Linux/macOS test package (see Package.swift). UI colors and
// CoreLocation coordinates live in Views/ModelUI.swift.

// MARK: - Carrier

/// Carrier is tagged manually — iOS no longer exposes the carrier name to apps.
enum Carrier: String, CaseIterable, Codable, Identifiable {
    case verizon = "Verizon"
    case att = "AT&T"
    case tmobile = "T-Mobile"
    case other = "Other"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// Unknown values (e.g. written by a newer app version) decode as `.other`
    /// instead of failing the whole file.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Carrier(rawValue: raw) ?? .other
    }
}

// MARK: - Radio Access Technology

/// Radio access technology. Unlike the carrier *name*, the radio type is still
/// readable natively via CoreTelephony, so we capture it for the CSV.
enum RAT: String, Codable, CaseIterable {
    case fiveG = "5G"
    case lte = "LTE"
    case threeG = "3G"
    case twoG = "2G"
    case none = "None"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RAT(rawValue: raw) ?? .none
    }

    /// Higher = better. Used for the sparkline height and "worst sample wins" merge.
    var tier: Int {
        switch self {
        case .fiveG: return 4
        case .lte: return 3
        case .threeG: return 2
        case .twoG: return 1
        case .none: return 0
        }
    }

    var label: String { self == .none ? "No service" : rawValue }

    /// Nearest RAT bucket for an averaged tier value.
    static func from(tier: Int) -> RAT {
        switch max(0, min(4, tier)) {
        case 4: return .fiveG
        case 3: return .lte
        case 2: return .threeG
        case 1: return .twoG
        default: return .none
        }
    }

    /// Map a CoreTelephony `CTRadioAccessTechnology*` constant to a bucket.
    static func from(techString tech: String?) -> RAT {
        guard let t = tech, !t.isEmpty else { return .none }
        if t.contains("NR") { return .fiveG }                 // NR / NRNSA
        if t.contains("LTE") { return .lte }
        if t.contains("WCDMA") || t.contains("HSDPA") || t.contains("HSUPA")
            || t.contains("EVDO") || t.contains("eHRPD") { return .threeG }
        if t.contains("GPRS") || t.contains("Edge") || t.contains("CDMA1x") { return .twoG }
        return .threeG
    }
}

// MARK: - Throughput coverage tiers (map coloring)

enum CoverageTier: String, Codable {
    case great, good, ok, poor, dead

    /// Height rank for the recording sparkline (great = tallest).
    var rank: Int {
        switch self {
        case .great: return 4
        case .good: return 3
        case .ok: return 2
        case .poor: return 1
        case .dead: return 0
        }
    }

    /// Buckets a measured download rate. `nil` means the test never returned data.
    static func from(downMbps: Double?) -> CoverageTier {
        guard let d = downMbps, d.isFinite else { return .dead }
        if d >= 120 { return .great }
        if d >= 30 { return .good }
        if d >= 5 { return .ok }
        if d > 0 { return .poor }
        return .dead
    }
}

// MARK: - Sample

/// One raw measurement captured while recording.
struct Sample: Codable, Identifiable {
    var id = UUID()
    var t: Date
    var lat: Double
    var lng: Double
    var accuracy: Double      // meters
    var speedMph: Double
    var heading: Double
    var rat: RAT
    var downMbps: Double?     // nil if no throughput test ran / it timed out
    var upMbps: Double?
    var latencyMs: Double?
    /// Carrier this row was recorded on. `nil` for single-carrier passes recorded
    /// before combining existed — the pass carrier applies. Set when passes from
    /// different carriers are merged so every row keeps its own carrier.
    var carrier: Carrier?

    /// True when the coordinate is a real point on Earth. Corrupt or non-finite
    /// coordinates are skipped by every aggregation instead of crashing it.
    var hasValidCoordinate: Bool {
        lat.isFinite && lng.isFinite && abs(lat) <= 90 && abs(lng) <= 180
    }

    /// Replaces non-finite / negative readings with safe values so a single bad
    /// sensor reading can never poison JSON encoding or the averages.
    func sanitized() -> Sample {
        var s = self
        s.accuracy = Self.clean(accuracy) ?? 0
        s.speedMph = Self.clean(speedMph) ?? 0
        s.heading = Self.clean(heading) ?? 0
        s.downMbps = downMbps.flatMap(Self.clean)
        s.upMbps = upMbps.flatMap(Self.clean)
        s.latencyMs = latencyMs.flatMap(Self.clean)
        return s
    }

    private static func clean(_ v: Double) -> Double? {
        v.isFinite ? max(0, v) : nil
    }
}

// MARK: - Cell (aggregated coverage point shown on the map)

struct Cell: Identifiable {
    /// Deterministic (carrier + grid bucket), so map selection and SwiftUI
    /// identity survive recomputation.
    var id: String
    var lat: Double
    var lng: Double
    var carrier: Carrier      // which carrier/layer this cell belongs to
    var rat: RAT              // averaged (or worst) RAT in the bucket
    var downMbps: Double?     // averaged (or worst) download
    var upMbps: Double?
    var latencyMs: Double?
    var accuracy: Double
    var speedMph: Double
    var sampleCount: Int
    var time: Date

    var coverage: CoverageTier { CoverageTier.from(downMbps: downMbps) }
}

// MARK: - Grid

enum CoverageGrid {
    /// Grid bucket key for a coordinate, shared by the live recording counter and
    /// `Pass.mergedCells` so both always agree. `nil` for invalid coordinates.
    static func key(lat: Double, lng: Double, gridMeters: Double) -> String? {
        guard lat.isFinite, lng.isFinite, abs(lat) <= 90, abs(lng) <= 180 else { return nil }
        let size = gridMeters.isFinite ? max(gridMeters, 10) : 120
        let cellDeg = size / 111_000.0
        return "\(Int((lat / cellDeg).rounded(.down)))_\(Int((lng / cellDeg).rounded(.down)))"
    }
}

// MARK: - Coverage breakdown

/// Per-RAT share of a set of cells, used by the Home cards and Summary screen.
struct CoverageBreakdown {
    struct Segment { var rat: RAT; var count: Int; var fraction: Double
        var percent: Int { Int((fraction * 100).rounded()) }
    }

    static let displayOrder: [RAT] = [.fiveG, .lte, .threeG, .twoG, .none]

    let totalCells: Int
    let deadCells: Int
    let segments: [Segment]

    init(cells: [Cell]) {
        totalCells = cells.count
        var counts: [RAT: Int] = [:]
        for c in cells { counts[c.rat, default: 0] += 1 }
        deadCells = counts[.none] ?? 0
        let total = Double(max(1, cells.count))
        // 2G is rare; only list it when present so the default view stays tidy.
        segments = Self.displayOrder
            .filter { $0 != .twoG || (counts[.twoG] ?? 0) > 0 }
            .map { rat in
                let n = counts[rat] ?? 0
                return Segment(rat: rat, count: n, fraction: Double(n) / total)
            }
    }
}

// MARK: - Pass

struct Pass: Codable, Identifiable {
    var id = UUID()
    var carrier: Carrier
    var startedAt: Date
    var durationSec: Int
    var distanceMiles: Double
    var samples: [Sample]

    init(id: UUID = UUID(), carrier: Carrier, startedAt: Date, durationSec: Int,
         distanceMiles: Double, samples: [Sample]) {
        self.id = id
        self.carrier = carrier
        self.startedAt = startedAt
        self.durationSec = max(0, durationSec)
        self.distanceMiles = distanceMiles.isFinite ? max(0, distanceMiles) : 0
        self.samples = samples
    }

    private enum CodingKeys: String, CodingKey {
        case id, carrier, startedAt, durationSec, distanceMiles, samples
    }

    /// Lenient decoding: a single unreadable sample is dropped instead of
    /// making the whole pass (and every other pass in the file) unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        carrier = try c.decodeIfPresent(Carrier.self, forKey: .carrier) ?? .other
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        durationSec = max(0, (try? c.decode(Int.self, forKey: .durationSec)) ?? 0)
        let miles = (try? c.decode(Double.self, forKey: .distanceMiles)) ?? 0
        distanceMiles = miles.isFinite ? max(0, miles) : 0
        let lossy = (try? c.decode([Lossy<Sample>].self, forKey: .samples)) ?? []
        samples = lossy.compactMap(\.value)
    }

    // Derived --------------------------------------------------------------

    /// Carrier for a given row (rows keep their own carrier after a mixed combine).
    func carrier(of sample: Sample) -> Carrier { sample.carrier ?? carrier }

    /// Distinct carriers present in this pass, in first-seen order.
    var carriers: [Carrier] {
        var seen: [Carrier] = []
        for s in samples {
            let c = carrier(of: s)
            if !seen.contains(c) { seen.append(c) }
        }
        return seen.isEmpty ? [carrier] : seen
    }

    /// "Verizon", or "Verizon + AT&T" for a combined multi-carrier pass.
    var carrierLabel: String { carriers.map(\.displayName).joined(separator: " + ") }

    /// Merge raw samples into coverage cells on a grid, one set per carrier. When
    /// `average` is true samples in the same location are averaged (RAT tier,
    /// download, up, latency); otherwise the worst sample in the bucket wins.
    func mergedCells(gridMeters: Double = 120, average: Bool = true) -> [Cell] {
        guard !samples.isEmpty else { return [] }
        struct Bucket {
            var carrier: Carrier
            var latSum = 0.0, lngSum = 0.0, count = 0
            var ratTierSum = 0
            var worstRat = RAT.fiveG
            var downSum = 0.0, downN = 0
            var minDown: Double?
            var upSum = 0.0, upN = 0
            var minUp: Double?
            var latSumMs = 0.0, latN = 0
            var maxLatency: Double?
            var accuracy = 0.0, speed = 0.0
            var time = Date.distantPast
        }
        var buckets: [String: Bucket] = [:]
        for raw in samples {
            let s = raw.sanitized()
            let c = carrier(of: s)
            guard let grid = CoverageGrid.key(lat: s.lat, lng: s.lng, gridMeters: gridMeters) else { continue }
            let key = "\(c.rawValue)|\(grid)"
            var b = buckets[key] ?? Bucket(carrier: c)
            b.latSum += s.lat; b.lngSum += s.lng; b.count += 1
            b.ratTierSum += s.rat.tier
            if s.rat.tier < b.worstRat.tier { b.worstRat = s.rat }
            if let d = s.downMbps {
                b.downSum += d; b.downN += 1
                b.minDown = b.minDown.map { Swift.min($0, d) } ?? d
            }
            if let u = s.upMbps {
                b.upSum += u; b.upN += 1
                b.minUp = b.minUp.map { Swift.min($0, u) } ?? u
            }
            if let l = s.latencyMs {
                b.latSumMs += l; b.latN += 1
                b.maxLatency = b.maxLatency.map { Swift.max($0, l) } ?? l
            }
            if s.t >= b.time {   // newest sample supplies accuracy/speed/time
                b.time = s.t
                b.accuracy = s.accuracy
                b.speed = s.speedMph
            }
            buckets[key] = b
        }
        return buckets.map { key, b in
            let n = Double(b.count)
            let rat: RAT = average
                ? RAT.from(tier: Int((Double(b.ratTierSum) / n).rounded()))
                : b.worstRat
            let down: Double? = average ? (b.downN > 0 ? b.downSum / Double(b.downN) : nil) : b.minDown
            let up: Double? = average ? (b.upN > 0 ? b.upSum / Double(b.upN) : nil) : b.minUp
            let latency: Double? = average ? (b.latN > 0 ? b.latSumMs / Double(b.latN) : nil) : b.maxLatency
            return Cell(id: key,
                        lat: b.latSum / n,
                        lng: b.lngSum / n,
                        carrier: b.carrier,
                        rat: rat,
                        downMbps: down,
                        upMbps: up,
                        latencyMs: latency,
                        accuracy: b.accuracy,
                        speedMph: b.speed,
                        sampleCount: b.count,
                        time: b.time)
        }
        .sorted { ($0.time, $0.id) < ($1.time, $1.id) }
    }

    /// Merge several passes into one new pass: all samples concatenated and
    /// sorted by time (each keeps its own carrier), durations and distances
    /// summed. The pass carrier is the shared one, or `.other` when mixed.
    static func combining(_ passes: [Pass]) -> Pass {
        let allSamples = passes
            .flatMap { p in p.samples.map { s -> Sample in
                var s = s
                s.carrier = p.carrier(of: s)
                return s
            } }
            .sorted { $0.t < $1.t }
        let carriers = Set(allSamples.compactMap(\.carrier) + passes.filter { $0.samples.isEmpty }.map(\.carrier))
        let carrier: Carrier = carriers.count == 1 ? (carriers.first ?? .other) : .other
        return Pass(carrier: carrier,
                    startedAt: passes.map(\.startedAt).min() ?? Date(),
                    durationSec: passes.reduce(0) { $0 + $1.durationSec },
                    distanceMiles: passes.reduce(0.0) { $0 + $1.distanceMiles },
                    samples: allSamples)
    }

    var durationString: String {
        let total = max(0, durationSec)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Decodes an element if possible and yields `nil` otherwise, so one bad
/// element never fails the surrounding array.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
