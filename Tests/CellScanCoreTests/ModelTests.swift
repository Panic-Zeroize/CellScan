import XCTest
@testable import CellScanCore

final class ModelTests: CoreTestCase {

    // MARK: - RAT / tiers

    func testRATFromCoreTelephonyConstants() {
        let cases: [(String?, RAT)] = [
            ("CTRadioAccessTechnologyNR", .fiveG), ("CTRadioAccessTechnologyNRNSA", .fiveG),
            ("CTRadioAccessTechnologyLTE", .lte),
            ("CTRadioAccessTechnologyWCDMA", .threeG), ("CTRadioAccessTechnologyHSDPA", .threeG),
            ("CTRadioAccessTechnologyHSUPA", .threeG), ("CTRadioAccessTechnologyCDMAEVDORev0", .threeG),
            ("CTRadioAccessTechnologyeHRPD", .threeG),
            ("CTRadioAccessTechnologyGPRS", .twoG), ("CTRadioAccessTechnologyEdge", .twoG),
            ("CTRadioAccessTechnologyCDMA1x", .twoG),
            (nil, .none), ("", .none),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(RAT.from(techString: input), expected, "\(input ?? "nil")")
        }
    }

    func testRATFromTierClampsOutOfRange() {
        XCTAssertEqual(RAT.from(tier: -5), RAT.none)
        XCTAssertEqual(RAT.from(tier: 99), .fiveG)
        for rat in RAT.allCases { XCTAssertEqual(RAT.from(tier: rat.tier), rat) }
    }

    func testCoverageTierBoundaries() {
        XCTAssertEqual(CoverageTier.from(downMbps: nil), .dead)
        XCTAssertEqual(CoverageTier.from(downMbps: 0), .dead)
        XCTAssertEqual(CoverageTier.from(downMbps: -3), .dead)
        XCTAssertEqual(CoverageTier.from(downMbps: .nan), .dead)
        XCTAssertEqual(CoverageTier.from(downMbps: .infinity), .dead)
        XCTAssertEqual(CoverageTier.from(downMbps: 0.01), .poor)
        XCTAssertEqual(CoverageTier.from(downMbps: 4.999), .poor)
        XCTAssertEqual(CoverageTier.from(downMbps: 5), .ok)
        XCTAssertEqual(CoverageTier.from(downMbps: 30), .good)
        XCTAssertEqual(CoverageTier.from(downMbps: 120), .great)
    }

    // MARK: - Lenient decoding

    func testUnknownEnumValuesDecodeInsteadOfFailing() throws {
        let json = #"{"id":"\#(UUID())","t":0,"lat":1,"lng":2,"accuracy":3,"speedMph":4,"heading":5,"rat":"6G","carrier":"Starlink"}"#
        let s = try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
        XCTAssertEqual(s.rat, RAT.none)
        XCTAssertEqual(s.carrier, .other)
    }

    func testLegacySampleWithoutCarrierDecodes() throws {
        let json = #"{"id":"\#(UUID())","t":0,"lat":1,"lng":2,"accuracy":3,"speedMph":4,"heading":5,"rat":"LTE","downMbps":12.5}"#
        let s = try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
        XCTAssertNil(s.carrier)
        XCTAssertEqual(s.downMbps, 12.5)
    }

    func testPassDropsOnlyTheBadSample() throws {
        let good = #"{"id":"\#(UUID())","t":0,"lat":1,"lng":2,"accuracy":3,"speedMph":4,"heading":5,"rat":"LTE"}"#
        let bad = #"{"id":"not-a-uuid","t":"yesterday"}"#
        let json = #"{"id":"\#(UUID())","carrier":"Verizon","startedAt":0,"durationSec":-5,"distanceMiles":1,"samples":[\#(good),\#(bad),\#(good.replacingOccurrences(of: "LTE", with: "5G"))]}"#
        let p = try JSONDecoder().decode(Pass.self, from: Data(json.utf8))
        XCTAssertEqual(p.samples.count, 2)
        XCTAssertEqual(p.durationSec, 0, "negative durations are clamped")
    }

    // MARK: - Sanitizing

    func testSanitizedRemovesNonFiniteAndNegativeValues() {
        var s = Fixtures.sample()
        s.accuracy = .nan; s.speedMph = -.infinity; s.heading = -10
        s.downMbps = .infinity; s.upMbps = .nan; s.latencyMs = -1
        let c = s.sanitized()
        XCTAssertEqual(c.accuracy, 0); XCTAssertEqual(c.speedMph, 0); XCTAssertEqual(c.heading, 0)
        XCTAssertNil(c.downMbps); XCTAssertNil(c.upMbps)
        XCTAssertEqual(c.latencyMs, 0)
    }

