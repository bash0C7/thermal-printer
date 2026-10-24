import Foundation
import Testing
@testable import ThermalPrinterCore

let printerRepoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let printerBusyJSON = """
{"version":1,"mode":"status","ok":false,"error":"busy","exit_code":12,"hint":null,
 "warnings":[],"status":null,"job":null,"notify":null,"completion":null,"elapsed_ms":3}
"""

func printerFixtureData(_ name: String) throws -> Data {
    try Data(contentsOf: printerRepoRoot.appending(path: "test/fixtures/\(name).json"))
}

func decodePrinterFixture(_ name: String) throws -> PrintResult {
    try JSONDecoder().decode(PrintResult.self, from: printerFixtureData(name))
}

func printerDate(hour: Int, minute: Int) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 10
    components.day = 24
    components.hour = hour
    components.minute = minute
    return Calendar.current.date(from: components)!
}

@Test(arguments: ["result_print_ok", "result_status_ok", "result_not_found"])
func everyRubyResultFixtureDecodes(name: String) throws {
    _ = try decodePrinterFixture(name)
}

@Test func printOkFixtureCarriesTheJobAndTheStatus() throws {
    let r = try decodePrinterFixture("result_print_ok")
    #expect(r.mode == .print)
    #expect(r.ok)
    #expect(r.error == nil)
    #expect(r.exitCode == 0)
    #expect(r.warnings.isEmpty)
    #expect(r.status?.battery == 83)
    #expect(r.status?.paper == "ok")
    #expect(r.status?.autoOff == 12)
    #expect(r.job?.rows == 2400)
    #expect(r.job?.chunkSize == 128)
    #expect(r.job?.intervalMs == 20)
    #expect(r.notify?.maxWrite == 182)
    #expect(r.notify?.events == ["1a0689", "1a0f0c"])
    #expect(r.completion?.state == "notified")
    #expect(r.completion?.afterSendMs == 2310)
    #expect(r.elapsedMs == 21034)
}

@Test func statusFixtureHasNoJobAndNoCompletion() throws {
    let r = try decodePrinterFixture("result_status_ok")
    #expect(r.mode == .status)
    #expect(r.job == nil)
    #expect(r.completion == nil)
    #expect(r.status?.firmware == "3.0.7")
}

@Test func notFoundFixtureIsAFailureWithItsKindAndExitCode() throws {
    let r = try decodePrinterFixture("result_not_found")
    #expect(!r.ok)
    #expect(r.error == .notFound)
    #expect(r.exitCode == 10)
    #expect(r.status == nil)
    #expect(r.hint?.isEmpty == false)
}

@Test func busyResultDecodesAsBusy() throws {
    let r = try JSONDecoder().decode(PrintResult.self, from: Data(printerBusyJSON.utf8))
    #expect(r.error == .busy)
    #expect(r.exitCode == 12)
}

@Test func anErrorKindFromANewerCLIDecodesAsUnknown() throws {
    let json = printerBusyJSON.replacingOccurrences(of: "\"busy\"", with: "\"something_new\"")
    let r = try JSONDecoder().decode(PrintResult.self, from: Data(json.utf8))
    #expect(r.error == .unknown)
}

@Test func invalidInputIsItsOwnKind() throws {
    let json = printerBusyJSON.replacingOccurrences(of: "\"busy\"", with: "\"invalid_input\"")
    let r = try JSONDecoder().decode(PrintResult.self, from: Data(json.utf8))
    #expect(r.error == .invalidInput)
}

@Test func everyErrorKindInTheContractTableDecodes() {
    let names = ["unknown", "usage", "invalid_input", "not_found", "wrong_device", "busy", "timeout",
                 "disconnected", "status_unavailable", "paper_out", "cover_open", "overheat",
                 "low_battery", "print_failed", "canceled"]
    #expect(PrintResult.ErrorKind.allCases.map(\.rawValue) == names)
}
