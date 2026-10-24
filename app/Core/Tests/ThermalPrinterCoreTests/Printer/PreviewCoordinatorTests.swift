import Foundation
import Testing
@testable import ThermalPrinterCore

private let coordinatorLaunch = PrinterLaunch(
    executable: URL(filePath: "/App/Contents/MacOS/picoruby"),
    leadingArguments: ["/App/Contents/Resources/cli/print.rb", "/App/Contents/Resources"])

@MainActor
private func coordinator(_ runner: FakeRunner) -> PreviewCoordinator {
    PreviewCoordinator(client: PrinterClient(runner: runner, launch: coordinatorLaunch))
}

@MainActor
private func cleanUp(_ coordinator: PreviewCoordinator) {
    coordinator.update(Bitmap1(height: 0))
}

@MainActor
@Test func aStripWithNoRowsHasNoPreviewAndNeverCallsTheCLI() async throws {
    let runner = try previewRunner(for: previewBitmap(rows: 8))
    let c = coordinator(runner)
    c.update(Bitmap1(height: 0))
    await c.waitUntilSettled()
    #expect(c.readyPreview == nil)
    #expect(!c.isGenerating)
    #expect(runner.history.isEmpty)
}

@MainActor
@Test func aChangedStripIsGeneratingAtOnceAndReadyAfterTheCLIReturns() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap)
    let c = coordinator(runner)
    c.update(bitmap)
    #expect(c.isGenerating)
    #expect(c.readyPreview == nil)
    await c.waitUntilSettled()
    #expect(!c.isGenerating)
    let preview = try #require(c.readyPreview)
    #expect(preview.png == (try PNGWriter.data(bitmap)))
    #expect(runner.pbmAtLastRun == PBMWriter.data(bitmap))
    cleanUp(c)
}

@MainActor
@Test func aStripChangeInvalidatesTheReadyPreviewAndRunsTheCLIAgain() async throws {
    let first = previewBitmap(rows: 8, markRow: 1)
    let second = previewBitmap(rows: 16, markRow: 2)
    let runner = try previewRunner(for: first)
    let c = coordinator(runner)
    c.update(first)
    await c.waitUntilSettled()
    let firstPBM = try #require(c.readyPreview?.pbm)

    c.update(second)
    #expect(c.readyPreview == nil)
    await c.waitUntilSettled()

    let secondPBM = try #require(c.readyPreview?.pbm)
    #expect(runner.history.count == 2)
    #expect(secondPBM != firstPBM)
    #expect(runner.pbmAtLastRun == PBMWriter.data(second))
    #expect(!FileManager.default.fileExists(atPath: firstPBM.path))
    cleanUp(c)
}

@MainActor
@Test func onlyTheLastOfSeveralQuickChangesIsShownAndTheOthersLeaveNoFiles() async throws {
    let a = previewBitmap(rows: 8, markRow: 1)
    let b = previewBitmap(rows: 8, markRow: 2)
    let last = previewBitmap(rows: 8, markRow: 3)
    let runner = try previewRunner(for: a)
    let c = coordinator(runner)
    c.update(a)
    c.update(b)
    c.update(last)
    await c.waitUntilSettled()

    let shown = try #require(c.readyPreview?.pbm)
    #expect(try Data(contentsOf: shown) == PBMWriter.data(last))
    let leftovers = runner.history.compactMap(\.last).filter { FileManager.default.fileExists(atPath: $0) }
    #expect(leftovers == [shown.path])
    cleanUp(c)
}

@MainActor
@Test func aFailingCLIShowsTheFailureAndAllowsNoPrint() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap, status: 2, output: "phomemo-print: usage: bad pbm")
    let c = coordinator(runner)
    c.update(bitmap)
    await c.waitUntilSettled()
    #expect(c.readyPreview == nil)
    #expect(!c.isGenerating)
    #expect(c.failureMessage?.contains("phomemo-print: usage: bad pbm") == true)
    await #expect(throws: PrinterClientError.previewNotReady) {
        try await c.printReady(density: 4)
    }
}

