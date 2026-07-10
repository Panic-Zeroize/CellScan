import Foundation
import Combine

/// User-tunable recording + display options. Defaults match the original prototype.
struct AppSettings: Codable, Equatable {
    var sampleIntervalSec: Int = 3        // time between GPS samples
    var throughputIntervalSec: Int = 20   // time between speed probes
    var minSampleDistanceM: Double = 0     // 0 = time-based only
    var cellMergeMeters: Double = 120      // how close samples group into one cell
    var averageCells: Bool = true          // true = average, false = worst-case
    var throughputDefaultOn: Bool = true   // default state of the New Pass toggle
    var metric: Bool = false               // km / km-h vs mi / mph

    static let `default` = AppSettings()

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

    func speedString(mph: Double) -> String {
        metric ? "\(Int((mph * 1.60934).rounded())) km/h" : "\(Int(mph.rounded())) mph"
    }
    func distanceString(miles: Double) -> String {
        metric ? String(format: "%.1f km", miles * 1.60934) : String(format: "%.1f mi", miles)
    }
}

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let key = "cellscan.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    func reset() { settings = .default }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
