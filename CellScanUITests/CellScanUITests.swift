import XCTest
import CoreLocation

/// Drives the real app through its user-facing flows in the iOS Simulator:
/// permission handling, recording, stop/save, CSV export (Copy and the system
/// Files "Save" picker), the map, and deleting a pass.
final class CellScanUITests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let start = CLLocationCoordinate2D(latitude: 37.3317, longitude: -122.0307)

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: start.latitude,
                                                                         longitude: start.longitude))
    }

    override func tearDown() {
        if let app, testRun?.hasSucceeded == false {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "failure-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
            print(app.debugDescription)
        }
        app = nil
    }

    // MARK: - Flows

    /// Denying location must block recording and offer a way to fix it.
    func testA_LocationDeniedBlocksRecording() {
        app.launch()
        tap(app.buttons["home.startPass"])
        answerLocationPrompt(allow: false)

        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 10),
                      "denied state should offer Open Settings")
        let startButton = app.buttons["newPass.start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        XCTAssertFalse(startButton.isEnabled, "Start Recording must be disabled without location access")
        snapshot("denied")
    }

    /// Record a pass, save it, export it (Copy + Files Save), view the map, delete it.
    func testB_RecordSaveExportMapDelete() {
        app.launch()
        tap(app.buttons["home.startPass"])
        answerLocationPrompt(allow: true)

        let startButton = app.buttons["newPass.start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        waitUntil("Start Recording enabled", timeout: 10) { startButton.isEnabled }
        tap(startButton)

        // Drive ~120 m north-east over 16 s so fixes stay fresh and samples accrue.
        let samples = app.descendants(matching: .any)["recording.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 10), "recording screen should appear")
        for step in 1...16 {
            XCUIDevice.shared.location = XCUILocation(location: CLLocation(
                latitude: start.latitude + Double(step) * 0.00005,
                longitude: start.longitude + Double(step) * 0.00005))
            sleep(1)
        }
        snapshot("recording")
        XCTAssertFalse(samples.label.hasSuffix(" 0") || samples.label.hasSuffix(",0"),
                       "samples should be counted while recording (label: \(samples.label))")

        // Stop → Save Pass.
        tap(app.buttons["recording.stop"])
        tap(app.buttons["Save Pass"])
        XCTAssertTrue(app.staticTexts["Pass complete"].waitForExistence(timeout: 10), "summary after save")
        snapshot("summary")

        // Export: Copy, then Save through the system Files picker.
        tap(app.buttons["summary.export"])
        let copy = app.buttons["export.copy"]
        tap(copy)
        waitUntil("Copy confirms", timeout: 5) { copy.label.contains("Copied") }

        let save = app.buttons["export.save"]
        tap(save)
        confirmFilesPicker()
        waitUntil("file saved through the Files picker", timeout: 15) { save.label.contains("Saved") }
        snapshot("exported")

        // Back to the summary, open the map, come back.
        tap(app.buttons["export.back"])
        tap(app.buttons["summary.viewMap"])
        XCTAssertTrue(app.buttons["map.back"].waitForExistence(timeout: 10), "map screen")
        snapshot("map")
        tap(app.buttons["map.back"])

        // Done → the pass is listed on Home; open it and delete it.
        tap(app.buttons["summary.done"])
        let card = app.descendants(matching: .any)["passCard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "saved pass listed on Home")
        card.tap()
        tap(app.buttons["summary.delete"])
        tap(app.buttons["Delete Pass"])
        XCTAssertTrue(app.staticTexts["No passes yet"].waitForExistence(timeout: 10), "pass deleted")
    }

    // MARK: - Helpers

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 15), "missing \(element)", file: file, line: line)
        waitUntil("\(element) hittable", timeout: 10) { element.isHittable }
        element.tap()
    }

    private func waitUntil(_ what: String, timeout: TimeInterval, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("timed out waiting for: \(what)", file: file, line: line)
    }

    /// The location prompt is owned by SpringBoard, not the app.
    private func answerLocationPrompt(allow: Bool) {
        let labels = allow ? ["Allow While Using App", "Allow Once", "Allow"] : ["Don’t Allow", "Don't Allow"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            for label in labels {
                let button = springboard.buttons[label]
                if button.exists { button.tap(); return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("location permission prompt did not appear")
    }

    /// Confirms the system document picker presented by `.fileExporter`.
    private func confirmFilesPicker() {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            for label in ["Save", "Move", "Done"] {
                let button = app.navigationBars.buttons[label]
                if button.exists && button.isHittable && button.isEnabled {
                    snapshot("files-picker")
                    button.tap()
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("Files picker confirm button not found")
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
