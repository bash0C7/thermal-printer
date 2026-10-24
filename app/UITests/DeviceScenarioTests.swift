import XCTest

final class DeviceScenarioTests: XCTestCase {
    private var report: [String] = []

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        let text = report.joined(separator: "\n") + "\n"
        add(XCTAttachment(string: text))
        if let path = ProcessInfo.processInfo.environment["DEVICE_REPORT"] {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    func testPrintsThePhotoThroughTheStagedApp() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["RUN_DEVICE"] == "1", "set RUN_DEVICE=1 to print on the real printer")
        let imagePath = try XCTUnwrap(environment["DEVICE_IMAGE"], "DEVICE_IMAGE is not set")
        let appPath = try stagedAppPath(environment)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: imagePath), "cannot read \(imagePath)")
        report.append("image: \(imagePath)")

        putFileOnPasteboard(URL(fileURLWithPath: imagePath))

        let home = try makeScratchDirectory("device").appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let app = XCUIApplication(url: URL(fileURLWithPath: appPath))
        app.launchEnvironment["HOME"] = home.path
        app.launch()

        pasteAndPreview(app)
        printAndVerify(app)
    }

    @MainActor
    func testPrintsTheGitHubCardThroughTheStagedApp() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["RUN_DEVICE"] == "1", "set RUN_DEVICE=1 to print on the real printer")
        let issueURL = try XCTUnwrap(environment["DEVICE_URL"], "DEVICE_URL is not set")
        let expectedRow = try XCTUnwrap(environment["DEVICE_EXPECT_ROW"], "DEVICE_EXPECT_ROW is not set")
        let appPath = try stagedAppPath(environment)
        report.append("url: \(issueURL)")

        putTextOnPasteboard(issueURL)

        let app = XCUIApplication(url: URL(fileURLWithPath: appPath))
        app.launch()

        pasteAndPreview(app, previewTimeout: 180)

        let row = app.item("partRow-0").containedText
        report.append("part row: \(row)")
        XCTAssertTrue(row.contains(expectedRow), "the card was not fetched from GitHub; part row: \(row)")

        printAndVerify(app)
    }

    private func stagedAppPath(_ environment: [String: String]) throws -> String {
        let appPath = try XCTUnwrap(environment["DEVICE_APP"], "DEVICE_APP is not set")
        XCTAssertNil(environment["THERMALPRINTER_CLI"], "THERMALPRINTER_CLI would replace the real CLI")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: appPath + "/Contents/MacOS/picoruby"),
            "\(appPath) does not bundle picoruby; run rake app:build")
        report.append("app: \(appPath)")
        return appPath
    }

    @MainActor
    private func pasteAndPreview(_ app: XCUIApplication, previewTimeout: TimeInterval = 20) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "no window")
        let refresh = app.buttons["refreshStatusButton"]
        XCTAssertTrue(refresh.waitUntilEnabled(timeout: 90), "the startup status check never finished")
        report.append("status at launch: \(app.item("statusLabel").text)")
        if app.item("statusDetailLabel").exists {
            report.append("status detail at launch: \(app.item("statusDetailLabel").text)")
        }

        let paste = app.buttons["pasteButton"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10), "pasteButton is missing")
        paste.click()

        let preview = app.item("previewImage")
        XCTAssertTrue(preview.waitForExistence(timeout: previewTimeout), "no preview appeared: \(app.item("messageLabel").text)")
        XCTAssertGreaterThan(preview.frame.height, 0)
        let length = app.item("lengthLabel").text
        report.append("length: \(length)")
        report.append("preview value: \(preview.value ?? "")")
    }

    @MainActor
    private func printAndVerify(_ app: XCUIApplication) {
        let refresh = app.buttons["refreshStatusButton"]
        let print = app.buttons["printButton"]
        XCTAssertTrue(print.waitUntilEnabled(timeout: 10), "printButton is not enabled; message: \(app.item("messageLabel").text)")
        print.click()

        let confirm = app.buttons["confirmPrintButton"]
        if confirm.waitForExistence(timeout: 3) {
            report.append("confirmation dialog appeared (length warning)")
            confirm.click()
        }

        let printing = app.item("printingLabel")
        let started = printing.waitForExistence(timeout: 15)
        report.append("printing label seen: \(started)")
        XCTAssertTrue(printing.waitUntilGone(timeout: 60), "still printing after 60 s")
        XCTAssertTrue(refresh.waitUntilEnabled(timeout: 90), "the status check after printing never finished")

        let message = app.item("messageLabel")
        XCTAssertTrue(message.waitForExistence(timeout: 10), "no result message after printing")
        let statusLine = app.item("statusLabel").text
        let detail = app.item("statusDetailLabel")
        report.append("message: \(message.text)")
        report.append("status after print: \(statusLine)")
        add(XCTAttachment(screenshot: app.screenshot()))

        XCTAssertTrue(message.text.hasPrefix("印刷しました"), "message was: \(message.text); status: \(statusLine)")
        XCTAssertFalse(detail.exists, "status detail: \(detail.text); message: \(message.text)")
        XCTAssertFalse(statusLine.contains("プリンター連携なし"), "status was: \(statusLine)")
    }
}
