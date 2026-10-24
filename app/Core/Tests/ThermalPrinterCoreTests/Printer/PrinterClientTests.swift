import Foundation
import Synchronization
import Testing
@testable import ThermalPrinterCore

final class FakeRunner: ProcessRunner {
    private struct Calls {
        var executable: URL?
        var arguments: [String] = []
        var history: [[String]] = []
        var pbmAtRun: Data?
    }

    private let calls = Mutex(Calls())
    private let resultData: Data?
    private let pngData: Data?
    private let terminationStatus: Int32
    private let output: String

    init(resultData: Data?, terminationStatus: Int32 = 0, pngData: Data? = nil, output: String = "fake output") {
        self.resultData = resultData
        self.terminationStatus = terminationStatus
        self.pngData = pngData
        self.output = output
    }

    convenience init(resultFixture: String, terminationStatus: Int32 = 0) {
        self.init(resultData: try? printerFixtureData(resultFixture), terminationStatus: terminationStatus)
    }

    convenience init(resultJSON: String, terminationStatus: Int32 = 0) {
        self.init(resultData: Data(resultJSON.utf8), terminationStatus: terminationStatus)
    }

    var lastExecutable: URL? { calls.withLock { $0.executable } }
    var lastArguments: [String] { calls.withLock { $0.arguments } }
    var history: [[String]] { calls.withLock { $0.history } }
    var pbmAtLastRun: Data? { calls.withLock { $0.pbmAtRun } }

    var lastResultPath: String? { value(after: "--result") }
    var lastPNGPath: String? { value(after: "--png") }

    func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        let pbm = arguments.last.flatMap { $0.hasSuffix(".pbm") ? try? Data(contentsOf: URL(filePath: $0)) : nil }
        calls.withLock {
            $0.executable = executable
            $0.arguments = arguments
            $0.history.append(arguments)
            $0.pbmAtRun = pbm
        }
        if let data = resultData, let path = lastResultPath {
            try data.write(to: URL(filePath: path))
        }
        if let data = pngData, let path = lastPNGPath {
            try data.write(to: URL(filePath: path))
        }
        return ProcessOutcome(terminationStatus: terminationStatus, output: output)
    }

    private func value(after flag: String) -> String? {
        let args = lastArguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

func previewBitmap(rows: Int, markRow: Int = 0) -> Bitmap1 {
    var bitmap = Bitmap1(height: rows)
    bitmap.fillRow(markRow)
    return bitmap
}

func previewRunner(for bitmap: Bitmap1, status: Int32 = 0, output: String = "fake output") throws -> FakeRunner {
    FakeRunner(resultData: try printerFixtureData("result_print_ok"), terminationStatus: status,
               pngData: try PNGWriter.data(bitmap), output: output)
}

private let launch = PrinterLaunch(executable: URL(filePath: "/App/Contents/MacOS/picoruby"),
                                   leadingArguments: ["/App/Contents/Resources/cli/print.rb", "/App/Contents/Resources"])

private func client(_ runner: FakeRunner, now: Date = printerDate(hour: 10, minute: 42)) -> PrinterClient {
    PrinterClient(runner: runner, launch: launch, now: { now })
}

@Test func printPassesTheResultPathAndDensity() async throws {
    let runner = FakeRunner(resultFixture: "result_print_ok")
    _ = try await PrinterClient(runner: runner).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 3)
    #expect(runner.lastArguments.contains("--density"))
    #expect(runner.lastArguments.contains("3"))
    #expect(runner.lastArguments.contains("--result"))
}

@Test func printLaunchesTheBundledVMWithTheScriptAndRootFirstAndThePBMLast() async throws {
    let runner = FakeRunner(resultFixture: "result_print_ok")
    _ = try await client(runner).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    #expect(runner.lastExecutable == launch.executable)
    #expect(Array(runner.lastArguments.prefix(2)) == launch.leadingArguments)
    #expect(runner.lastArguments.last == "/tmp/a.pbm")
    #expect(!runner.lastArguments.contains("--status"))
}

@Test func printReturnsTheDecodedResult() async throws {
    let result = try await client(FakeRunner(resultFixture: "result_print_ok")).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    #expect(result.ok)
    #expect(result.mode == .print)
    #expect(result.job?.rows == 2400)
}

@Test func aFailedPrintIsReturnedNotThrown() async throws {
    let result = try await client(FakeRunner(resultFixture: "result_not_found", terminationStatus: 10))
        .print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    #expect(!result.ok)
    #expect(result.error == .notFound)
}