@MainActor
@Test func printingHandsTheCLITheSamePBMThePreviewUsedWithoutRegeneratingIt() async throws {
    let bitmap = previewBitmap(rows: 8, markRow: 5)
    let runner = try previewRunner(for: bitmap)
    let c = coordinator(runner)
    c.update(bitmap)
    await c.waitUntilSettled()
    let pbm = try #require(c.readyPreview?.pbm)

    let result = try await c.printReady(density: 3)

    #expect(result.ok)
    #expect(runner.history.count == 2)
    let args = runner.lastArguments
    #expect(args.last == pbm.path)
    #expect(!args.contains("--dry-run"))
    #expect(args.contains("--density"))
    #expect(args.contains("3"))
    #expect(runner.pbmAtLastRun == PBMWriter.data(bitmap))
    cleanUp(c)
}

@MainActor
@Test func printingIsRefusedWhileTheStripChangedAndThePreviewIsStale() async throws {
    let first = previewBitmap(rows: 8, markRow: 1)
    let runner = try previewRunner(for: first)
    let c = coordinator(runner)
    c.update(first)
    await c.waitUntilSettled()

    c.update(previewBitmap(rows: 8, markRow: 2))

    await #expect(throws: PrinterClientError.previewNotReady) {
        try await c.printReady(density: 4)
    }
    #expect(runner.history.allSatisfy { $0.contains("--dry-run") })
    await c.waitUntilSettled()
    cleanUp(c)
}

@MainActor
@Test func theReadyPBMIsKeptForRepeatedPrintsAndRemovedOnceTheStripChanges() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap)
    let c = coordinator(runner)
    c.update(bitmap)
    await c.waitUntilSettled()
    let pbm = try #require(c.readyPreview?.pbm)

    _ = try await c.printReady(density: 4)
    #expect(FileManager.default.fileExists(atPath: pbm.path))

    c.update(Bitmap1(height: 0))
    #expect(!FileManager.default.fileExists(atPath: pbm.path))
}

private final class GatedPrintRunner: ProcessRunner {
    private let inner: FakeRunner
    private let gate = AsyncStream<Void>.makeStream()
    private let entered = AsyncStream<Void>.makeStream()

    init(_ inner: FakeRunner) {
        self.inner = inner
    }

    func waitUntilPrintStarts() async {
        for await _ in entered.stream { return }
    }

    func releasePrint() {
        gate.continuation.yield()
    }

    func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        if !arguments.contains("--dry-run") {
            entered.continuation.yield()
            for await _ in gate.stream { break }
        }
        return try await inner.run(executable: executable, arguments: arguments)
    }
}

@MainActor
@Test func aStripChangeDuringAPrintKeepsThePBMUntilThePrintEnds() async throws {
    let bitmap = previewBitmap(rows: 8)
    let gated = GatedPrintRunner(try previewRunner(for: bitmap))
    let c = PreviewCoordinator(client: PrinterClient(runner: gated, launch: coordinatorLaunch))
    c.update(bitmap)
    await c.waitUntilSettled()
    let pbm = try #require(c.readyPreview?.pbm)

    let printing = Task { try await c.printReady(density: 4) }
    await gated.waitUntilPrintStarts()
    c.update(Bitmap1(height: 0))
    #expect(FileManager.default.fileExists(atPath: pbm.path))

    gated.releasePrint()
    _ = try await printing.value
    #expect(!FileManager.default.fileExists(atPath: pbm.path))
}

@MainActor
@Test func invalidatingDropsTheReadyPreviewAtOnceAndShowsGeneratingAndIgnoresAnInFlightResult() async throws {
    let bitmap = previewBitmap(rows: 8)
    let runner = try previewRunner(for: bitmap)
    let c = coordinator(runner)
    c.update(bitmap)
    await c.waitUntilSettled()
    let pbm = try #require(c.readyPreview?.pbm)

    c.invalidate()

    #expect(c.readyPreview == nil)
    #expect(c.isGenerating)
    #expect(!FileManager.default.fileExists(atPath: pbm.path))
    await #expect(throws: PrinterClientError.previewNotReady) {
        try await c.printReady(density: 4)
    }
}
