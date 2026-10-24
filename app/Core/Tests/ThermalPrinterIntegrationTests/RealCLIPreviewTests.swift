import Foundation
import Testing
import ThermalPrinterCore

@Suite(.enabled(if: RealCLI.vmExists, "product VM not built: run rake vm:build or set PHOMEMO_PICORUBY"))
struct RealCLIPreviewTests {
    @Test(arguments: ["github", "slack", "url", "reminder"])
    func theCLIPNGOfACardStripEqualsTheComposedBitmap(card: String) async throws {
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try RealCLI.cardBitmap(card)

        let preview = try await RealCLI.client(workDirectory: directory).preview(bitmap)

        let image = try #require(preview.image)
        #expect(image.width == Bitmap1.width)
        #expect(image.height == bitmap.height)
        #expect(try RealCLI.mismatches(image, bitmap) == 0)
    }

    @Test func theCLIPNGOfAMarkdownStripEqualsTheComposedBitmap() async throws {
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = StripComposer().compose([.markdown("# 見出し\n\n本文の段落。\n\n- 箇条書き一\n- 箇条書き二")]).bitmap
        #expect(!bitmap.blackPixels(inColumns: 0..<Bitmap1.width).isEmpty)

        let preview = try await RealCLI.client(workDirectory: directory).preview(bitmap)

        let image = try #require(preview.image)
        #expect(image.width == Bitmap1.width)
        #expect(image.height == bitmap.height)
        #expect(try RealCLI.mismatches(image, bitmap) == 0)
    }

    @Test func aStripTallerThanOneRasterBlockRoundTripsToAPNGOfTheSameHeight() async throws {
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paragraph = String(repeating: "長い段落の文章です。", count: 20)
        let bitmap = StripComposer().compose([.markdown(Array(repeating: paragraph, count: 6).joined(separator: "\n\n"))]).bitmap
        #expect(bitmap.height > 255 * 2)

        let preview = try await RealCLI.client(workDirectory: directory).preview(bitmap)

        let image = try #require(preview.image)
        #expect(image.height == bitmap.height)
        #expect(try RealCLI.mismatches(image, bitmap) == 0)
    }

    @Test func aStripOfExactlyTwoRasterBlocksRoundTripsToAPNGOfTheSameHeight() async throws {
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var bitmap = Bitmap1(height: 256)
        var y = 0
        while y < bitmap.height {
            bitmap.set(x: y % Bitmap1.width, y: y)
            bitmap.set(x: Bitmap1.width - 1 - (y % Bitmap1.width), y: y)
            y += 1
        }

        let preview = try await RealCLI.client(workDirectory: directory).preview(bitmap)

        let image = try #require(preview.image)
        #expect(image.height == 256)
        #expect(try RealCLI.mismatches(image, bitmap) == 0)
    }

    @Test func aPBMOfTheWrongWidthMakesPreviewThrowWithExitStatusTwoAndTheCLIMessage() async throws {
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wrongWidth = Data("P4\n16 2\n".utf8) + Data(repeating: 0, count: 4)
        let client = RealCLI.client(runner: PBMReplacingRunner(replacement: wrongWidth), workDirectory: directory)

        let thrown = await #expect(throws: PrinterClientError.self) {
            try await client.preview(Bitmap1(height: 8))
        }

        guard case let .previewFailed(status, output)? = thrown else {
            Issue.record("expected previewFailed, got \(String(describing: thrown))")
            return
        }
        #expect(status == 2)
        #expect(output.contains("phomemo-print: invalid_input"))
        #expect(output.contains("width must be 384"))
        #expect(try RealCLI.entries(in: directory).isEmpty)
    }

    @Test func thePBMHandedToTheCLIIsTheFileThatStaysForPrinting() async throws {
        let directory = try RealCLI.makeWorkDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = try RealCLI.cardBitmap("github")

        let preview = try await RealCLI.client(workDirectory: directory).preview(bitmap)

        #expect(FileManager.default.fileExists(atPath: preview.pbm.path))
        #expect(try Data(contentsOf: preview.pbm) == PBMWriter.data(bitmap))
        #expect(try RealCLI.entries(in: directory) == [preview.pbm.lastPathComponent])
    }
}
