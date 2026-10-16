import XCTest
@testable import CellScanCore

final class ArchiveTests: CoreTestCase {
    private var dir: URL!
    private var archive: PassArchive!

    override func setUp() {
        dir = Fixtures.tempDirectory()
        archive = PassArchive(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        // Linux XCTest keeps every test-case instance alive; drop what we own.
        dir = nil
        archive = nil
    }

    private func files() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()) ?? []
    }

    func testMissingFileLoadsEmptyWithoutIssue() {
        let r = archive.load()
        XCTAssertTrue(r.passes.isEmpty)
        XCTAssertNil(r.issue)
    }

    func testRoundTripPreservesEverything() throws {
        var mixed = Pass.combining([Fixtures.drive(samples: 30, carrier: .verizon, seed: 1),
                                    Fixtures.drive(samples: 30, carrier: .att, seed: 2)])
        mixed.startedAt = Fixtures.t0 + 99
        let passes = [Fixtures.drive(samples: 40, carrier: .tmobile), mixed]
        try archive.save(passes)
        let r = archive.load()
        XCTAssertNil(r.issue)
        XCTAssertEqual(r.passes.map(\.id), [mixed.id, passes[0].id], "sorted newest first")
        let loaded = r.passes.first { $0.id == mixed.id }!
        XCTAssertEqual(loaded.samples.count, 60)
        XCTAssertEqual(loaded.samples.map(\.carrier), mixed.samples.map(\.carrier))
        XCTAssertEqual(loaded.samples.map(\.downMbps), mixed.samples.map(\.downMbps))
        XCTAssertEqual(loaded.csvString(), mixed.csvString())
    }

    /// Regression: a corrupt file used to load as empty and then be overwritten.
    func testCorruptFileIsBackedUpNotLost() throws {
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: archive.passesURL)
        let r = archive.load()
        XCTAssertTrue(r.passes.isEmpty)
        XCTAssertNotNil(r.issue)
        let backup = try XCTUnwrap(r.backupURL)
        XCTAssertEqual(try Data(contentsOf: backup), garbage)

        // The app then saves new data; the backup must survive.
        try archive.save([Fixtures.drive(samples: 3)])
        XCTAssertEqual(try Data(contentsOf: backup), garbage)
        XCTAssertEqual(archive.load().passes.count, 1)
    }

    func testPartiallyReadableFileKeepsGoodPassesAndBacksUp() throws {
        let good = Fixtures.drive(samples: 5)
        let goodJSON = String(decoding: try PassArchive.makeEncoder().encode(good), as: UTF8.self)
        let file = "[\(goodJSON), {\"id\": 42}, \(goodJSON.replacingOccurrences(of: good.id.uuidString, with: UUID().uuidString))]"
        try Data(file.utf8).write(to: archive.passesURL)
        let r = archive.load()
        XCTAssertEqual(r.passes.count, 2)
        XCTAssertNotNil(r.issue)
        XCTAssertTrue(r.issue!.contains("1 saved pass"))
        XCTAssertNotNil(r.backupURL)
    }

    func testDuplicateIDsAreCollapsed() throws {
        let p = Fixtures.drive(samples: 2)
        try archive.save([p, p, p])
        XCTAssertEqual(archive.load().passes.count, 1)
    }

    func testEmptyFileIsTreatedAsNoData() throws {
        try Data().write(to: archive.passesURL)
        let r = archive.load()
        XCTAssertTrue(r.passes.isEmpty)
        XCTAssertNil(r.issue)
    }

    func testNonFiniteNumbersStillEncode() throws {
        var p = Fixtures.drive(samples: 3)
        p.samples[0].downMbps = .nan
        p.samples[1].speedMph = .infinity
        p.distanceMiles = .nan
        XCTAssertNoThrow(try archive.save([p]), "default JSONEncoder would throw and lose the save")
        XCTAssertEqual(archive.load().passes.first?.samples.count, 3)
    }

    func testSaveIntoMissingDirectoryCreatesIt() throws {
        let nested = PassArchive(directory: dir.appendingPathComponent("a/b/c"))
        try nested.save([Fixtures.drive(samples: 1)])
        XCTAssertEqual(nested.load().passes.count, 1)
    }

    func testUnwritableLocationThrowsDescriptiveError() {
        // A regular file where the directory should be makes every write fail.
        let blocker = dir.appendingPathComponent("blocker")
        XCTAssertTrue(FileManager.default.createFile(atPath: blocker.path, contents: Data("x".utf8)))
        let bad = PassArchive(directory: blocker.appendingPathComponent("sub"))
        XCTAssertThrowsError(try bad.save([Fixtures.drive(samples: 1)])) { error in
            XCTAssertNotNil((error as? LocalizedError)?.errorDescription)
        }
        XCTAssertThrowsError(try bad.writeCheckpoint(Fixtures.drive(samples: 1)))
        XCTAssertTrue(bad.load().passes.isEmpty)
    }

    // MARK: - Checkpoint

    func testCheckpointRoundTripAndIsConsumedOnce() throws {
        let live = Fixtures.drive(samples: 25)
        try archive.writeCheckpoint(live)
        let recovered = try XCTUnwrap(archive.takeCheckpoint())
        XCTAssertEqual(recovered.id, live.id)
        XCTAssertEqual(recovered.samples.count, 25)
        XCTAssertNil(archive.takeCheckpoint(), "checkpoint is removed after recovery")
    }

    func testEmptyOrCorruptCheckpointIsIgnoredSafely() throws {
        try archive.writeCheckpoint(Pass(carrier: .att, startedAt: Fixtures.t0, durationSec: 0, distanceMiles: 0, samples: []))
        XCTAssertNil(archive.takeCheckpoint())
        try Data("garbage".utf8).write(to: archive.checkpointURL)
        XCTAssertNil(archive.takeCheckpoint())
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.checkpointURL.path))
        XCTAssertTrue(files().contains { $0.contains("recording-checkpoint.corrupt-") }, "corrupt checkpoint preserved")
    }

    func testClearCheckpointWhenNoneExistsIsNoOp() {
        archive.clearCheckpoint()
        archive.clearCheckpoint()
        XCTAssertNil(archive.takeCheckpoint())
    }

    // MARK: - Stress

    func testStressLargeArchiveRoundTrip() throws {
        let passes = (0..<50).map { Fixtures.drive(samples: 5_000, carrier: Carrier.allCases[$0 % 4],
                                                   startTime: Fixtures.t0 + Double($0) * 86_400,
                                                   seed: UInt64($0)) }
        try archive.save(passes)
        let r = archive.load()
        XCTAssertNil(r.issue)
        XCTAssertEqual(r.passes.count, 50)
        XCTAssertEqual(r.passes.reduce(0) { $0 + $1.samples.count }, 250_000)
    }

    /// Many writers hammering one serial queue (as the app does) must leave a
    /// valid, fully-readable file with the last write's content.
    func testConcurrentSerializedWritesStayConsistent() throws {
        let queue = DispatchQueue(label: "test.persistence")
        let group = DispatchGroup()
        var expected: [Pass] = []
        for i in 0..<200 {
            let snapshot = (0...(i % 7)).map { Fixtures.drive(samples: 20, seed: UInt64(i * 10 + $0)) }
            expected = snapshot
            DispatchQueue.global().async(group: group) {
                queue.sync { try? self.archive.save(snapshot) }
            }
            if i % 3 == 0 {
                let live = Fixtures.drive(samples: 15, seed: UInt64(i))
                DispatchQueue.global().async(group: group) {
                    queue.sync { try? self.archive.writeCheckpoint(live); self.archive.clearCheckpoint() }
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 120), .success)
        try queue.sync { try archive.save(expected) }
        let r = archive.load()
        XCTAssertNil(r.issue)
        XCTAssertEqual(Set(r.passes.map(\.id)), Set(expected.map(\.id)))
        XCTAssertFalse(files().contains { $0.contains("corrupt") || $0.contains("partial") })
    }
}

