import Foundation

public protocol URLHandler: Sendable {
    func handles(_ url: URL) -> Bool
    func card(for url: URL) async throws -> Card
}

public enum URLHandlerError: Error, Equatable {
    case unsupported(URL)
}

public struct URLHandlerRegistry: Sendable {
    private let handlers: [any URLHandler]

    public init(handlers: [any URLHandler]) {
        self.handlers = handlers
    }

    public static func standard(
        runner: any ProcessRunner,
        summarizer: any Summarizer,
        locator: GHLocator = GHLocator(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> URLHandlerRegistry {
        URLHandlerRegistry(handlers: [
            GitHubHandler(runner: runner, summarizer: summarizer, locator: locator, now: now),
            SlackURLHandler(),
            WebPageHandler(runner: runner, summarizer: summarizer),
        ])
    }

    public func card(for url: URL) async -> Card {
        guard let handler = handlers.first(where: { $0.handles(url) }) else {
            return UnknownURLHandler.make(for: url)
        }
        do {
            return try await handler.card(for: url)
        } catch {
            return UnknownURLHandler.make(for: url, note: "取得できません（\(error.localizedDescription)）")
        }
    }
}
