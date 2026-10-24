import CoreGraphics
import Foundation
import ImageIO
import Testing
import ThermalPrinterCore

enum RealCLI {
    static let repoRoot: URL = {
        var directory = URL(filePath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appending(path: "bin/phomemo-print").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        fatalError("bin/phomemo-print not found above \(#filePath)")
    }()

    static let script = repoRoot.appending(path: "bin/phomemo-print")

    static let vm: URL = {
        if let path = ProcessInfo.processInfo.environment["PHOMEMO_PICORUBY"], !path.isEmpty {
            return URL(filePath: path)
        }
        return repoRoot.appending(path: "vendor/R2P2-darwin/build/host/bin/picoruby")
    }()

    static var vmExists: Bool { FileManager.default.isExecutableFile(atPath: vm.path) }

    static let launch = PrinterLaunch(executable: script, leadingArguments: [])

    static func client(runner: any ProcessRunner = SystemProcessRunner(), workDirectory: URL) -> PrinterClient {
        PrinterClient(runner: runner, launch: launch, workDirectory: workDirectory)
    }

    static func makeWorkDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "thermal-printer-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func entries(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    static func cardBitmap(_ name: String) throws -> Bitmap1 {
        let json = try Data(contentsOf: repoRoot.appending(path: "test/fixtures/cards/\(name).json"))
        return try StripComposer().bitmap(cardJSON: json)
    }

    static func blackMatrix(of image: CGImage) throws -> [[Bool]] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = try pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        var rows: [[Bool]] = []
        var y = 0
        while y < height {
            var row: [Bool] = []
            var x = 0
            while x < width {
                row.append(pixels[y * width + x] < 128)
                x += 1
            }
            rows.append(row)
            y += 1
        }
        return rows
    }

    static func mismatches(_ image: CGImage, _ bitmap: Bitmap1) throws -> Int {
        let matrix = try blackMatrix(of: image)
        var count = 0
        var y = 0
        while y < bitmap.height {
            var x = 0
            while x < Bitmap1.width {
                if matrix[y][x] != bitmap[x: x, y: y] { count += 1 }
                x += 1
            }
            y += 1
        }
        return count
    }
}

struct PBMReplacingRunner: ProcessRunner {
    let replacement: Data

    func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        let pbm = try #require(arguments.last)
        try replacement.write(to: URL(filePath: pbm))
        return try await SystemProcessRunner().run(executable: executable, arguments: arguments)
    }
}
