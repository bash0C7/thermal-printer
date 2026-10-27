import AppKit
import XCTest

enum FakeScenario: String {
    case ok
    case notFound = "not_found"
    case busy
}

private let uitestsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

let fakeCLIURL = uitestsDirectory.appending(path: "Fixtures/fake-cli.sh")

func makeScratchDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "thermalprinter-uitest-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func putTextOnPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

func putFileOnPasteboard(_ url: URL) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.writeObjects([url as NSURL])
}

extension XCUIApplication {
    func item(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    func pasteURL() {
        let field = textFields["urlField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "urlField is missing")
        field.click()
        typeKey("v", modifierFlags: .command)
        typeKey(.return, modifierFlags: [])
    }

    @MainActor
    func pasteIntoDraft() {
        let editor = textViews["draftEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "draftEditor is missing")
        editor.click()
        typeKey("v", modifierFlags: .command)
    }
}

extension XCUIElement {
    var containedText: String {
        descendants(matching: .staticText).allElementsBoundByIndex.map(\.text).joined(separator: " ")
    }

    var text: String {
        if !label.isEmpty { return label }
        return (value as? String) ?? ""
    }

    func waitUntilGone(timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: self)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    func waitUntilEnabled(timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: self)
        return XCTWaiter().wait(for: [enabled], timeout: timeout) == .completed
    }
}

struct FakeSession {
    let app: XCUIApplication
    let log: URL

    var loggedLines: [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    @MainActor
    static func launch(_ scenario: FakeScenario = .ok, isolatedHome: Bool = true) throws -> FakeSession {
        let scratch = try makeScratchDirectory("fake")
        let log = scratch.appending(path: "cli.log")
        let app = XCUIApplication()
        app.launchEnvironment["THERMALPRINTER_CLI"] = fakeCLIURL.path
        app.launchEnvironment["FAKE_CLI_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["FAKE_CLI_LOG"] = log.path
        if isolatedHome {
            let home = scratch.appending(path: "home")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            app.launchEnvironment["HOME"] = home.path
        }
        app.launch()
        return FakeSession(app: app, log: log)
    }

    @MainActor
    func paste() {
        app.pasteIntoDraft()
    }

    @MainActor
    func pasteURL() {
        app.pasteURL()
    }

    @MainActor
    func waitForIdle() {
        XCTAssertTrue(app.buttons["refreshStatusButton"].waitUntilEnabled(timeout: 20), "the status refresh never finished")
    }
}
