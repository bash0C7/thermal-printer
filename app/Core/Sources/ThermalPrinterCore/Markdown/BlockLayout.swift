import Foundation

enum LayoutMarker {
    case none
    case bullet
    case text([StyledRun])
}

enum LayoutContent {
    case text([StyledRun])
    case rule
    case image(Bitmap1)
}

struct LayoutBlock {
    var content: LayoutContent
    var textInset: Int
    var bars: [Int] = []
    var marker: LayoutMarker = .none
    var markerX = 0
    var underlined = false
    var before = 0
    var after = 0
}

private struct MarkdownCanvas {
    var bitmap: Bitmap1

    init(height: Int) {
        bitmap = Bitmap1(height: height)
    }

    mutating func blit(_ source: Bitmap1, atY offset: Int, columns: Range<Int> = 0..<Bitmap1.contentWidth) {
        for y in 0..<source.height where offset + y >= 0 && offset + y < bitmap.height {
            for (index, byte) in source.rowBytes(y).enumerated() where byte != 0 {
                for bit in 0..<8 where byte & (0x80 >> UInt8(bit)) != 0 {
                    let x = index * 8 + bit
                    if columns.contains(x) { bitmap.set(x: x, y: offset + y) }
                }
            }
        }
    }

    mutating func fill(x: Int, y: Int, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        for row in max(y, 0)..<min(y + height, bitmap.height) {
            for column in max(x, 0)..<min(x + width, Bitmap1.contentWidth) {
                bitmap.set(x: column, y: row)
            }
        }
    }

    mutating func disc(centerX: Int, centerY: Int, radius: Double) {
        let reach = Int(radius.rounded(.up))
        for dy in -reach...reach {
            for dx in -reach...reach where Double(dx * dx + dy * dy) <= radius * radius {
                fill(x: centerX + dx, y: centerY + dy, width: 1, height: 1)
            }
        }
    }
}

enum BlockLayout {
    static let barWidth = 5
    static let barGap = 10
    static let bulletWidth = 16
    static let bulletRadius = 4.3
    static let maxInset = 184
    static let ruleThickness = 4
    static let underlineGap = 3
    static let underlineThickness = 3

    static func lines(of block: LayoutBlock, margin: Int) -> [[StyledRun]] {
        guard case .text(let runs) = block.content else { return [] }
        return LineBreaker(width: Bitmap1.contentWidth - 2 * margin - block.textInset).lines(runs: runs)
    }

    static func render(_ blocks: [LayoutBlock], margin: Int) -> Bitmap1 {
        let bodies = blocks.map { body(of: $0, margin: margin) }
        var tops: [Int] = []
        var gaps: [Int] = []
        var y = 0
        for (index, block) in blocks.enumerated() {
            let gap = index == 0 ? 0 : max(blocks[index - 1].after, block.before)
            gaps.append(gap)
            tops.append(y + gap)
            y += gap + bodies[index].height
        }

        var canvas = MarkdownCanvas(height: y)
        for (index, block) in blocks.enumerated() {
            let top = tops[index]
            canvas.blit(bodies[index], atY: top)
            let previousBars = index == 0 ? [] : blocks[index - 1].bars
            for bar in block.bars {
                let from = previousBars.contains(bar) ? top - gaps[index] : top
                canvas.fill(x: margin + bar, y: from, width: barWidth, height: top + bodies[index].height - from)
            }
        }
        return canvas.bitmap
    }

    private static func body(of block: LayoutBlock, margin: Int) -> Bitmap1 {
        switch block.content {
        case .rule:
            var canvas = MarkdownCanvas(height: ruleThickness)
            canvas.fill(x: margin + block.textInset, y: 0, width: Bitmap1.contentWidth - 2 * margin - block.textInset, height: ruleThickness)
            return canvas.bitmap
        case .image(let image):
            var canvas = MarkdownCanvas(height: image.height)
            canvas.blit(image, atY: 0, columns: margin..<(Bitmap1.contentWidth - margin))
            return canvas.bitmap
        case .text:
            return textBody(of: block, margin: margin)
        }
    }

    private static func textBody(of block: LayoutBlock, margin: Int) -> Bitmap1 {
        let renderer = TextRenderer(margin: margin)
        let lines = self.lines(of: block, margin: margin)
        let text = renderer.render(lines: lines, indent: block.textInset)
        let firstRow = lines.first.map { StyledLineMetrics(runs: $0).rowHeight } ?? 0

        var markerBitmap: Bitmap1?
        if case .text(let runs) = block.marker {
            markerBitmap = renderer.render(runs: runs, indent: block.markerX)
        }
        let underline = block.underlined ? underlineGap + underlineThickness : 0
        var canvas = MarkdownCanvas(height: max(text.height + underline, markerBitmap?.height ?? 0))
        canvas.blit(text, atY: 0)
        if let markerBitmap {
            canvas.blit(markerBitmap, atY: 0)
        }
        if case .bullet = block.marker {
            canvas.disc(centerX: margin + block.markerX + Int(bulletRadius.rounded(.up)), centerY: firstRow / 2 + 1, radius: bulletRadius)
        }
        if block.underlined {
            canvas.fill(
                x: margin + block.textInset, y: text.height + underlineGap,
                width: Bitmap1.contentWidth - 2 * margin - block.textInset, height: underlineThickness
            )
        }
        return canvas.bitmap
    }
}
