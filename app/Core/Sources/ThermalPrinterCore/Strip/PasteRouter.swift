import Foundation

public struct PasteboardContent: Equatable, Sendable {
    public var imageData: Data?
    public var fileURLs: [URL]
    public var text: String?

    public init(imageData: Data? = nil, fileURLs: [URL] = [], text: String? = nil) {
        self.imageData = imageData
        self.fileURLs = fileURLs
        self.text = text
    }
}

public enum PasteItem: Equatable, Sendable {
    case part(Part)
    case cardURL(String)
    case rejected(String)

    public static func parts(of items: [PasteItem]) -> [Part] {
        items.compactMap { item in
            guard case .part(let part) = item else { return nil }
            return part
        }
    }
}

public enum PasteRouter {
    public enum Kind: Equatable, Sendable {
        case image
        case card
        case markdown
        case text
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
    ]
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let textExtensions: Set<String> = ["txt"]

    public static func route(text: String) -> Kind {
        singleURL(in: text) == nil ? .markdown : .card
    }

    public static func route(fileURL: URL) -> Kind? {
        let ext = fileURL.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if markdownExtensions.contains(ext) { return .markdown }
        if textExtensions.contains(ext) { return .text }
        return nil
    }

    public static func items(
        from content: PasteboardContent, readFile: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) -> [PasteItem] {
        if !content.fileURLs.isEmpty {
            return content.fileURLs.map { item(forFile: $0, readFile: readFile) }
        }
        if let imageData = content.imageData {
            return [.part(.image(imageData))]
        }
        guard let text = content.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        if let url = singleURL(in: text) {
            return [.cardURL(url)]
        }
        return [.part(.markdown(text))]
    }

    private static func item(forFile url: URL, readFile: (URL) throws -> Data) -> PasteItem {
        let name = url.lastPathComponent
        guard let kind = route(fileURL: url) else {
            return .rejected("\(name): 対応していない形式です")
        }
        let data: Data
        do {
            data = try readFile(url)
        } catch {
            return .rejected("\(name): \(error.localizedDescription)")
        }
        if kind == .image {
            return .part(.image(data))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .rejected("\(name): UTF-8 として読めません")
        }
        if kind == .markdown {
            return .part(.markdown(text, baseURL: url.deletingLastPathComponent()))
        }
        return .part(.text(text))
    }

    private static func singleURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
