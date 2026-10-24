import Foundation

public struct StripFailure: Equatable, Sendable {
    public let partIndex: Int
    public let message: String
}

public enum CardJSONError: Error, Equatable {
    case render(String)
}

public struct ComposedStrip: Sendable {
    public let bitmap: Bitmap1
    public let partRanges: [Range<Int>]
    public let cutLineRows: [Int]
    public let failures: [StripFailure]
}

public struct StripComposer: Sendable {
    public static let defaultFeedRows = 48
    public static let defaultTopRows = 0
    public static let defaultGapRows = 16

    private static let dashLength = 8

    public let feedRows: Int
    public let topRows: Int
    public let margin: Int
    public let gapRows: Int

    public init(
        feedRows: Int = StripComposer.defaultFeedRows, topRows: Int = StripComposer.defaultTopRows,
        margin: Int = 8, gapRows: Int = StripComposer.defaultGapRows
    ) {
        self.feedRows = feedRows
        self.topRows = topRows
        self.margin = margin
        self.gapRows = gapRows
    }

    public func compose(_ parts: [Part]) -> ComposedStrip {
        guard !parts.isEmpty else {
            return ComposedStrip(bitmap: Bitmap1(height: 0), partRanges: [], cutLineRows: [], failures: [])
        }

        var failures: [StripFailure] = []
        var rendered: [Bitmap1] = []
        for (index, part) in parts.enumerated() {
            do {
                rendered.append(try render(part))
            } catch {
                failures.append(StripFailure(partIndex: index, message: Self.message(for: part, error: error)))
                rendered.append(placeholder(for: part))
            }
        }

        let separator = gapRows + 1 + gapRows
        let contentHeight = rendered.map(\.height).reduce(0, +) + separator * (rendered.count - 1)
        var bitmap = Bitmap1(height: topRows + contentHeight + feedRows)
        var ranges: [Range<Int>] = []
        var cutLines: [Int] = []
        var y = topRows
        for (index, piece) in rendered.enumerated() {
            if index > 0 {
                let line = y + gapRows
                drawCutLine(into: &bitmap, row: line)
                cutLines.append(line)
                y += separator
            }
            bitmap.draw(piece, columns: 0..<Bitmap1.contentWidth, toX: Bitmap1.contentLeft, y: y)
            ranges.append(y..<(y + piece.height))
            y += piece.height
        }
        return ComposedStrip(bitmap: bitmap, partRanges: ranges, cutLineRows: cutLines, failures: failures)
    }

    public func bitmap(cardJSON: Data) throws -> Bitmap1 {
        let card = try JSONDecoder().decode(Card.self, from: cardJSON)
        let strip = compose([.card(card)])
        if let failure = strip.failures.first { throw CardJSONError.render(failure.message) }
        return strip.bitmap
    }

    private func render(_ part: Part) throws -> Bitmap1 {
        switch part {
        case .text(let text, let size):
            return TextRenderer(margin: margin).render(text, style: size.style)
        case .markdown(let text, let baseURL, let asPlainText):
            if asPlainText {
                return TextRenderer(margin: margin).render(text, style: .body)
            }
            return MarkdownRenderer(margin: margin, baseURL: baseURL).render(text)
        case .image(let data, let settings):
            return try ImageLoader.bitmap(from: data, adjust: settings.adjust, rotation: settings.rotation)
        case .card(let card):
            return try CardRenderer(margin: margin).render(card).bitmap
        }
    }

    private func placeholder(for part: Part) -> Bitmap1 {
        let label: String
        switch part {
        case .image: label = "（画像を読み込めません）"
        case .card: label = "（カードを描画できません）"
        case .text, .markdown: label = "（部品を描画できません）"
        }
        return TextRenderer(margin: margin).render(label, style: .small)
    }

    private static func message(for part: Part, error: Error) -> String {
        switch part {
        case .image: return "画像を読み込めません: \(error)"
        case .card: return "カードを描画できません: \(error)"
        case .text, .markdown: return "部品を描画できません: \(error)"
        }
    }

    private func drawCutLine(into bitmap: inout Bitmap1, row: Int) {
        for x in margin..<(Bitmap1.contentWidth - margin) where ((x - margin) / Self.dashLength) % 2 == 0 {
            bitmap.set(x: Bitmap1.contentLeft + x, y: row)
        }
    }
}
