import XCTest
@testable import CellScanCore

final class CSVTests: CoreTestCase {

    func testHeaderAndColumnCount() {
        let csv = Fixtures.drive(samples: 10).csvString()
        let rows = CSVParser.parse(csv)
        XCTAssertEqual(rows.first, CSV.columns)
        XCTAssertEqual(rows.count, 11)
        XCTAssertTrue(rows.allSatisfy { $0.count == 11 })
        XCTAssertTrue(csv.hasSuffix("\n"))
        XCTAssertFalse(csv.hasSuffix("\n\n"))
    }

    func testEmptyPassIsHeaderOnly() {
        let p = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 0, distanceMiles: 0, samples: [])
        XCTAssertEqual(p.csvString(), CSV.header + "\n")
    }

    /// Regression: combining used to emit blank rows between passes.
    func testCombinedCSVHasNoBlankLinesAndOneHeader() {
        let a = Fixtures.drive(samples: 50, carrier: .verizon, seed: 1)
        let b = Fixtures.drive(samples: 0, carrier: .att, seed: 2)
        let c = Fixtures.drive(samples: 70, carrier: .tmobile, startTime: Fixtures.t0 + 10, seed: 3)
        let csv = Pass.combinedCSV([a, b, c])
        XCTAssertFalse(csv.contains("\n\n"))
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.filter { $0 == Substring(CSV.header) }.count, 1)
        let rows = CSVParser.parse(csv)
        XCTAssertEqual(rows.count, 1 + 50 + 70)
        XCTAssertEqual(Set(rows.dropFirst().map { $0[6] }), ["Verizon", "T-Mobile"])
        let stamps = rows.dropFirst().map { $0[0] }
        XCTAssertEqual(stamps, stamps.sorted(), "combined rows are time-ordered")
    }

    func testRowValuesAndEmptyOptionals() {
        let s = Fixtures.sample(lat: 39.123456789, lng: -104.5, rat: .none, down: nil, up: nil, latency: nil)
        let row = CSVParser.parse(CSV.row(s, carrier: .att) + "\n")[0]
        XCTAssertEqual(row[1], "39.123457")
        XCTAssertEqual(row[2], "-104.500000")
        XCTAssertEqual(row[6], "AT&T")
        XCTAssertEqual(row[7], "None")
        XCTAssertEqual(Array(row[8...10]), ["", "", ""])
        XCTAssertTrue(row[0].hasSuffix("Z"), "timestamps are UTC ISO-8601")
    }

    func testNonFiniteValuesNeverReachTheFile() {
        var s = Fixtures.sample()
        s.lat = .nan; s.downMbps = .infinity; s.speedMph = .nan
        let row = CSV.row(s, carrier: .verizon)
        XCTAssertFalse(row.lowercased().contains("nan"))
        XCTAssertFalse(row.lowercased().contains("inf"))
    }

    func testFieldEscaping() {
        XCTAssertEqual(CSV.field("plain"), "plain")
        XCTAssertEqual(CSV.field("a,b"), "\"a,b\"")
        XCTAssertEqual(CSV.field("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSV.field("line\nbreak"), "\"line\nbreak\"")
        let parsed = CSVParser.parse([CSV.field("a,\"b\"\nc"), CSV.field("x")].joined(separator: ",") + "\n")
        XCTAssertEqual(parsed, [["a,\"b\"\nc", "x"]])
    }

    func testFileNames() {
        let p = Fixtures.drive(samples: 2, carrier: .att, startTime: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(p.csvFileName, "atandt_2023-11-14.csv")
        XCTAssertEqual(Fixtures.drive(samples: 1, carrier: .tmobile).csvFileName.prefix(8), "tmobile_")
        let mixed = Pass.combining([p, Fixtures.drive(samples: 2, carrier: .verizon)])
        XCTAssertTrue(mixed.csvFileName.hasPrefix("cellscan_combined_"))
        XCTAssertTrue(CSV.fileName(for: [p, p]).hasPrefix("cellscan_combined_"))
        XCTAssertTrue(CSV.fileName(for: []).hasSuffix(".csv"))
    }

    func testStressLargeExportIsWellFormed() {
        let passes = (0..<5).map { Fixtures.drive(samples: 20_000, carrier: Carrier.allCases[$0 % 4], seed: UInt64($0 + 100)) }
        let csv = CSV.document(for: passes)
        let rows = CSVParser.parse(csv)
        XCTAssertEqual(rows.count, 1 + 100_000)
        XCTAssertTrue(rows.allSatisfy { $0.count == CSV.columns.count })
        for row in rows.dropFirst().prefix(5_000) {
            XCTAssertNotNil(Double(row[1])); XCTAssertNotNil(Double(row[2]))
        }
    }

    func testExportPerformance50k() {
        let p = Fixtures.drive(samples: 50_000, seed: 8)
        measure { _ = p.csvString() }
    }
}

final class CombineTests: CoreTestCase {

    func testCombiningKeepsEverySampleSortedWithItsCarrier() {
        let a = Fixtures.drive(samples: 300, carrier: .verizon, startTime: Fixtures.t0 + 1000, seed: 1)
        let b = Fixtures.drive(samples: 200, carrier: .att, startTime: Fixtures.t0, seed: 2)
        let m = Pass.combining([a, b])
        XCTAssertEqual(m.samples.count, 500)
        XCTAssertEqual(m.samples.map(\.t), m.samples.map(\.t).sorted())
        XCTAssertEqual(m.carrier, .other)
        XCTAssertEqual(Set(m.carriers), [.verizon, .att])
        XCTAssertEqual(m.startedAt, Fixtures.t0)
        XCTAssertEqual(m.durationSec, a.durationSec + b.durationSec)
        XCTAssertEqual(m.distanceMiles, a.distanceMiles + b.distanceMiles, accuracy: 1e-9)
        XCTAssertNotEqual(m.id, a.id); XCTAssertNotEqual(m.id, b.id)
        XCTAssertEqual(m.samples.filter { $0.carrier == .verizon }.count, 300)
    }

    func testSameCarrierCombineKeepsCarrier() {
        let m = Pass.combining([Fixtures.drive(samples: 5, carrier: .tmobile, seed: 1),
                                Fixtures.drive(samples: 5, carrier: .tmobile, seed: 2)])
        XCTAssertEqual(m.carrier, .tmobile)
        XCTAssertEqual(m.carrierLabel, "T-Mobile")
    }

    func testRecombiningPreservesOriginalCarriers() {
        let ab = Pass.combining([Fixtures.drive(samples: 4, carrier: .verizon, seed: 1),
                                 Fixtures.drive(samples: 4, carrier: .att, seed: 2)])
        let abc = Pass.combining([ab, Fixtures.drive(samples: 4, carrier: .tmobile, seed: 3)])
        XCTAssertEqual(Set(abc.carriers), [.verizon, .att, .tmobile])
        XCTAssertEqual(CSVParser.parse(abc.csvString()).dropFirst().filter { $0[6] == "AT&T" }.count, 4)
    }

    func testCombiningEdgeCases() {
        let empty = Pass.combining([])
        XCTAssertTrue(empty.samples.isEmpty)
        let lone = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 5, distanceMiles: 1, samples: [])
        XCTAssertEqual(Pass.combining([lone, lone]).carrier, .att)
    }
}
