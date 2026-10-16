import XCTest
@testable import CellScanCore

final class MergeTests: CoreTestCase {

    func testEmptyPassHasNoCells() {
        let p = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 0, distanceMiles: 0, samples: [])
        XCTAssertTrue(p.mergedCells().isEmpty)
    }

    func testSingleSampleBecomesOneCell() {
        let p = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 3, distanceMiles: 0,
                     samples: [Fixtures.sample(down: 42)])
        let cells = p.mergedCells()
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].sampleCount, 1)
        XCTAssertEqual(cells[0].downMbps, 42)
        XCTAssertEqual(cells[0].carrier, .att)
    }

    func testAverageVersusWorstCase() {
        let t = Fixtures.t0
        let samples = [
            Fixtures.sample(at: t, rat: .fiveG, down: 300, up: 50, latency: 20),
            Fixtures.sample(at: t + 3, rat: .lte, down: 100, up: 10, latency: 60),
            Fixtures.sample(at: t + 6, rat: .none, down: nil, up: nil, latency: nil),
        ]
        let p = Pass(carrier: .verizon, startedAt: t, durationSec: 9, distanceMiles: 0, samples: samples)

        let avg = p.mergedCells(average: true)
        XCTAssertEqual(avg.count, 1)
        XCTAssertEqual(avg[0].downMbps, 200)          // nils excluded from the mean
        XCTAssertEqual(avg[0].upMbps, 30)
        XCTAssertEqual(avg[0].latencyMs, 40)
        XCTAssertEqual(avg[0].rat, .threeG)           // (4+3+0)/3 = 2.33 → 2
        XCTAssertEqual(avg[0].time, t + 6)

        let worst = p.mergedCells(average: false)
        XCTAssertEqual(worst[0].rat, RAT.none)
        XCTAssertEqual(worst[0].downMbps, 100)
        XCTAssertEqual(worst[0].upMbps, 10)
        XCTAssertEqual(worst[0].latencyMs, 60, "worst latency is the highest")
    }

    func testInvalidSamplesAreSkippedNotCrashing() {
        let samples = [
            Fixtures.sample(lat: .nan, lng: 0),
            Fixtures.sample(lat: 1e300, lng: 1e300),
            Fixtures.sample(lat: 95, lng: 0),
            Fixtures.sample(lat: 10, lng: 10, down: .infinity),
        ]
        let p = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 0, distanceMiles: 0, samples: samples)
        let cells = p.mergedCells()
        XCTAssertEqual(cells.count, 1)
        XCTAssertNil(cells[0].downMbps, "infinite throughput sanitized away")
    }

    func testCellIDsAreDeterministic() {
        let p = Fixtures.drive(samples: 2_000, seed: 3)
        let a = p.mergedCells().map(\.id)
        let b = p.mergedCells().map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a).count, a.count, "ids are unique")
    }

    func testMixedCarrierPassKeepsSeparateLayers() {
        let t = Fixtures.t0
        let samples = [
            Fixtures.sample(at: t, carrier: .verizon),
            Fixtures.sample(at: t + 1, carrier: .att),     // same spot, other carrier
        ]
        let p = Pass(carrier: .other, startedAt: t, durationSec: 2, distanceMiles: 0, samples: samples)
        let cells = p.mergedCells()
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(Set(cells.map(\.carrier)), [.verizon, .att])
    }

    /// 100k-sample drive in both modes and at every merge radius the UI offers.
    func testStressInvariantsAcrossSettings() {
        let p = Fixtures.drive(samples: 100_000, seed: 42)
        for (grid, _) in [(10.0, "")] + AppSettings.mergeRadii {
            for average in [true, false] {
                let cells = p.mergedCells(gridMeters: grid, average: average)
                XCTAssertFalse(cells.isEmpty)
                XCTAssertLessThanOrEqual(cells.count, p.samples.count)
                XCTAssertEqual(cells.reduce(0) { $0 + $1.sampleCount }, p.samples.count,
                               "every valid sample lands in exactly one cell (grid \(grid), avg \(average))")
                XCTAssertEqual(Set(cells.map(\.id)).count, cells.count)
                for c in cells {
                    XCTAssertTrue(c.lat.isFinite && c.lng.isFinite)
                    XCTAssertTrue(abs(c.lat) <= 90 && abs(c.lng) <= 180)
                    if let d = c.downMbps { XCTAssertTrue(d.isFinite && d >= 0) }
                    if let u = c.upMbps { XCTAssertTrue(u.isFinite && u >= 0) }
                    if let l = c.latencyMs { XCTAssertTrue(l.isFinite && l >= 0) }
                    XCTAssertGreaterThanOrEqual(c.sampleCount, 1)
                }
                XCTAssertEqual(cells.map(\.time), cells.map(\.time).sorted(), "cells sorted by time")
            }
        }
    }

    func testWorstCaseNeverBeatsAverage() {
        let p = Fixtures.drive(samples: 20_000, seed: 9)
        let avg = Dictionary(uniqueKeysWithValues: p.mergedCells(average: true).map { ($0.id, $0) })
        for w in p.mergedCells(average: false) {
            guard let a = avg[w.id] else { return XCTFail("cell sets differ between modes") }
            XCTAssertLessThanOrEqual(w.rat.tier, a.rat.tier)
            if let wd = w.downMbps, let ad = a.downMbps { XCTAssertLessThanOrEqual(wd, ad + 1e-9) }
            if let wl = w.latencyMs, let al = a.latencyMs { XCTAssertGreaterThanOrEqual(wl, al - 1e-9) }
        }
    }

    func testLargerGridNeverProducesMoreCells() {
        let p = Fixtures.drive(samples: 30_000, seed: 11)
        let counts = [60.0, 120, 250, 500, 2000].map { p.mergedCells(gridMeters: $0).count }
        // Not strictly monotonic for arbitrary grids (bucket edges shift), but a 33x
        // larger grid must collapse far more than a small one.
        XCTAssertGreaterThan(counts.first!, counts.last!)
    }

    func testAntimeridianAndPolesDoNotCrash() {
        let samples = [
            Fixtures.sample(lat: 89.9999, lng: 179.9999),
            Fixtures.sample(lat: 89.9999, lng: -179.9999),
            Fixtures.sample(lat: -89.9999, lng: 0),
            Fixtures.sample(lat: 0, lng: 0),
        ]
        let p = Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 0, distanceMiles: 0, samples: samples)
        XCTAssertEqual(p.mergedCells(gridMeters: 10).count, 4)
    }

    func testMergePerformance100k() {
        let p = Fixtures.drive(samples: 100_000, seed: 5)
        measure { _ = p.mergedCells() }
    }
}
