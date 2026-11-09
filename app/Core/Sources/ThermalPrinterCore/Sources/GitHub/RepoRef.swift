import Foundation

public struct RepoRef: Equatable, Sendable, Codable {
    private static let hosts: Set<String> = ["github.com", "www.github.com"]
    private static let gitSuffix = ".git"
    private static let queryOrFragment: Set<Character> = ["?", "#"]

    public let owner: String
    public let name: String

    public var nameWithOwner: String { "\(owner)/\(name)" }

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    public static func parse(_ text: String) -> RepoRef? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace) else { return nil }

        let segments = trimmed.split(separator: "/").map(String.init)
        if trimmed.contains("://") {
            return pathAfterHost(segments, hasScheme: true).flatMap(make)
        }
        if let path = pathAfterHost(segments, hasScheme: false) {
            return make(path)
        }
        return segments.count == 2 ? make(segments) : nil
    }

    static func isOwner(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLetter || first.isNumber else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    static func isRepo(_ name: String) -> Bool {
        guard let first = name.first, first != "-", name != ".", name != ".." else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }

    private static func pathAfterHost(_ segments: [String], hasScheme: Bool) -> [String]? {
        if hasScheme {
            guard segments.count >= 3, ["https:", "http:"].contains(segments[0]), hosts.contains(segments[1])
            else { return nil }
            return Array(segments.dropFirst(2))
        }
        guard let first = segments.first, hosts.contains(first) else { return nil }
        return Array(segments.dropFirst())
    }

    private static func make(_ path: [String]) -> RepoRef? {
        guard path.count >= 2 else { return nil }
        var name = String(path[1].prefix { !queryOrFragment.contains($0) })
        if name.hasSuffix(gitSuffix) { name.removeLast(gitSuffix.count) }
        guard isOwner(path[0]), isRepo(name) else { return nil }
        return RepoRef(owner: path[0], name: name)
    }
}
