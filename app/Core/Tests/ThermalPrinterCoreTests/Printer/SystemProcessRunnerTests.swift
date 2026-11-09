import Foundation
import Testing
@testable import ThermalPrinterCore

private func physicalPath(of url: URL) -> String? {
    guard let resolved = realpath(url.path, nil) else { return nil }
    defer { free(resolved) }
    return String(cString: resolved)
}

@Test func aRunnerGivenADirectoryStartsTheProcessThere() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let outcome = try await SystemProcessRunner(currentDirectory: dir)
        .run(executable: URL(filePath: "/bin/pwd"), arguments: ["-P"])
    #expect(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)
        == physicalPath(of: dir))
}
