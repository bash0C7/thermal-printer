import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testAppLaunchesAndShowsTheThreePanes() throws {
        let session = try FakeSession.launch()
        XCTAssertTrue(session.app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(session.app.item("todayList").waitForExistence(timeout: 10), "the today column is missing")
        XCTAssertTrue(session.app.item("partsList").exists, "the parts column is missing")
        XCTAssertTrue(session.app.item("emptyPreviewLabel").exists, "the preview column is missing")
        XCTAssertTrue(session.app.item("printButton").exists, "the footer is missing")
    }

    @MainActor
    func testTheTitleBarShowsTheStatusFromTheCLI() throws {
        let session = try FakeSession.launch()
        session.waitForIdle()
        let label = session.app.item("statusLabel")
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        XCTAssertTrue(label.text.contains("電池83%"), "status line was: \(label.text)")
        XCTAssertTrue(session.loggedLines.contains { $0.hasPrefix("status ") }, "log was: \(session.loggedLines)")
    }
}
