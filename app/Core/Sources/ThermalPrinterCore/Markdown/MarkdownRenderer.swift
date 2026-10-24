import CoreText
import Foundation
import Markdown

public struct MarkdownRenderer: Sendable {
    public let margin: Int
    public let baseURL: URL?

    public init(margin: Int = 8, baseURL: URL? = nil) {
        self.margin = margin
        self.baseURL = baseURL
    }

    public func render(_ markdown: String) -> Bitmap1 {
        BlockLayout.render(layout(markdown), margin: margin)
    }

    public static func plainText(_ markdown: String) -> String {
        var builder = MarkdownBlockBuilder(baseURL: nil, embedsImages: false)
        builder.build(markdown)
        return builder.blocks.compactMap { block -> String? in
            guard case .text(let runs) = block.content else { return nil }
            var prefix = ""
            if case .text(let markerRuns) = block.marker {
                prefix = markerRuns.map(\.text).joined() + " "
            }
            return prefix + runs.map(\.text).joined()
        }.joined(separator: "\n")
    }

    func layout(_ markdown: String) -> [LayoutBlock] {
        var builder = MarkdownBlockBuilder(baseURL: baseURL, embedsImages: true)
        builder.build(markdown)
        return builder.blocks
    }

    func wrappedLines(_ markdown: String) -> [[String]] {
        layout(markdown).compactMap { block in
            guard case .text = block.content else { return nil }
            return BlockLayout.lines(of: block, margin: margin).map { $0.map(\.text).joined() }
        }
    }
}

private struct MarkdownContext {
    var inset = 0
    var bars: [Int] = []
    var listDepth = 0
    var pendingMarker: (marker: LayoutMarker, x: Int)?
}

private let softBreakSentinel = "\u{0}"

private extension TextStyle {
    var bold: TextStyle {
        guard fontName.hasPrefix("HiraginoSans") else { return self }
        var copy = self
        copy.fontName = TextStyle.strong.fontName
        return copy
    }

    var inlineCode: TextStyle {
        TextStyle(
            fontName: TextStyle.monospaced.fontName, size: max(14, size - 2),
            isOblique: isOblique, lineSpacing: TextStyle.monospaced.lineSpacing
        )
    }
}

struct MarkdownBlockBuilder {
    private(set) var blocks: [LayoutBlock] = []
    private let baseURL: URL?
    private let embedsImages: Bool

    init(baseURL: URL?, embedsImages: Bool) {
        self.baseURL = baseURL
        self.embedsImages = embedsImages
    }

    mutating func build(_ markdown: String) {
        let document = Document(parsing: markdown.replacingOccurrences(of: "\r\n", with: "\n"))
        var context = MarkdownContext()
        visitBlocks(document.children, context: &context)
    }

    private mutating func visitBlocks(_ children: some Sequence<Markup>, context: inout MarkdownContext) {
        for child in children {
            visitBlock(child, context: &context)
        }
    }

    private mutating func visitBlock(_ markup: Markup, context: inout MarkdownContext) {
        switch markup {
        case let heading as Heading:
            visitHeading(heading, context: &context)
        case let paragraph as Paragraph:
            visitParagraph(paragraph, context: &context)
        case let quote as BlockQuote:
            var inner = context
            let origin = min(context.inset, BlockLayout.maxInset)
            inner.bars.append(origin)
            inner.inset = origin + BlockLayout.barWidth + BlockLayout.barGap
            visitBlocks(quote.children, context: &inner)
            context.pendingMarker = inner.pendingMarker
        case let list as UnorderedList:
            visitList(items: Array(list.listItems), start: nil, context: &context)
        case let list as OrderedList:
            visitList(items: Array(list.listItems), start: list.startIndex, context: &context)
        case let code as CodeBlock:
            let text = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            append(.text([StyledRun(text, style: .monospaced)]), context: &context, before: 4, after: 8)
        case is ThematicBreak:
            append(.rule, context: &context, before: 8, after: 8)
        case let table as Markdown.Table:
            visitTable(table, context: &context)
        case let html as HTMLBlock:
            let text = html.rawHTML.hasSuffix("\n") ? String(html.rawHTML.dropLast()) : html.rawHTML
            append(.text([StyledRun(text, style: .monospaced)]), context: &context, before: 4, after: 8)
        default:
            let runs = [StyledRun(markup.format(), style: .body)]
            append(.text(runs), context: &context, before: 0, after: 8)
        }
    }

    private mutating func visitHeading(_ heading: Heading, context: inout MarkdownContext) {
        let runs = inlineRuns(heading.children, style: headingStyle(level: heading.level))
        switch heading.level {
        case 1:
            append(.text(runs), context: &context, before: 4, after: 8)
        case 2:
            append(.text(runs), context: &context, before: 14, after: 8, underlined: true)
        default:
            append(.text(runs), context: &context, before: 10, after: 4)
        }
    }

    private func headingStyle(level: Int) -> TextStyle {
        switch level {
        case 1: .heading1
        case 2: .heading2
        default: .heading3
        }
    }

    private mutating func visitParagraph(_ paragraph: Paragraph, context: inout MarkdownContext) {
        if paragraph.childCount == 1, let image = paragraph.child(at: 0) as? Markdown.Image,
            let source = image.source, let bitmap = loadImage(source)
        {
            append(.image(bitmap), context: &context, before: 4, after: 8)
            return
        }
        let runs = inlineRuns(paragraph.children, style: .body)
        append(.text(runs), context: &context, before: 0, after: context.listDepth > 0 ? 3 : 8)
    }