final class SettingsTests: CoreTestCase {

    func testDefaultsRoundTrip() throws {
        let data = try JSONEncoder().encode(AppSettings.default)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), .default)
    }

    func testMissingAndMalformedKeysFallBackIndividually() throws {
        let json = #"{"sampleIntervalSec": 5, "metric": "yes please", "futureOption": 1}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.sampleIntervalSec, 5)
        XCTAssertEqual(s.metric, false)
        XCTAssertEqual(s.cellMergeMeters, 120)
        XCTAssertEqual(s.throughputIntervalSec, 20)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let json = #"{"sampleIntervalSec": 0, "throughputIntervalSec": 2, "minSampleDistanceM": -9, "cellMergeMeters": 1e9}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.sampleIntervalSec, 1)
        XCTAssertEqual(s.throughputIntervalSec, 5)
        XCTAssertEqual(s.minSampleDistanceM, 0)
        XCTAssertEqual(s.cellMergeMeters, 2000)
        var off = AppSettings(); off.throughputIntervalSec = -1
        XCTAssertEqual(off.sanitized().throughputIntervalSec, 0, "negative means off")
    }

    func testEveryUIChoiceSurvivesSanitizing() {
        for (v, _) in AppSettings.sampleIntervals { var s = AppSettings(); s.sampleIntervalSec = v; XCTAssertEqual(s.sanitized().sampleIntervalSec, v) }
        for (v, _) in AppSettings.throughputIntervals { var s = AppSettings(); s.throughputIntervalSec = v; XCTAssertEqual(s.sanitized().throughputIntervalSec, v) }
        for (v, _) in AppSettings.distances { var s = AppSettings(); s.minSampleDistanceM = v; XCTAssertEqual(s.sanitized().minSampleDistanceM, v) }
        for (v, _) in AppSettings.mergeRadii { var s = AppSettings(); s.cellMergeMeters = v; XCTAssertEqual(s.sanitized().cellMergeMeters, v) }
    }

    func testUnitStrings() {
        var s = AppSettings()
        XCTAssertEqual(s.speedString(mph: 60.4), "60 mph")
        XCTAssertEqual(s.distanceString(miles: 1.25), "1.2 mi")
        XCTAssertEqual(s.speedString(mph: .nan), "0 mph")
        XCTAssertEqual(s.speedString(mph: -4), "0 mph")
        s.metric = true
        XCTAssertEqual(s.speedString(mph: 60), "97 km/h")
        XCTAssertEqual(s.distanceString(miles: 10), "16.1 km")
        XCTAssertEqual(s.distanceString(miles: .infinity), "0.0 km")
    }
}
