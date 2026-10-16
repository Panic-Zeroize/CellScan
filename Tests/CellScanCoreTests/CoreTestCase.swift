import XCTest

/// Base class for every test in this package.
///
/// Leak checking (Tests/check-leaks.sh): Linux XCTest keeps its run records and
/// test-case instances alive for the whole process, but the only reference to
/// them ends up behind a weak-reference side table that XCTWaiter leaks (one
/// 32-byte allocation, suppressed in Tests/lsan-xctest.supp). LeakSanitizer would
/// then report XCTest's entire object graph as "indirect leaks".
///
/// Holding the finished suites in a global keeps that harness-owned graph
/// reachable, as it is on Darwin. It never retains anything created by the code
/// under test: test cases release their fixtures in tearDown, so a leak in
/// CellScanCore stays unreachable and is still reported.
class CoreTestCase: XCTestCase {
    override class func setUp() {
        super.setUp()
        HarnessRetainer.registerOnce()
    }
}

final class HarnessRetainer: NSObject, XCTestObservation {
    private static let shared = HarnessRetainer()
    private static var registered = false
    private(set) static var finishedSuites: [XCTestSuite] = []

    static func registerOnce() {
        guard !registered else { return }
        registered = true
        XCTestObservationCenter.shared.addTestObserver(shared)
    }

    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        Self.finishedSuites.append(testSuite)
    }
}
