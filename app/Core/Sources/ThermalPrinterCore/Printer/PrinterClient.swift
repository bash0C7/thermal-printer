import CoreGraphics
import Foundation
import ImageIO

public struct PrinterLaunch: Equatable, Sendable {
    public var executable: URL
    public var leadingArguments: [String]

    public init(executable: URL, leadingArguments: [String]) {
        self.executable = executable
        self.leadingArguments = leadingArguments
    }

    public static func bundled(at bundleURL: URL) -> PrinterLaunch {
        let contents = bundleURL.appending(path: "Contents")
        let resources = contents.appending(path: "Resources")
        return PrinterLaunch(
            executable: contents.appending(path: "MacOS/picoruby"),
            leadingArguments: [resources.appending(path: "cli/print.rb").path, resources.path])
    }

    public static func bundled(_ bundle: Bundle = .main) -> PrinterLaunch {
        bundled(at: bundle.bundleURL)
    }

    #if DEBUG
    public static func resolving(environment: [String: String], bundleURL: URL) -> PrinterLaunch {
        guard let path = environment["THERMALPRINTER_CLI"], !path.isEmpty else {
            return bundled(at: bundleURL)
        }
        return PrinterLaunch(executable: URL(filePath: path), leadingArguments: [])
    }

    public static func resolving(
        environment: [String: String] = ProcessInfo.processInfo.environment, bundle: Bundle = .main
    ) -> PrinterLaunch {
        resolving(environment: environment, bundleURL: bundle.bundleURL)
    }
    #endif
}

public enum PrinterClientError: Error, Equatable, LocalizedError {
    case noResult(terminationStatus: Int32, output: String)
    case previewFailed(terminationStatus: Int32, output: String)
    case previewNotReady

    public var errorDescription: String? {
        switch self {
        case let .noResult(status, output):
            return Self.message(
                "CLIが結果を書かずに終了しました（終了コード\(status)）。Bluetoothの許可とアプリの同梱物を確認してください。", output)
        case let .previewFailed(status, output):
            return Self.message("CLIがプレビューを作れませんでした（終了コード\(status)）。", output)
        case .previewNotReady:
            return "現在の内容のプレビューがまだ表示されていないため、印刷できません。"
        }
    }

    private static func message(_ base: String, _ output: String) -> String {
        let tail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? base : "\(base)\n\(tail)"
    }
}

public struct CLIPreview: @unchecked Sendable {
    public let png: Data
    public let pbm: URL
    public let image: CGImage?

    public init(png: Data, pbm: URL) {
        self.png = png
        self.pbm = pbm
        self.image = CGImageSourceCreateWithData(png as CFData, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}

public struct PrinterClient: Sendable {
    private let runner: any ProcessRunner
    private let launch: PrinterLaunch
    private let now: @Sendable () -> Date
    private let workDirectory: URL

    public init(runner: any ProcessRunner = SystemProcessRunner(),
                launch: PrinterLaunch = .bundled(),
                now: @escaping @Sendable () -> Date = { Date() },
                workDirectory: URL = FileManager.default.temporaryDirectory) {
        self.runner = runner
        self.launch = launch
        self.now = now
        self.workDirectory = workDirectory
    }

    public func print(pbm: URL, density: Int) async throws -> PrintResult {
        try await invoke(["--density", String(density)], trailing: [pbm.path])
    }

    public func preview(_ bitmap: Bitmap1) async throws -> CLIPreview {
        let name = "thermal-printer-preview-\(UUID().uuidString)"
        let pbm = workDirectory.appending(path: "\(name).pbm")
        let png = workDirectory.appending(path: "\(name).png")
        defer { try? FileManager.default.removeItem(at: png) }
        do {
            try PBMWriter.data(bitmap).write(to: pbm)
            let arguments = launch.leadingArguments + ["--dry-run", "--png", png.path, pbm.path]
            let outcome = try await runner.run(executable: launch.executable, arguments: arguments)
            guard outcome.terminationStatus == 0, let data = try? Data(contentsOf: png) else {
                throw PrinterClientError.previewFailed(terminationStatus: outcome.terminationStatus, output: outcome.output)
            }
            let preview = CLIPreview(png: data, pbm: pbm)
            guard preview.image != nil else {
                throw PrinterClientError.previewFailed(terminationStatus: outcome.terminationStatus, output: outcome.output)
            }
            return preview
        } catch {
            try? FileManager.default.removeItem(at: pbm)
            throw error
        }
    }

    public func status() async throws -> PrintResult {
        try await invoke(["--status"], trailing: [])
    }

    public func refreshStatus(previous: PrinterStatusSnapshot?) async -> PrinterStatusSnapshot {
        let checkedAt = now()
        let unknown = PrinterStatusText.titleBar(
            PrintResult.Status(battery: nil, paper: nil, cover: nil, temperature: nil,
                               firmware: nil, serial: nil, autoOff: nil),
            checkedAt: checkedAt)
        do {
            let result = try await status()
            if result.error == .busy {
                return previous ?? PrinterStatusSnapshot(line: "使用中（状態は未確認）")
            }
            if result.ok, let status = result.status {
                return PrinterStatusSnapshot(line: PrinterStatusText.titleBar(status, checkedAt: checkedAt))
            }
            let detail = PrinterStatusText.message(for: result.error ?? .unknown)
            return PrinterStatusSnapshot(line: unknown, detail: detail)
        } catch {
            return PrinterStatusSnapshot(line: unknown, detail: error.localizedDescription)
        }
    }

    private func invoke(_ options: [String], trailing: [String]) async throws -> PrintResult {
        let resultURL = workDirectory.appending(path: "thermal-printer-result-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: resultURL) }

        let arguments = launch.leadingArguments + options + ["--result", resultURL.path] + trailing
        let outcome = try await runner.run(executable: launch.executable, arguments: arguments)

        guard let data = try? Data(contentsOf: resultURL),
              let result = try? JSONDecoder().decode(PrintResult.self, from: data)
        else {
            throw PrinterClientError.noResult(terminationStatus: outcome.terminationStatus, output: outcome.output)
        }
        return result
    }
}