    func testCoordinateValidity() {
        XCTAssertTrue(Fixtures.sample(lat: 90, lng: 180).hasValidCoordinate)
        XCTAssertTrue(Fixtures.sample(lat: -90, lng: -180).hasValidCoordinate)
        XCTAssertFalse(Fixtures.sample(lat: 91, lng: 0).hasValidCoordinate)
        XCTAssertFalse(Fixtures.sample(lat: .nan, lng: 0).hasValidCoordinate)
        XCTAssertFalse(Fixtures.sample(lat: 0, lng: .infinity).hasValidCoordinate)
        XCTAssertFalse(Fixtures.sample(lat: 1e300, lng: 0).hasValidCoordinate)
    }

    // MARK: - Grid

    func testGridKeyRejectsGarbageAndNeverTraps() {
        XCTAssertNil(CoverageGrid.key(lat: .nan, lng: 0, gridMeters: 120))
        XCTAssertNil(CoverageGrid.key(lat: 1e300, lng: 0, gridMeters: 120))
        XCTAssertNotNil(CoverageGrid.key(lat: 0, lng: 0, gridMeters: 0), "tiny grids clamp to 10 m")
        XCTAssertNotNil(CoverageGrid.key(lat: 0, lng: 0, gridMeters: -50))
        XCTAssertNotNil(CoverageGrid.key(lat: 0, lng: 0, gridMeters: .nan))
        XCTAssertNotNil(CoverageGrid.key(lat: 90, lng: 180, gridMeters: 10))
        XCTAssertNotNil(CoverageGrid.key(lat: -90, lng: -180, gridMeters: 10))
    }

    func testGridKeyIsStableAndSeparatesHemispheres() {
        let a = CoverageGrid.key(lat: 0.0001, lng: 0.0001, gridMeters: 120)
        let b = CoverageGrid.key(lat: -0.0001, lng: -0.0001, gridMeters: 120)
        XCTAssertNotEqual(a, b, "rounding down must not fold -0.0001 into the 0 bucket")
        XCTAssertEqual(a, CoverageGrid.key(lat: 0.0001, lng: 0.0001, gridMeters: 120))
    }

    // MARK: - Pass helpers

    func testDurationStringFormats() {
        func pass(_ s: Int) -> Pass { Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: s, distanceMiles: 0, samples: []) }
        XCTAssertEqual(pass(0).durationString, "00:00")
        XCTAssertEqual(pass(59).durationString, "00:59")
        XCTAssertEqual(pass(3599).durationString, "59:59")
        XCTAssertEqual(pass(3600).durationString, "1:00:00")
        XCTAssertEqual(pass(36_000 + 61).durationString, "10:01:01")
        XCTAssertEqual(pass(-20).durationString, "00:00")
    }

    func testPassInitClampsBadNumbers() {
        let p = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: -1, distanceMiles: .nan, samples: [])
        XCTAssertEqual(p.durationSec, 0)
        XCTAssertEqual(p.distanceMiles, 0)
    }

    func testCarriersAndLabel() {
        var p = Fixtures.drive(samples: 3, carrier: .verizon)
        XCTAssertEqual(p.carriers, [.verizon])
        XCTAssertEqual(p.carrierLabel, "Verizon")
        p.samples[1].carrier = .tmobile
        XCTAssertEqual(p.carriers, [.verizon, .tmobile])
        XCTAssertEqual(p.carrierLabel, "Verizon + T-Mobile")
        let empty = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 0, distanceMiles: 0, samples: [])
        XCTAssertEqual(empty.carriers, [.att])
    }

    // MARK: - Breakdown

    func testBreakdownFractionsSumToOne() {
        let cells = Fixtures.drive(samples: 5_000, seed: 7).mergedCells()
        let b = CoverageBreakdown(cells: cells)
        XCTAssertEqual(b.totalCells, cells.count)
        XCTAssertEqual(b.segments.reduce(0) { $0 + $1.count }, cells.count)
        XCTAssertEqual(b.segments.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1e-9)
        XCTAssertEqual(b.deadCells, cells.filter { $0.rat == .none }.count)
    }

    func testBreakdownOfNothingIsAllZero() {
        let b = CoverageBreakdown(cells: [])
        XCTAssertEqual(b.totalCells, 0)
        XCTAssertEqual(b.deadCells, 0)
        XCTAssertTrue(b.segments.allSatisfy { $0.count == 0 && $0.fraction == 0 && $0.percent == 0 })
        XCTAssertFalse(b.segments.contains { $0.rat == .twoG }, "2G row hidden when absent")
    }
}
