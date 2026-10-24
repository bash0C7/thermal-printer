import Foundation

public struct GHLocator: Sendable {
    public static let defaultCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private let candidates: [String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        candidates: [String] = GHLocator.defaultCandidates,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.candidates = candidates
        self.isExecutable = isExecutable
    }

    public func locate() -> URL? {
        candidates.first(where: isExecutable).map { URL(filePath: $0) }
    }
}
