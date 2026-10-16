import Foundation
@testable import CellScanCore

/// Deterministic RNG so stress tests are reproducible run to run.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Fixtures {
    static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    /// A simulated drive: a random walk from a start point, one sample every
    /// `interval` seconds, with realistic gaps in throughput / dead zones.
    static func drive(samples count: Int,
                      carrier: Carrier = .verizon,
                      start: (lat: Double, lng: Double) = (39.7392, -104.9903),
                      startTime: Date = t0,
                      interval: TimeInterval = 3,
                      seed: UInt64 = 1) -> Pass {
        var rng = SeededRNG(seed: seed)
        var lat = start.lat, lng = start.lng
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            lat += Double.random(in: -0.0004...0.0006, using: &rng)
            lng += Double.random(in: -0.0004...0.0006, using: &rng)
            let rat = RAT.allCases.randomElement(using: &rng)!
            let hasProbe = rat != .none && Bool.random(using: &rng)
            samples.append(Sample(
                t: startTime.addingTimeInterval(Double(i) * interval),
                lat: lat, lng: lng,
                accuracy: Double.random(in: 3...40, using: &rng),
                speedMph: Double.random(in: 0...80, using: &rng),
                heading: Double.random(in: 0..<360, using: &rng),
                rat: rat,
                downMbps: hasProbe ? Double.random(in: 0.1...400, using: &rng) : nil,
                upMbps: hasProbe ? Double.random(in: 0.1...80, using: &rng) : nil,
                latencyMs: hasProbe ? Double.random(in: 10...900, using: &rng) : nil))
        }
        return Pass(carrier: carrier, startedAt: startTime,
                    durationSec: Int(Double(count) * interval),
                    distanceMiles: Double(count) * 0.02, samples: samples)
    }

    static func sample(at t: Date = t0, lat: Double = 40, lng: Double = -105,
                       rat: RAT = .lte, down: Double? = 50, up: Double? = 10,
                       latency: Double? = 40, carrier: Carrier? = nil) -> Sample {
        Sample(t: t, lat: lat, lng: lng, accuracy: 5, speedMph: 30, heading: 90,
               rat: rat, downMbps: down, upMbps: up, latencyMs: latency, carrier: carrier)
    }

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellscan-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Minimal RFC 4180 parser used to prove exported CSV is well-formed.
enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if inQuotes {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                case "\r": continue
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
