import Foundation

/// CSV export. One header, one row per sample, RFC 4180 quoting, no blank lines —
/// ArcGIS / Excel / Numbers import it directly.
enum CSV {
    static let columns = ["timestamp", "lat", "lng", "acc", "spd", "hdg",
                          "carrier", "rat", "down_mbps", "up_mbps", "lat_ms"]
    static var header: String { columns.joined(separator: ",") }

    /// One formatter per export (not per row, and no shared mutable state).
    static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    /// Full document for one or more passes, rows sorted by time when combining.
    static func document(for passes: [Pass]) -> String {
        let iso = makeTimestampFormatter()
        var lines: [String] = [header]
        let rows: [(Pass, Sample)] = passes.flatMap { p in p.samples.map { (p, $0) } }
        let ordered = passes.count > 1 ? rows.sorted { $0.1.t < $1.1.t } : rows
        lines.reserveCapacity(ordered.count + 1)
        for (pass, sample) in ordered {
            lines.append(row(sample, carrier: pass.carrier(of: sample), formatter: iso))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func row(_ raw: Sample, carrier: Carrier,
                    formatter iso: ISO8601DateFormatter = makeTimestampFormatter()) -> String {
        let s = raw.sanitized()
        let cols: [String] = [
            iso.string(from: s.t),
            coord(s.lat),
            coord(s.lng),
            String(format: "%.0f", s.accuracy),
            String(format: "%.0f", s.speedMph),
            String(format: "%.0f", s.heading),
            field(carrier.displayName),
            field(s.rat.rawValue),
            s.downMbps.map { String(format: "%.1f", $0) } ?? "",
            s.upMbps.map { String(format: "%.1f", $0) } ?? "",
            s.latencyMs.map { String(format: "%.0f", $0) } ?? ""
        ]
        return cols.joined(separator: ",")
    }

    /// Quotes a field when it contains a delimiter, quote or line break.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func coord(_ v: Double) -> String {
        v.isFinite ? String(format: "%.6f", v) : ""
    }

    /// Suggested file name: `verizon_2026-10-16.csv`, or `combined_…` for several
    /// passes / a mixed-carrier pass.
    static func fileName(for passes: [Pass], now: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        if passes.count == 1, let p = passes.first, p.carriers.count == 1 {
            let name = p.carriers[0].displayName.lowercased()
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
            return "\(name)_\(df.string(from: p.startedAt)).csv"
        }
        let date = passes.map(\.startedAt).min() ?? now
        return "cellscan_combined_\(df.string(from: date)).csv"
    }
}

extension Pass {
    func csvString() -> String { CSV.document(for: [self]) }
    var csvFileName: String { CSV.fileName(for: [self]) }
    static func combinedCSV(_ passes: [Pass]) -> String { CSV.document(for: passes) }
}
