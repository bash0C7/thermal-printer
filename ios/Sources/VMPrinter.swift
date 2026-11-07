import Foundation
import ThermalPrinterCore

enum VMPrinterError: Error, LocalizedError {
    case bootSourceMissing
    case vmFailedToOpen
    case noResult(String)

    var errorDescription: String? {
        switch self {
        case .bootSourceMissing: "同梱のRubyソースが見つかりません"
        case .vmFailedToOpen: "Ruby VMを起動できません"
        case .noResult(let output): "印刷結果が得られません（\(output)）"
        }
    }
}

final class VMPrinter: @unchecked Sendable {
    static let shared = VMPrinter()

    static let heldJobTimeout = Duration.seconds(90)

    private let queue = DispatchQueue(label: "com.bash0c7.thermalprinter.vm")
    private var vm: UnsafeMutableRawPointer?
    private let directory = FileManager.default.temporaryDirectory
    private let holdLock = NSLock()
    private var wantsHold = false

    private init() {}

    private var holdPrefix: String { directory.appending(path: "cheki-").path }
    private func holdFile(_ name: String) -> URL { URL(fileURLWithPath: holdPrefix + name) }

    var isHeldLinked: Bool {
        (try? String(contentsOf: holdFile("state"), encoding: .utf8)) == "linked"
    }

    func startHolding(density: Int) {
        setWantsHold(true)
        queue.async {
            guard self.holdLock.withLock({ self.wantsHold }) else { return }
            for name in ["close", "job.pbm", "result.json", "state"] {
                try? FileManager.default.removeItem(at: self.holdFile(name))
            }
            do {
                let handle = try self.openIfNeeded()
                let argument = "\(self.holdPrefix)\t\(density)"
                let out = "hold".withCString { m in argument.withCString { a in vm_call(handle, m, a) } }
                NSLog("[ThermalPrinterPhone] hold ended: %@", out.map { String(cString: $0) } ?? "")
                if let out { free(out) }
            } catch {
                NSLog("[ThermalPrinterPhone] hold failed: %@", error.localizedDescription)
            }
        }
    }

    func stopHolding() {
        setWantsHold(false)
        FileManager.default.createFile(atPath: holdFile("close").path, contents: Data())
    }

    func printHeld(_ bitmap: Bitmap1) async throws -> PrintResult {
        let result = holdFile("result.json")
        let job = holdFile("job.pbm")
        let staged = holdFile("job.pbm.tmp")
        try? FileManager.default.removeItem(at: result)
        try PBMWriter.data(bitmap).write(to: staged)
        try FileManager.default.moveItem(at: staged, to: job)
        let deadline = ContinuousClock.now + Self.heldJobTimeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            guard let data = try? Data(contentsOf: result) else { continue }
            try? FileManager.default.removeItem(at: result)
            return try JSONDecoder().decode(PrintResult.self, from: data)
        }
        try? FileManager.default.removeItem(at: job)
        throw VMPrinterError.noResult("hold")
    }

    private func setWantsHold(_ value: Bool) {
        holdLock.withLock { wantsHold = value }
    }

    func warmUp() {
        queue.async {
            do {
                _ = try self.openIfNeeded()
                NSLog("[ThermalPrinterPhone] VM opened")
            } catch {
                NSLog("[ThermalPrinterPhone] VM failed: %@", error.localizedDescription)
            }
        }
    }

    func print(_ bitmap: Bitmap1, density: Int) async throws -> PrintResult {
        try await job(bitmap, ["--density", String(density)])
    }

    func dryRun(_ bitmap: Bitmap1) async throws -> PrintResult {
        try await job(bitmap, ["--dry-run"])
    }

    private func job(_ bitmap: Bitmap1, _ options: [String]) async throws -> PrintResult {
        let pbm = directory.appending(path: "job-\(UUID().uuidString).pbm")
        try PBMWriter.data(bitmap).write(to: pbm)
        defer { try? FileManager.default.removeItem(at: pbm) }
        return try await run(options, trailing: [pbm.path])
    }

    func status() async throws -> PrintResult {
        try await run(["--status"], trailing: [])
    }

    private func run(_ options: [String], trailing: [String]) async throws -> PrintResult {
        let result = directory.appending(path: "result-\(UUID().uuidString).json")
        let lock = directory.appending(path: "phomemo-print.lock")
        defer { try? FileManager.default.removeItem(at: result) }
        let argument = ([lock.path] + options + ["--result", result.path] + trailing).joined(separator: "\t")
        let output = try await call("run_cli", argument)
        guard let data = try? Data(contentsOf: result),
            let decoded = try? JSONDecoder().decode(PrintResult.self, from: data)
        else { throw VMPrinterError.noResult(output) }
        return decoded
    }

    private func call(_ method: String, _ argument: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let handle = try self.openIfNeeded()
                    let out = method.withCString { m in argument.withCString { a in vm_call(handle, m, a) } }
                    let text = out.map { String(cString: $0) } ?? ""
                    if let out { free(out) }
                    continuation.resume(returning: text)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func openIfNeeded() throws -> UnsafeMutableRawPointer {
        if let vm { return vm }
        let bundle = Bundle.main
        guard let cli = bundle.url(forResource: "phomemo_cli", withExtension: "rb"),
            let app = bundle.url(forResource: "app", withExtension: "rb"),
            let cliSource = try? String(contentsOf: cli, encoding: .utf8),
            let appSource = try? String(contentsOf: app, encoding: .utf8)
        else { throw VMPrinterError.bootSourceMissing }
        guard let handle = (cliSource + "\n" + appSource).withCString({ vm_open($0) }) else {
            throw VMPrinterError.vmFailedToOpen
        }
        vm = handle
        return handle
    }
}
