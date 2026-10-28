import Foundation

public struct RenderedCard: Sendable {
    public let bitmap: Bitmap1
    public let topPadding: Int
    public let headerFrame: PixelRect
    public let headerTextFrame: PixelRect
    public let qrFrame: PixelRect?
    public let titleFrame: PixelRect
    public let noteFrame: PixelRect?
}

public struct CardRenderer: Sendable {
    public let margin: Int

    public init(margin: Int = 8) {
        self.margin = margin
    }

    private static let topPadding = 12
    private static let bottomPadding = 12
    private static let qrGap = 8
    private static let minimumHeaderTextWidth = 96
    private static let emphasisSizes: [Double] = [36, 28, 22]

    private static let lineStyle = TextStyle(fontName: "HiraginoSans-W7", size: 20, lineSpacing: 1.25)
    private static let sublineStyle = TextStyle(fontName: "HiraginoSans-W7", size: 18, lineSpacing: 1.3)
    private static let labelStyle = TextStyle(fontName: "HiraginoSans-W8", size: 20, lineSpacing: 1.2)

    private struct Placement {
        let source: Bitmap1
        let columns: Range<Int>
        let x: Int
        let y: Int
    }

    public func render(_ card: Card) throws -> RenderedCard {
        let printable = Bitmap1.contentWidth - 2 * margin
        let right = Bitmap1.contentWidth - margin
        let top = CardRenderer.topPadding

        let qr = try (card.qr ?? card.url).map { try QRCode($0) }
        if let qr, qr.sideDots > printable {
            throw QRCode.Failure.tooWide(sideDots: qr.sideDots)
        }
        let qrFrame = qr.map { PixelRect(x: right - $0.sideDots, y: top, width: $0.sideDots, height: $0.sideDots) }
        let stacked = qrFrame.map { $0.minX - CardRenderer.qrGap - margin < CardRenderer.minimumHeaderTextWidth } ?? false
        let textWidth = qrFrame.map { stacked ? printable : $0.minX - CardRenderer.qrGap - margin } ?? printable
        let columnWidth = textWidth - textWidth % 2
        let columnMargin = (Bitmap1.contentWidth - columnWidth) / 2
        let textTop = stacked ? top + (qrFrame?.height ?? 0) + 8 : top

        var placements: [Placement] = []
        var textY = textTop
        for piece in headerPieces(card.header, columnMargin: columnMargin, columnWidth: columnWidth) {
            if textY > textTop { textY += 4 }
            placements.append(Placement(source: piece, columns: columnMargin..<(Bitmap1.contentWidth - columnMargin), x: margin, y: textY))
            textY += piece.height
        }
        let headerTextFrame = PixelRect(x: margin, y: textTop, width: columnWidth, height: textY - textTop)
        let headerBottom = stacked ? textY : max(textY, qrFrame?.maxY ?? 0)
        let headerFrame = PixelRect(x: margin, y: top, width: printable, height: headerBottom - top)

        let renderer = TextRenderer(margin: margin)
        var y = headerBottom + 10
        let title = renderer.render(card.title, style: .heading2)
        let titleFrame = PixelRect(x: margin, y: y, width: printable, height: title.height)
        placements.append(Placement(source: title, columns: 0..<Bitmap1.contentWidth, x: 0, y: y))
        y += title.height

        for (index, section) in card.sections.enumerated() {
            y += index == 0 ? 4 : 8
            if let label = section.label {
                let heading = labelBitmap(label, right: right)
                placements.append(Placement(source: heading, columns: 0..<Bitmap1.contentWidth, x: 0, y: y))
                y += heading.height + 2
            }
            if !section.text.isEmpty {
                let body = renderer.render(section.text, style: .body)
                placements.append(Placement(source: body, columns: 0..<Bitmap1.contentWidth, x: 0, y: y))
                y += body.height
            }
        }

        var noteFrame: PixelRect?
        if let note = card.note, !note.isEmpty {
            y += 8
            let small = renderer.render(note, style: .small)
            noteFrame = PixelRect(x: margin, y: y, width: printable, height: small.height)
            placements.append(Placement(source: small, columns: 0..<Bitmap1.contentWidth, x: 0, y: y))
            y += small.height
        }

        var bitmap = Bitmap1(height: y + CardRenderer.bottomPadding)
        for placement in placements {
            bitmap.draw(placement.source, columns: placement.columns, toX: placement.x, y: placement.y)
        }
        if let qr, let qrFrame {
            qr.draw(into: &bitmap, x: qrFrame.minX, y: qrFrame.minY)
        }
        return RenderedCard(
            bitmap: bitmap, topPadding: top, headerFrame: headerFrame, headerTextFrame: headerTextFrame,
            qrFrame: qrFrame, titleFrame: titleFrame, noteFrame: noteFrame
        )
    }

    private func headerPieces(_ header: Card.Header, columnMargin: Int, columnWidth: Int) -> [Bitmap1] {
        let renderer = TextRenderer(margin: columnMargin)
        var pieces: [Bitmap1] = []
        if !header.lines.isEmpty {
            pieces.append(renderer.render(header.lines.joined(separator: "\n"), style: CardRenderer.lineStyle))
        }
        if let emphasis = header.emphasis, !emphasis.isEmpty {
            pieces.append(renderer.render(emphasis, style: emphasisStyle(emphasis, width: columnWidth)))
        }
        if !header.sublines.isEmpty {
            pieces.append(renderer.render(header.sublines.joined(separator: "\n"), style: CardRenderer.sublineStyle))
        }
        return pieces
    }

    private func emphasisStyle(_ emphasis: String, width: Int) -> TextStyle {
        var style = TextStyle.heading2
        for size in CardRenderer.emphasisSizes {
            style = TextStyle(fontName: "HiraginoSans-W8", size: size, lineSpacing: 1.1)
            if LineBreaker(width: width).lines(emphasis, style: style).count == 1 { break }
        }
        return style
    }

    private func labelBitmap(_ label: String, right: Int) -> Bitmap1 {
        let text = TextRenderer(margin: margin).render(label, style: CardRenderer.labelStyle)
        guard let inkRight = text.blackPixels(inColumns: 0..<Bitmap1.contentWidth).map(\.x).max() else { return text }
        var heading = Bitmap1(height: text.height + 5)
        heading.draw(text, columns: 0..<Bitmap1.contentWidth, toX: 0, y: 0)
        heading.fill(PixelRect(x: margin, y: text.height + 2, width: min(inkRight + 1, right) - margin, height: 3))
        return heading
    }
}