    private mutating func visitList(items: [ListItem], start: UInt?, context: inout MarkdownContext) {
        let listInset = min(context.inset, BlockLayout.maxInset)
        let markers = items.enumerated().map { index, item -> LayoutMarker in
            if let checkbox = item.checkbox {
                return .text([StyledRun(checkbox == .checked ? "☑" : "☐", style: .body)])
            }
            if let start {
                return .text([StyledRun("\(Int(start) + index).", style: .body)])
            }
            return .bullet
        }
        let markerWidth = markers.map(width(of:)).max() ?? BlockLayout.bulletWidth
        let firstBlock = blocks.count
        for (item, marker) in zip(items, markers) {
            var inner = context
            inner.inset = listInset + markerWidth
            inner.listDepth = context.listDepth + 1
            inner.pendingMarker = (marker, listInset)
            visitBlocks(item.children, context: &inner)
        }
        context.pendingMarker = nil
        if context.listDepth == 0, blocks.count > firstBlock {
            blocks[blocks.count - 1].after = max(blocks[blocks.count - 1].after, 8)
        }
    }

    private func width(of marker: LayoutMarker) -> Int {
        guard case .text(let runs) = marker else { return BlockLayout.bulletWidth }
        var total = 0.0
        for run in runs {
            total += CTLineGetTypographicBounds(LineBreaker.makeLine(run.text, font: run.style.ctFont), nil, nil, nil)
        }
        return max(BlockLayout.bulletWidth, Int(total.rounded(.up)) + 6)
    }

    private mutating func visitTable(_ table: Markdown.Table, context: inout MarkdownContext) {
        var rows: [(cells: [Markup], style: TextStyle)] = []
        for part in table.children {
            if part is Markdown.Table.Head {
                rows.append((Array(part.children), .strong))
            } else {
                for row in part.children {
                    rows.append((Array(row.children), .body))
                }
            }
        }
        for (index, row) in rows.enumerated() {
            var runs: [StyledRun] = []
            for (cellIndex, cell) in row.cells.enumerated() {
                if cellIndex > 0 { runs.append(StyledRun(" | ", style: row.style)) }
                runs.append(contentsOf: inlineRuns(cell.children, style: row.style))
            }
            append(.text(merged(runs)), context: &context, before: 0, after: index == rows.count - 1 ? 8 : 2)
        }
    }

    private mutating func append(
        _ content: LayoutContent, context: inout MarkdownContext, before: Int, after: Int, underlined: Bool = false
    ) {
        var block = LayoutBlock(content: content, textInset: context.inset)
        block.bars = context.bars
        block.before = before
        block.after = after
        block.underlined = underlined
        if case .text = content, let pending = context.pendingMarker {
            block.marker = pending.marker
            block.markerX = pending.x
            context.pendingMarker = nil
        }
        blocks.append(block)
    }

    private func loadImage(_ source: String) -> Bitmap1? {
        guard embedsImages else { return nil }
        let decoded = source.removingPercentEncoding ?? source
        let url: URL
        if source.hasPrefix("file://"), let fileURL = URL(string: source) {
            url = fileURL
        } else if decoded.hasPrefix("/") {
            url = URL(fileURLWithPath: decoded)
        } else if !source.contains("://"), let baseURL {
            url = baseURL.appending(path: decoded)
        } else {
            return nil
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return try? ImageLoader.bitmap(fromFile: url)
    }

    private func inlineRuns(_ children: some Sequence<Markup>, style: TextStyle) -> [StyledRun] {
        var runs: [StyledRun] = []
        collect(children, style: style, into: &runs)
        return merged(resolvedSoftBreaks(runs))
    }

    private func collect(_ children: some Sequence<Markup>, style: TextStyle, into runs: inout [StyledRun]) {
        for child in children {
            switch child {
            case let text as Markdown.Text:
                runs.append(StyledRun(text.string, style: style))
            case is Strong:
                collect(child.children, style: style.bold, into: &runs)
            case is Emphasis:
                collect(child.children, style: style.oblique, into: &runs)
            case let code as InlineCode:
                runs.append(StyledRun(code.code, style: style.inlineCode))
            case is SoftBreak:
                runs.append(StyledRun(softBreakSentinel, style: style))
            case is LineBreak:
                runs.append(StyledRun("\n", style: style))
            case let html as InlineHTML:
                runs.append(StyledRun(html.rawHTML, style: style))
            default:
                if child.childCount > 0 {
                    collect(child.children, style: style, into: &runs)
                } else {
                    runs.append(StyledRun(child.format(), style: style))
                }
            }
        }
    }

    private func resolvedSoftBreaks(_ runs: [StyledRun]) -> [StyledRun] {
        var result: [StyledRun] = []
        for (index, run) in runs.enumerated() {
            guard run.text == softBreakSentinel else {
                result.append(run)
                continue
            }
            let before = result.last?.text.last
            let after = runs[(index + 1)...].first { $0.text != softBreakSentinel }?.text.first
            guard let before, let after, before != "\n", after != "\n", before != " ", after != " " else { continue }
            if !(isWide(before) && isWide(after)) {
                result.append(StyledRun(" ", style: run.style))
            }
        }
        return result
    }

    private func isWide(_ character: Character) -> Bool {
        (character.unicodeScalars.first?.value ?? 0) >= 0x2E80
    }

    private func merged(_ runs: [StyledRun]) -> [StyledRun] {
        var result: [StyledRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = result.last, last.style == run.style {
                result[result.count - 1].text += run.text
            } else {
                result.append(run)
            }
        }
        return result
    }
}
