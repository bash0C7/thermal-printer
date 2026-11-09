import Foundation
import Testing
@testable import ThermalPrinterCore

private let presentGH = GHLocator(isExecutable: { _ in true })

private struct ScriptedGHRunner: ProcessRunner {
    let issues: String
    let assignedPulls: String
    let reviewPulls: String

    func run(executable: URL, arguments: [String]) async throws -> ProcessOutcome {
        let output =
            if arguments.contains("issues") { issues }
            else if arguments.contains("user-review-requested:@me") { reviewPulls }
            else { assignedPulls }
        return ProcessOutcome(terminationStatus: 0, output: output, truncated: false)
    }
}

private func rows(_ numbers: Int...) -> String {
    let items = numbers.map {
        #"{"number":\#($0),"title":"t\#($0)","url":"https://github.com/o/r/pull/\#($0)","repository":{"nameWithOwner":"o/r"}}"#
    }
    return "[" + items.joined(separator: ",") + "]"
}

private func contains(_ arguments: [String], pair: [String]) -> Bool {
    zip(arguments, arguments.dropFirst()).contains { [$0, $1] == pair }
}

@Test func assignedSearchesKeepTheirCurrentArgumentsWhenNoRepoIsGiven() {
    #expect(GitHubListingLoader.arguments(noun: "issues", assigned: true, repo: nil) ==
        ["search", "issues", "--assignee", "@me", "--state", "open",
         "--sort", "updated", "--limit", "50", "--json", "number,title,repository,url"])
}

@Test func aRepoNarrowsEverySearch() {
    let repo = RepoRef(owner: "octo-org", name: "sample")
    #expect(contains(GitHubListingLoader.arguments(noun: "prs", assigned: true, repo: repo),
                     pair: ["--repo", "octo-org/sample"]))
    #expect(contains(GitHubListingLoader.arguments(noun: "prs", assigned: false, repo: repo),
                     pair: ["--repo", "octo-org/sample"]))
}

@Test func reviewRequestsAskForPersonalRequestsOnly() {
    let args = GitHubListingLoader.arguments(noun: "prs", assigned: false, repo: nil)
    #expect(args.contains("user-review-requested:@me"))
    #expect(!args.contains("--review-requested"))
    #expect(!args.contains("--assignee"))
}

@Test func aPullRequestBothAssignedAndUnderReviewIsListedOnceAsAssigned() async throws {
    let runner = ScriptedGHRunner(issues: rows(1), assignedPulls: rows(3), reviewPulls: rows(3, 4))
    let listings = try await GitHubListingLoader.load(repo: nil, runner: runner, locator: presentGH)
    #expect(listings.map(\.number) == [1, 3, 4])
    #expect(listings.map(\.isReviewRequest) == [false, false, true])
    #expect(listings.map(\.isPullRequest) == [false, true, true])
}

@Test func aReviewRequestLabelSaysSo() {
    let listing = GitHubListing(
        number: 4, repository: "o/r", title: "t", url: "https://github.com/o/r/pull/4",
        isPullRequest: true, isReviewRequest: true)
    #expect(listing.label == "o/r PR #4 レビュー依頼")
    #expect(listing.id == "github:https://github.com/o/r/pull/4")
}

@Test func anAssignedIssueLabelHasNoPullRequestOrReviewMark() {
    let listing = GitHubListing(
        number: 1, repository: "o/r", title: "t", url: "https://github.com/o/r/issues/1",
        isPullRequest: false, isReviewRequest: false)
    #expect(listing.label == "o/r #1")
}

@Test func aFailingGhSurfacesItsFirstLine() async {
    let runner = FakeGHRunner(output: "HTTP 401: Bad credentials\nrun gh auth login", terminationStatus: 1)
    await #expect(throws: GitHubListingError.self) {
        try await GitHubListingLoader.load(repo: nil, runner: runner, locator: presentGH)
    }
    do {
        _ = try await GitHubListingLoader.load(repo: nil, runner: runner, locator: presentGH)
    } catch let GitHubListingError.ghFailed(line) {
        #expect(line == "HTTP 401: Bad credentials")
    } catch {
        Issue.record("unexpected error \(error)")
    }
}

@Test func missingGhIsReported() async {
    let absent = GHLocator(isExecutable: { _ in false })
    await #expect(throws: GitHubListingError.self) {
        try await GitHubListingLoader.load(repo: nil, runner: FakeGHRunner(output: "[]"), locator: absent)
    }
}
