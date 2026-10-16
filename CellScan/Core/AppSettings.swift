import Foundation

/// User-tunable recording + display options. Defaults match the original prototype.
struct AppSettings: Codable, Equatable {
    var sampleIntervalSec: Int = 3        // time between GPS samples
    var throughputIntervalSec: Int = 20   // time between speed probes (0 = off)
    var minSampleDistanceM: Double = 0     // 0 = time-based only
    var cellMergeMeters: Double = 120      // how close samples group into one cell
    var averageCells: Bool = true          // true = average, false = worst-case
    var throughputDefaultOn: Bool = true   // default state of the New Pass toggle
    var metric: Bool = false               // km / km-h vs mi / mph

    static let `default` = AppSettings()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case sampleIntervalSec, throughputIntervalSec, minSampleDistanceM,
             cellMergeMeters, averageCells, throughputDefaultOn, metric
    }

    /// Missing or malformed keys fall back to their default individually, so a
    /// settings blob from an older/newer version never resets everything.
    init(from decoder: Decoder) throws {
        let d = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sampleIntervalSec = (try? c.decode(Int.self, forKey: .sampleIntervalSec)) ?? d.sampleIntervalSec
        throughputIntervalSec = (try? c.decode(Int.self, forKey: .throughputIntervalSec)) ?? d.throughputIntervalSec
        minSampleDistanceM = (try? c.decode(Double.self, forKey: .minSampleDistanceM)) ?? d.minSampleDistanceM
        cellMergeMeters = (try? c.decode(Double.self, forKey: .cellMergeMeters)) ?? d.cellMergeMeters
        averageCells = (try? c.decode(Bool.self, forKey: .averageCells)) ?? d.averageCells
        throughputDefaultOn = (try? c.decode(Bool.self, forKey: .throughputDefaultOn)) ?? d.throughputDefaultOn
        metric = (try? c.decode(Bool.self, forKey: .metric)) ?? d.metric
        self = sanitized()
    }

    /// Clamps every value into a range the recorder can safely run with.
    func sanitized() -> AppSettings {
        var s = self
        s.sampleIntervalSec = min(max(sampleIntervalSec, 1), 60)
        s.throughputIntervalSec = throughputIntervalSec <= 0 ? 0 : min(max(throughputIntervalSec, 5), 600)
        s.minSampleDistanceM = minSampleDistanceM.isFinite ? min(max(minSampleDistanceM, 0), 1000) : 0
        s.cellMergeMeters = cellMergeMeters.isFinite ? min(max(cellMergeMeters, 10), 2000) : 120
        return s
    }

    // Choices offered in the Settings UI (value, label)
    static let sampleIntervals: [(Int, String)] =
        [(1, "1s"), (2, "2s"), (3, "3s (default)"), (5, "5s"), (10, "10s")]
    static let throughputIntervals: [(Int, String)] =
        [(10, "10s"), (20, "20s (default)"), (30, "30s"), (60, "60s"), (0, "Off")]
    static let distances: [(Double, String)] =
        [(0, "Off (default)"), (10, "10 m"), (25, "25 m"), (50, "50 m"), (100, "100 m")]
    static let mergeRadii: [(Double, String)] =
        [(60, "60 m"), (120, "120 m (default)"), (250, "250 m"), (500, "500 m")]

    // Display helpers ------------------------------------------------------

    static let metersPerMile = 1609.344
    static let mphPerMetersPerSecond = 2.2369362920544

    func speedString(mph: Double) -> String {
        let v = mph.isFinite ? max(0, mph) : 0
        return metric ? "\(Int((v * 1.609344).rounded())) km/h" : "\(Int(v.rounded())) mph"
    }
    func distanceString(miles: Double) -> String {
        let v = miles.isFinite ? max(0, miles) : 0
        return metric ? String(format: "%.1f km", v * 1.609344) : String(format: "%.1f mi", v)
    }
}
