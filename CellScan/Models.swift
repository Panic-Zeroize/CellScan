import SwiftUI
import CoreLocation

// MARK: - Carrier

/// Carrier is tagged manually — iOS no longer exposes the carrier name to apps.
enum Carrier: String, CaseIterable, Codable, Identifiable {
    case verizon = "Verizon"
    case att = "AT&T"
    case tmobile = "T-Mobile"
    case other = "Other"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .verizon: return Color(hex: 0xEE2A2A)
        case .att: return Color(hex: 0x00A8E0)
        case .tmobile: return Color(hex: 0xE20074)
        case .other: return Color(hex: 0x6B7280)
        }
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

    var color: Color {
        switch self {
        case .fiveG: return Color(hex: 0x34D399)
        case .lte: return Color(hex: 0x38BDF8)
        case .threeG: return Color(hex: 0xFBBF24)
        case .twoG: return Color(hex: 0xFB923C)
        case .none: return Color(hex: 0xF43F5E)
        }
    }

    var label: String { self == .none ? "No service" : rawValue }

    /// Map a CoreTelephony `CTRadioAccessTechnology*` constant to a bucket.
    static func from(techString tech: String?) -> RAT {
        guard let t = tech else { return .none }
        if t.contains("NR") { return .fiveG }                 // NR / NRNSA
        if t.contains("LTE") { return .lte }
        if t.contains("WCDMA") || t.contains("HSDPA") || t.contains("HSUPA")
            || t.contains("EVDO") || t.contains("eHRPD") { return .threeG }
        if t.contains("GPRS") || t.contains("Edge") || t.contains("CDMA1x") { return .twoG }
        return .threeG
    }
}

// MARK: - Throughput coverage tiers (map coloring per user's choice)

enum CoverageTier: String, Codable {
    case great, good, ok, poor, dead

    var color: Color {
        switch self {
        case .great: return Color(hex: 0x34D399)
        case .good: return Color(hex: 0x38BDF8)
        case .ok: return Color(hex: 0xFBBF24)
        case .poor: return Color(hex: 0xFB923C)
        case .dead: return Color(hex: 0xF43F5E)
        }
    }

    var legendLabel: String {
        switch self {
        case .great: return "> 120 Mbps"
        case .good: return "30–120"
        case .ok: return "5–30"
        case .poor: return "< 5"
        case .dead: return "No data"
        }
    }

    /// Buckets a measured download rate. `nil` means the test never returned data.
    static func from(downMbps: Double?) -> CoverageTier {
        guard let d = downMbps else { return .dead }
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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Cell (aggregated coverage point shown on the map)

struct Cell: Identifiable {
    var id = UUID()
    var lat: Double
    var lng: Double
    var rat: RAT              // worst RAT seen in the bucket
    var downMbps: Double?     // representative (worst non-nil) download
    var upMbps: Double?
    var latencyMs: Double?
    var accuracy: Double
    var speedMph: Double
    var sampleCount: Int
    var time: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    var coverage: CoverageTier { CoverageTier.from(downMbps: downMbps) }
}

// MARK: - Pass

struct Pass: Codable, Identifiable {
    var id = UUID()
    var carrier: Carrier
    var startedAt: Date
    var durationSec: Int
    var distanceMiles: Double
    var samples: [Sample]

    // Derived --------------------------------------------------------------

    /// Merge raw samples into coverage cells on a ~110 m grid, worst sample wins.
    var cells: [Cell] {
        guard !samples.isEmpty else { return [] }
        struct Bucket {
            var latSum = 0.0, lngSum = 0.0
            var count = 0
            var worstRat = RAT.fiveG
            var minDown: Double? = nil
            var up: Double? = nil
            var latency: Double? = nil
            var accuracy = 0.0
            var speed = 0.0
            var time = Date()
        }
        var buckets: [String: Bucket] = [:]
        for s in samples {
            let key = "\(Int(s.lat * 900))_\(Int(s.lng * 900))" // ~120 m cells
            var b = buckets[key] ?? Bucket()
            b.latSum += s.lat; b.lngSum += s.lng; b.count += 1
            if s.rat.tier < b.worstRat.tier { b.worstRat = s.rat }
            if let d = s.downMbps {
                b.minDown = b.minDown.map { Swift.min($0, d) } ?? d
            }
            if let u = s.upMbps { b.up = u }
            if let l = s.latencyMs { b.latency = l }
            b.accuracy = s.accuracy
            b.speed = s.speedMph
            b.time = s.t
            buckets[key] = b
        }
        return buckets.values.map { b in
            Cell(lat: b.latSum / Double(b.count),
                 lng: b.lngSum / Double(b.count),
                 rat: b.worstRat,
                 downMbps: b.minDown,
                 upMbps: b.up,
                 latencyMs: b.latency,
                 accuracy: b.accuracy,
                 speedMph: b.speed,
                 sampleCount: b.count,
                 time: b.time)
        }
        .sorted { $0.time < $1.time }
    }

    var deadZoneCount: Int { cells.filter { $0.rat == .none }.count }

    var durationString: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%02d:%02d", m, s)
    }

    // CSV -----------------------------------------------------------------

    var csvFileName: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let name = carrier.displayName.lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: " ", with: "")
        return "\(name)_\(df.string(from: startedAt)).csv"
    }

    func csvString() -> String {
        let iso = ISO8601DateFormatter()
        var out = "timestamp,lat,lng,acc,spd,hdg,carrier,rat,down_mbps,up_mbps,lat_ms\n"
        for s in samples {
            let cols: [String] = [
                iso.string(from: s.t),
                String(format: "%.6f", s.lat),
                String(format: "%.6f", s.lng),
                String(format: "%.0f", s.accuracy),
                String(format: "%.0f", s.speedMph),
                String(format: "%.0f", s.heading),
                carrier.displayName,
                s.rat.rawValue,
                s.downMbps.map { String(format: "%.1f", $0) } ?? "",
                s.upMbps.map { String(format: "%.1f", $0) } ?? "",
                s.latencyMs.map { String(format: "%.0f", $0) } ?? ""
            ]
            out += cols.joined(separator: ",") + "\n"
        }
        return out
    }
}
