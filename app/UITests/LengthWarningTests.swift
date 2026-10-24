import XCTest

final class LengthWarningTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private static let longText = String(repeating: "段落です。長い印刷の警告を確かめるための文章です。\n", count: 80)

    @MainActor
    private func launchWithALongStrip() throws -> FakeSession {
        putTextOnPasteboard(Self.longText)
        let session = try FakeSession.launch()
        session.waitForIdle()
        session.paste()
        XCTAssertTrue(session.app.item("lengthWarning").waitForExistence(timeout: 15), "no length warning")
        XCTAssertTrue(session.app.buttons["printButton"].waitUntilEnabled(timeout: 30), "the preview never became ready")
        return session
    }

    @MainActor
    func testALongStripShowsAWarningAndAsksBeforePrinting() throws {
        let session = try launchWithALongStrip()
        session.app.buttons["printButton"].click()
        let confirm = session.app.buttons["confirmPrintButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no confirmation dialog")
        XCTAssertFalse(session.loggedLines.contains { $0.hasPrefix("print ") }, "printed before confirming")
        confirm.click()
        let message = session.app.item("messageLabel")
        XCTAssertTrue(message.waitForExistence(timeout: 20), "no result message; log: \(session.loggedLines)")
        XCTAssertTrue(message.text.hasPrefix("印刷しました"), "message was: \(message.text)")
        XCTAssertEqual(session.loggedLines.filter { $0.hasPrefix("print ") }.count, 1)
    }

    @MainActor
    func testDecliningTheConfirmationPrintsNothing() throws {
        let session = try launchWithALongStrip()
        session.app.buttons["printButton"].click()
        let cancel = session.app.buttons["cancelPrintButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "no confirmation dialog")
        cancel.click()
        XCTAssertTrue(session.app.item("confirmPrintButton").waitUntilGone(timeout: 5))
        XCTAssertFalse(session.loggedLines.contains { $0.hasPrefix("print ") }, "log: \(session.loggedLines)")
    }
}
