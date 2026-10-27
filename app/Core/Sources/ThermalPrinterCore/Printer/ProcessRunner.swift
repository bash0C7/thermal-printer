import Foundation

public struct ProcessOutcome: Equatable, Sendable {
    public let terminationStatus: Int32
    public let output: String
    public let truncated: Bool

    public init(terminationStatus: Int32, output: String, truncated: Bool = false) {
        self.terminationStatus = terminationStatus
        self.output = output
        self.truncated = truncated
    }
}

public protocol ProcessRunner: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome
}

public struct SystemProcessRunner: ProcessRunner {
    public static let defaultOutputLimit = 4 * 1024 * 1024

    private let outputLimit: Int

    public init(outputLimit: Int = SystemProcessRunner.defaultOutputLimit) {
        self.outputLimit = outputLimit
    }

#if os(macOS)
    public func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        let log = FileManager.default.temporaryDirectory
            .appending(path: "thermal-printer-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let sink = try FileHandle(forWritingTo: log)
        defer {
            try? sink.close()
            try? FileManager.default.removeItem(at: log)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = sink
        process.standardError = sink

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let code = finished.terminationReason == .exit
                    ? finished.terminationStatus
                    : 128 + finished.terminationStatus
                continuation.resume(returning: code)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let data = try Data(contentsOf: log)
        return ProcessOutcome(
            terminationStatus: status,
            output: String(decoding: data.suffix(outputLimit), as: UTF8.self),
            truncated: data.count > outputLimit)
    }
#else
    public func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        throw CocoaError(.featureUnsupported)
    }
#endif
}