@Test func theResultIsReadFromTheFileEvenWhenTheExitCodeIsLost() async throws {
    let result = try await client(FakeRunner(resultFixture: "result_print_ok", terminationStatus: 0))
        .print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    #expect(result.exitCode == 0)
}

@Test func missingResultFileThrowsNoResultWithTheExitStatusAndOutput() async {
    let runner = FakeRunner(resultData: nil, terminationStatus: 134)
    await #expect(throws: PrinterClientError.noResult(terminationStatus: 134, output: "fake output")) {
        try await client(runner).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    }
}

@Test func garbledResultFileThrowsNoResult() async {
    let runner = FakeRunner(resultJSON: "not json", terminationStatus: 0)
    await #expect(throws: PrinterClientError.noResult(terminationStatus: 0, output: "fake output")) {
        try await client(runner).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    }
}

@Test func theResultFileIsRemovedAfterItIsRead() async throws {
    let runner = FakeRunner(resultFixture: "result_print_ok")
    _ = try await client(runner).print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    let path = try #require(runner.lastResultPath)
    #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func eachRunUsesAFreshResultPath() async throws {
    let runner = FakeRunner(resultFixture: "result_print_ok")
    let c = client(runner)
    _ = try await c.print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    let first = runner.lastResultPath
    _ = try await c.print(pbm: URL(filePath: "/tmp/a.pbm"), density: 4)
    #expect(first != runner.lastResultPath)
}

@Test func statusAsksForStatusOnlyAndPassesNoPBM() async throws {
    let runner = FakeRunner(resultFixture: "result_status_ok")
    let result = try await client(runner).status()
    #expect(runner.lastArguments.contains("--status"))
    #expect(runner.lastArguments.contains("--result"))
    #expect(!runner.lastArguments.contains("--density"))
    #expect(result.mode == .status)
}

@Test func refreshStatusShowsTheStatusLineWithTheCheckTime() async {
    let after = await client(FakeRunner(resultFixture: "result_status_ok")).refreshStatus(previous: nil)
    #expect(after.line == "電池83%・紙あり・カバー閉・温度正常（10:42確認）")
}

@Test func busyKeepsThePreviousStatus() async {
    let client = client(FakeRunner(resultJSON: printerBusyJSON, terminationStatus: 12))
    let before = PrinterStatusSnapshot(line: "電池83%・紙あり（10:42確認）")
    let after = await client.refreshStatus(previous: before)
    #expect(after == before)
}

@Test func busyWithNoPreviousStatusSaysTheStatusIsUnchecked() async {
    let after = await client(FakeRunner(resultJSON: printerBusyJSON, terminationStatus: 12)).refreshStatus(previous: nil)
    #expect(after.line.contains("未確認"))
}

@Test func aFailedCheckShowsUnknownWithTheCheckTimeAndKeepsTheReasonAsDetail() async {
    let after = await client(FakeRunner(resultFixture: "result_not_found", terminationStatus: 10)).refreshStatus(previous: nil)
    #expect(after.line == "状態不明（10:42確認）")
    #expect(after.detail == PrinterStatusText.message(for: .notFound))
}

@Test func aCrashWithNoResultFileShowsUnknownWithTheExitStatus() async {
    let after = await client(FakeRunner(resultData: nil, terminationStatus: 134)).refreshStatus(previous: nil)
    #expect(after.line == "状態不明（10:42確認）")
    #expect(after.detail?.contains("134") == true)
}

@Test func theSystemRunnerReturnsTheExitStatusAndTheCombinedOutput() async throws {
    let outcome = try await SystemProcessRunner().run(executable: URL(filePath: "/bin/sh"),
                                                      arguments: ["-c", "echo out; echo err 1>&2; exit 3"])
    #expect(outcome.terminationStatus == 3)
    #expect(outcome.output.contains("out"))
    #expect(outcome.output.contains("err"))
}

@Test func theSystemRunnerReturnsOutputLargerThanFourThousandBytesWhole() async throws {
    let outcome = try await SystemProcessRunner().run(
        executable: URL(filePath: "/bin/sh"),
        arguments: ["-c", "i=0; while [ $i -lt 5000 ]; do echo line$i; i=$((i+1)); done"])
    #expect(outcome.output.hasPrefix("line0\n"))
    #expect(outcome.output.hasSuffix("line4999\n"))
    #expect(!outcome.truncated)
}

@Test func theSystemRunnerKeepsTheTailAndFlagsOutputOverTheLimit() async throws {
    let outcome = try await SystemProcessRunner(outputLimit: 5).run(
        executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo head; echo tail"])
    #expect(outcome.output == "tail\n")
    #expect(outcome.truncated)
}

@Test func theSystemRunnerThrowsWhenTheExecutableIsMissing() async {
    await #expect(throws: (any Error).self) {
        try await SystemProcessRunner().run(executable: URL(filePath: "/nonexistent/picoruby"), arguments: [])
    }
}

