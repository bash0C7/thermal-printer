import XCTest

final class GitHubCardTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAPastedIssueURLBecomesAFetchedCardThatPreviewsAndSendsOneJob() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["RUN_GITHUB"] == "1", "set RUN_GITHUB=1 to fetch a card through the real gh")
        let issueURL = try XCTUnwrap(environment["GITHUB_URL"], "GITHUB_URL is not set")
        let expectedRow = try XCTUnwrap(environment["GITHUB_EXPECT_ROW"], "GITHUB_EXPECT_ROW is not set")

        putTextOnPasteboard(issueURL)
        let session = try FakeSession.launch(isolatedHome: false)
        session.waitForIdle()
        session.pasteURL()

        let row = session.app.item("partRow-0")
        XCTAssertTrue(row.waitForExistence(timeout: 180), "no part row appeared")
        XCTAssertTrue(row.containedText.contains(expectedRow), "the card was not fetched from GitHub; part row: \(row.containedText)")

        let preview = session.app.item("previewImage")
        XCTAssertTrue(preview.waitForExistence(timeout: 30), "no preview appeared: \(session.app.item("messageLabel").text)")
        XCTAssertGreaterThan(preview.frame.height, 0)
        add(XCTAttachment(string: "part row: \(row.containedText)\nlength: \(session.app.item("lengthLabel").text)\npreview: \(preview.value ?? "")\n"))

        let print = session.app.buttons["printButton"]
        XCTAssertTrue(print.waitUntilEnabled(timeout: 10))
        print.click()
        let confirm = session.app.buttons["confirmPrintButton"]
        if confirm.waitForExistence(timeout: 3) {
            confirm.click()
        }
        let message = session.app.item("messageLabel")
        XCTAssertTrue(message.waitForExistence(timeout: 20), "no result message; log: \(session.loggedLines)")
        XCTAssertTrue(message.text.hasPrefix("印刷しました"), "message was: \(message.text)")
        let jobs = session.loggedLines.filter { $0.hasPrefix("print ") }
        XCTAssertEqual(jobs.count, 1, "log: \(session.loggedLines)")
        XCTAssertTrue(jobs[0].contains(".pbm"), jobs[0])
        let previews = session.loggedLines.filter { $0.hasPrefix("dry_run ") }
        XCTAssertFalse(previews.isEmpty, "the preview did not go through the real CLI: \(session.loggedLines)")
    }
}
