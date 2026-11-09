import Foundation

let fixtureVault = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "Fixtures/vault", directoryHint: .isDirectory)

func taskForgeFixture(_ relativePath: String) throws -> String {
    try String(contentsOf: fixtureVault.appending(path: relativePath), encoding: .utf8)
}
