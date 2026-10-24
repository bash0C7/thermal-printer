import Foundation

public struct UnknownURLHandler: URLHandler {
    public init() {}

    public func handles(_ url: URL) -> Bool { true }

    public func card(for url: URL) async throws -> Card {
        Self.make(for: url)
    }

    public static func make(for url: URL, note: String? = nil) -> Card {
        let origin = url.host(percentEncoded: false) ?? url.scheme ?? ""
        return Card(
            kind: .url, url: url.absoluteString,
            header: Card.Header(lines: [origin]),
            title: url.absoluteString, sections: [], note: note
        )
    }
}
