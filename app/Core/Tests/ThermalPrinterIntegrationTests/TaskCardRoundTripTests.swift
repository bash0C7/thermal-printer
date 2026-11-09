import Foundation
import Testing
import ThermalPrinterCore

private let fixtureVault = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "ThermalPrinterCoreTests/Sources/TaskForge/Fixtures/vault", directoryHint: .isDirectory)

private struct Passthrough: Summarizer {
    func summarize(_ text: String, kind: SummaryKind) async -> Summary {
        Summary(text: text, usedModel: true)
    }
}

@Suite(.enabled(if: RealCLI.vmExists, "product VM not built: run rake vm:build or set PHOMEMO_PICORUBY"))
struct TaskCardRoundTripTests {
    @Test func aTaskCardPreviewedByTheRealCLIStillCarriesTheTaskLinkInItsQR() async throws {
        let notes = try TaskForgeSource.openTasks(vault: fixtureVault)
        let note = try #require(notes.first { $0.title == "期限つき" })
        let card = await TaskForgeCard.make(note, vaultName: "my-vault", now: Date(), summarizer: Passthrough())
        let bitmap = StripComposer().compose([.card(card)]).bitmap
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let image = try #require(try await RealCLI.client(workDirectory: directory).preview(bitmap).image)

        #expect(try QRReader.payloads(in: image) == [card.url!])
    }
}
