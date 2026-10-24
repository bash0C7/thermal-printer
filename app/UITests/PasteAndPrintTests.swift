import XCTest

final class PasteAndPrintTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testPastingTextAddsAPartAndShowsAPreview() throws {
        putTextOnPasteboard("# 見出し\n\n本文です。")
        let session = try FakeSession.launch()
        session.paste()
        XCTAssertTrue(session.app.item("partRow-0").waitForExistence(timeout: 10), "no part row appeared")
        let preview = session.app.item("previewImage")
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "no preview appeared")
        XCTAssertGreaterThan(preview.frame.height, 0)
        XCTAssertTrue(session.app.item("lengthLabel").text.hasPrefix("長さ "), session.app.item("lengthLabel").text)
    }

    @MainActor
    func testPastingOneURLMakesACardPart() throws {
        putTextOnPasteboard("https://example.com/a/page")
        let session = try FakeSession.launch()
        session.paste()
        XCTAssertTrue(session.app.item("partRow-0").waitForExistence(timeout: 20), "no part row appeared")
        XCTAssertTrue(session.app.staticTexts["URL"].waitForExistence(timeout: 5), "the part is not a URL card")
    }

    @MainActor
    func testPrintingSendsOneJobAndReportsSuccess() throws {
        putTextOnPasteboard("印刷の確認です。")
        let session = try FakeSession.launch()
        session.waitForIdle()
        session.paste()
        XCTAssertTrue(session.app.item("previewImage").waitForExistence(timeout: 10))
        let print = session.app.buttons["printButton"]
        XCTAssertTrue(print.waitUntilEnabled(timeout: 10))
        print.click()
        let message = session.app.item("messageLabel")
        XCTAssertTrue(message.waitForExistence(timeout: 20), "no result message; log: \(session.loggedLines)")
        XCTAssertTrue(message.text.hasPrefix("印刷しました"), "message was: \(message.text)")
        let jobs = session.loggedLines.filter { $0.hasPrefix("print ") }
        XCTAssertEqual(jobs.count, 1, "log: \(session.loggedLines)")
        XCTAssertTrue(jobs[0].contains("--density 4"), jobs[0])
        XCTAssertTrue(jobs[0].contains(".pbm"), jobs[0])
        XCTAssertEqual(session.loggedLines.last?.hasPrefix("status "), true, "status was not refreshed: \(session.loggedLines)")
    }

    @MainActor
    func testNotFoundShowsTheWakeUpHint() throws {
        putTextOnPasteboard("印刷の確認です。")
        let session = try FakeSession.launch(.notFound)
        session.waitForIdle()
        session.paste()
        XCTAssertTrue(session.app.item("previewImage").waitForExistence(timeout: 10))
        let print = session.app.buttons["printButton"]
        XCTAssertTrue(print.waitUntilEnabled(timeout: 10))
        print.click()
        let message = session.app.item("messageLabel")
        XCTAssertTrue(message.waitForExistence(timeout: 20), "no result message; log: \(session.loggedLines)")
        XCTAssertTrue(message.text.contains("電源ボタン"), "message was: \(message.text)")
    }
}