@Test func theBundledLaunchPointsAtTheVMAndTheCLIResources() throws {
    let bundleURL = URL(filePath: "/Apps/Thermal Printer.app")
    let l = PrinterLaunch.bundled(at: bundleURL)
    #expect(l.executable.path == "/Apps/Thermal Printer.app/Contents/MacOS/picoruby")
    #expect(l.leadingArguments == ["/Apps/Thermal Printer.app/Contents/Resources/cli/print.rb",
                                   "/Apps/Thermal Printer.app/Contents/Resources"])
}

#if DEBUG
@Test func launchUsesTheBundledPicorubyWhenNoOverrideIsSet() {
    let bundle = URL(filePath: "/Apps/ThermalPrinter.app")
    #expect(PrinterLaunch.resolving(environment: [:], bundleURL: bundle) == PrinterLaunch.bundled(at: bundle))
    #expect(PrinterLaunch.resolving(environment: ["THERMALPRINTER_CLI": ""], bundleURL: bundle) == PrinterLaunch.bundled(at: bundle))
}

@Test func launchRunsTheOverrideScriptDirectlyWithoutLeadingArguments() {
    let bundle = URL(filePath: "/Apps/ThermalPrinter.app")
    let launch = PrinterLaunch.resolving(environment: ["THERMALPRINTER_CLI": "/tmp/fake-cli.sh"], bundleURL: bundle)
    #expect(launch.executable == URL(filePath: "/tmp/fake-cli.sh"))
    #expect(launch.leadingArguments.isEmpty)
}
#endif

@Test func previewRunsTheCLIAsADryRunWithAPNGPathAndThePBMLast() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap)
    _ = try await client(runner).preview(bitmap)
    let args = runner.lastArguments
    #expect(runner.lastExecutable == launch.executable)
    #expect(Array(args.prefix(2)) == launch.leadingArguments)
    #expect(args.contains("--dry-run"))
    #expect(args.last?.hasSuffix(".pbm") == true)
    #expect(args.firstIndex(of: "--png").map { args[$0 + 1].hasSuffix(".png") } == true)
    #expect(!args.contains("--status"))
    #expect(!args.contains("--density"))
}

@Test func previewReturnsTheCLIPNGAndTheSamePBMItHandedToTheCLI() async throws {
    let bitmap = previewBitmap(rows: 8, markRow: 3)
    let runner = try previewRunner(for: bitmap)
    let preview = try await client(runner).preview(bitmap)
    #expect(preview.png == (try PNGWriter.data(bitmap)))
    #expect(preview.image?.width == Bitmap1.width)
    #expect(preview.image?.height == 8)
    #expect(preview.pbm.path == runner.lastArguments.last)
    #expect(runner.pbmAtLastRun == PBMWriter.data(bitmap))
    #expect(try Data(contentsOf: preview.pbm) == PBMWriter.data(bitmap))
    try? FileManager.default.removeItem(at: preview.pbm)
}

@Test func previewRemovesItsPNGButKeepsThePBMForPrinting() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap)
    let preview = try await client(runner).preview(bitmap)
    let png = try #require(runner.lastPNGPath)
    #expect(!FileManager.default.fileExists(atPath: png))
    #expect(FileManager.default.fileExists(atPath: preview.pbm.path))
    try? FileManager.default.removeItem(at: preview.pbm)
}

@Test func aFailingCLIMakesPreviewThrowWithTheExitStatusAndOutputAndLeavesNoFiles() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap, status: 2, output: "phomemo-print: usage: bad pbm")
    await #expect(throws: PrinterClientError.previewFailed(terminationStatus: 2, output: "phomemo-print: usage: bad pbm")) {
        try await client(runner).preview(bitmap)
    }
    let pbm = try #require(runner.lastArguments.last)
    #expect(!FileManager.default.fileExists(atPath: pbm))
}

@Test func aCLIThatWritesNoPNGMakesPreviewThrow() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = FakeRunner(resultData: nil, terminationStatus: 0)
    await #expect(throws: PrinterClientError.previewFailed(terminationStatus: 0, output: "fake output")) {
        try await client(runner).preview(bitmap)
    }
}

@Test func theFailureMessageCarriesTheCLIOutput() {
    let error = PrinterClientError.previewFailed(terminationStatus: 2, output: "phomemo-print: usage: bad pbm\n")
    #expect(error.localizedDescription.contains("phomemo-print: usage: bad pbm"))
}
