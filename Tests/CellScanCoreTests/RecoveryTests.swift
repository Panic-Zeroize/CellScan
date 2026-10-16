import XCTest
@testable import CellScanCore

/// The crash-recovery lifecycle the app relies on (PassStore + RecordingEngine).
final class RecoveryTests: XCTestCase {
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

    func testTargetedClearOnlyRemovesMatchingCheckpoint() throws {
        let stale = Fixtures.drive(samples: 5, seed: 1)
        let live = Fixtures.drive(samples: 5, seed: 2)
        try archive.writeCheckpoint(live)
        archive.clearCheckpoint(ifPassID: stale.id)
        XCTAssertEqual(archive.takeCheckpoint()?.id, live.id, "a live recording's checkpoint survives")

        try archive.writeCheckpoint(stale)
        archive.clearCheckpoint(ifPassID: stale.id)
        XCTAssertNil(archive.takeCheckpoint())
        archive.clearCheckpoint(ifPassID: stale.id)   // no file: no-op
    }

    /// Simulates: recording with periodic checkpoints → crash → relaunch recovers
    /// the newest checkpoint → it's saved → nothing is left to recover again.
    func testCrashMidRecordingRecoversLatestSnapshot() throws {
        let full = Fixtures.drive(samples: 95, seed: 3)
        for n in stride(from: 10, through: 90, by: 10) {
            var partial = full
            partial.samples = Array(full.samples.prefix(n))
            try archive.writeCheckpoint(partial)
        }
        // -- crash; relaunch --
        let recovered = try XCTUnwrap(archive.takeCheckpoint())
        XCTAssertEqual(recovered.id, full.id)
        XCTAssertEqual(recovered.samples.count, 90, "at most the samples since the last checkpoint are lost")
        var passes = archive.load().passes
        passes.append(recovered)
        try archive.save(passes)
        XCTAssertNil(archive.takeCheckpoint())
        XCTAssertEqual(archive.load().passes.map(\.id), [full.id])
    }

    /// Normal stop: save then clear in order on one queue → nothing to recover.
    func testCleanStopLeavesNoCheckpoint() throws {
        let queue = DispatchQueue(label: "test.persistence")
        let pass = Fixtures.drive(samples: 30)
        queue.async { try? self.archive.writeCheckpoint(pass) }
        queue.async { try? self.archive.save([pass]); self.archive.clearCheckpoint() }
        queue.sync {}
        XCTAssertNil(archive.takeCheckpoint())
        XCTAssertEqual(archive.load().passes.count, 1)
    }
}
