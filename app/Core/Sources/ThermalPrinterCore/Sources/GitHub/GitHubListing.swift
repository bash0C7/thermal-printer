import Foundation

public struct GitHubListing: Identifiable, Equatable, Sendable {
    public let number: Int
    public let repository: String
    public let title: String
    public let url: String
    public let isPullRequest: Bool
    public let isReviewRequest: Bool

    public init(
        number: Int, repository: String, title: String, url: String,
        isPullRequest: Bool, isReviewRequest: Bool
    ) {
        self.number = number
        self.repository = repository
        self.title = title
        self.url = url
        self.isPullRequest = isPullRequest
        self.isReviewRequest = isReviewRequest
    }

    public var id: String { "github:\(url)" }

    public var label: String {
        let base = "\(repository) \(isPullRequest ? "PR " : "")#\(number)"
        return isReviewRequest ? "\(base) レビュー依頼" : base
    }
}

public enum GitHubListingError: Error, LocalizedError {
    case ghMissing
    case ghFailed(String)
    case unreadable

    public var errorDescription: String? {
        switch self {
        case .ghMissing: "gh が見つかりません（/opt/homebrew/bin/gh か /usr/local/bin/gh が要ります）"
        case .ghFailed(let line): line.isEmpty ? "gh が失敗しました" : "gh が失敗しました（\(line)）"
        case .unreadable: "gh の応答を読めません"
        }
    }
}

public enum GitHubListingLoader {
    private static let personalReviewQuery = "user-review-requested:@me"

    static func arguments(noun: String, assigned: Bool, repo: RepoRef?) -> [String] {
        var arguments = ["search", noun]
        arguments += assigned ? ["--assignee", "@me"] : [personalReviewQuery]
        arguments += ["--state", "open", "--sort", "updated", "--limit", "50", "--json", "number,title,repository,url"]
        if let repo {
            arguments += ["--repo", repo.nameWithOwner]
        }
        return arguments
    }

    private struct Row: Decodable {
        struct Repository: Decodable {
            let nameWithOwner: String
        }

        let number: Int
        let title: String
        let url: String
        let repository: Repository
    }

    public static func load(
        repo: RepoRef?, runner: any ProcessRunner, locator: GHLocator = GHLocator()
    ) async throws -> [GitHubListing] {
        guard let gh = locator.locate() else { throw GitHubListingError.ghMissing }
        let issues = try await search("issues", assigned: true, isPullRequest: false, repo: repo, gh: gh, runner: runner)
        let assignedPulls = try await search("prs", assigned: true, isPullRequest: true, repo: repo, gh: gh, runner: runner)
        let reviewPulls = try await search("prs", assigned: false, isPullRequest: true, repo: repo, gh: gh, runner: runner)
        let assignedURLs = Set(assignedPulls.map(\.url))
        let reviewOnly = reviewPulls.filter { !assignedURLs.contains($0.url) }
        return issues + assignedPulls + reviewOnly
    }

    private static func search(
        _ noun: String, assigned: Bool, isPullRequest: Bool, repo: RepoRef?, gh: URL, runner: any ProcessRunner
    ) async throws -> [GitHubListing] {
        let outcome = try await runner.run(
            executable: gh, arguments: arguments(noun: noun, assigned: assigned, repo: repo))
        guard outcome.terminationStatus == 0 else {
            let line = outcome.output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            throw GitHubListingError.ghFailed(String(line.prefix(80)))
        }
        guard !outcome.truncated,
              let rows = try? JSONDecoder().decode([Row].self, from: Data(outcome.output.utf8))
        else { throw GitHubListingError.unreadable }
        return rows.map {
            GitHubListing(
                number: $0.number, repository: $0.repository.nameWithOwner, title: $0.title, url: $0.url,
                isPullRequest: isPullRequest, isReviewRequest: !assigned)
        }
    }
}
