import Foundation

public enum Draft {
    private static var imageToken: Regex<(Substring, Substring)> { /\[Image #(\d+)\]/ }

    public static func token(_ number: Int) -> String {
        "[Image #\(number)]"
    }

    public static func markdown(_ text: String, images: [Int: URL]) -> String {
        text.replacing(imageToken) { match in
            guard let number = Int(match.1), let url = images[number] else { return String(match.0) }
            return "\n\n![](\(url.absoluteString))\n\n"
        }
    }

    public static func plainText(_ text: String) -> String {
        text.replacing(imageToken, with: "")
    }
}

public struct DraftDocument {
    public private(set) var text = ""
    public private(set) var digest: Card?
    private var images: [Int: URL] = [:]
    private var nextNumber = 1
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var canDigest: Bool {
        !Draft.plainText(text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var parts: [Part] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        if let digest { return [.card(digest)] }
        return [.markdown(Draft.markdown(text, images: images))]
    }

    public mutating func edit(_ newText: String) {
        text = newText
        digest = nil
    }

    public mutating func apply(_ card: Card, to source: String) {
        if source == text { digest = card }
    }

    public mutating func addImage(_ data: Data) throws -> String {
        let url = directory.appending(path: "image-\(nextNumber).png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url)
        images[nextNumber] = url
        defer { nextNumber += 1 }
        return Draft.token(nextNumber)
    }

    public mutating func clear() {
        try? FileManager.default.removeItem(at: directory)
        self = DraftDocument(directory: directory)
    }
}
