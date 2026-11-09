import Foundation
import Testing
@testable import ThermalPrinterCore

private func makeGhqRoot(owners: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "ghq-\(UUID().uuidString)")
    for owner in owners {
        try FileManager.default.createDirectory(
            at: root.appending(path: owner), withIntermediateDirectories: true)
    }
    return root
}

@Test func theOwnerDirectoryIsFoundIgnoringCaseAndReturnedWithItsRealSpelling() throws {
    let root = try makeGhqRoot(owners: ["Octo-Org", "other-org"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GHAccountScope.directory(for: "octo-org", ghqRoot: root)?.lastPathComponent == "Octo-Org")
    #expect(GHAccountScope.directory(for: "other-org", ghqRoot: root)?.lastPathComponent == "other-org")
}

@Test func anOwnerWithoutADirectoryHasNoScope() throws {
    let root = try makeGhqRoot(owners: [])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GHAccountScope.directory(for: "nobody", ghqRoot: root) == nil)
}

@Test func theScopedRunnerHandsGhAndItsArgumentsToZshAsPositionalArguments() async throws {
    let base = FakeGHRunner(output: "")
    _ = try await ScopedGHRunner(base: base).run(
        executable: URL(filePath: "/opt/homebrew/bin/gh"), arguments: ["search", "prs", "a/b; rm -rf ~"])
    #expect(base.lastExecutable == URL(filePath: "/bin/zsh"))
    #expect(base.lastArguments == ["-c", "exec \"$@\"", "zsh", "/opt/homebrew/bin/gh", "search", "prs", "a/b; rm -rf ~"])
}

@Test func theScopedRunnerRunsTheCommandInsideZshForReal() async throws {
    let outcome = try await ScopedGHRunner(base: SystemProcessRunner())
        .run(executable: URL(filePath: "/bin/echo"), arguments: ["$HOME", "a b"])
    #expect(outcome.output == "$HOME a b\n")
}

@Test func aRepoWithAnOwnerDirectoryGetsAScopedRunnerAndOtherwiseThePlainOne() throws {
    let root = try makeGhqRoot(owners: ["octo-org"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(GHAccountScope.runner(for: RepoRef(owner: "octo-org", name: "sample"), ghqRoot: root) is ScopedGHRunner)
    #expect(GHAccountScope.runner(for: RepoRef(owner: "nobody", name: "x"), ghqRoot: root) is SystemProcessRunner)
    #expect(GHAccountScope.runner(for: nil, ghqRoot: root) is SystemProcessRunner)
}
