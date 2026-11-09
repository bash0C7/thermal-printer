import Foundation

public enum GHAccountScope {
    public static let defaultGhqRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "ghq/github.com")

    public static func directory(
        for owner: String, ghqRoot: URL = defaultGhqRoot, fileManager: FileManager = .default
    ) -> URL? {
        let entries = (try? fileManager.contentsOfDirectory(
            at: ghqRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.first { entry in
            entry.lastPathComponent.caseInsensitiveCompare(owner) == .orderedSame
                && (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    public static func runner(for repo: RepoRef?, ghqRoot: URL = defaultGhqRoot) -> any ProcessRunner {
        guard let repo, let directory = directory(for: repo.owner, ghqRoot: ghqRoot) else {
            return SystemProcessRunner()
        }
        return ScopedGHRunner(base: SystemProcessRunner(currentDirectory: directory))
    }
}

public struct ScopedGHRunner: ProcessRunner {
    private static let shell = URL(filePath: "/bin/zsh")
    private static let execPositionalArguments = ["-c", "exec \"$@\"", "zsh"]

    private let base: any ProcessRunner

    public init(base: any ProcessRunner) {
        self.base = base
    }

    public func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        try await base.run(
            executable: Self.shell,
            arguments: Self.execPositionalArguments + [executable.path] + arguments)
    }
}
