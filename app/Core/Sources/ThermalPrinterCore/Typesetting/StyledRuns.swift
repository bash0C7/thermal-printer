import CoreGraphics
import CoreText
import Foundation

public struct StyledRun: Hashable, Sendable {
    public var text: String
    public var style: TextStyle

    public init(_ text: String, style: TextStyle) {
        self.text = text
        self.style = style
    }
}

private struct StyledSpan {
    let range: NSRange
    let style: TextStyle
}

private func attributedString(_ runs: [StyledRun]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for run in runs {
        result.append(NSAttributedString(
            string: run.text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): run.style.ctFont]
        ))
    }
    return result
}

private func spans(of runs: [StyledRun]) -> [StyledSpan] {
    var result: [StyledSpan] = []
    var location = 0
    for run in runs {
        let length = (run.text as NSString).length
        result.append(StyledSpan(range: NSRange(location: location, length: length), style: run.style))
        location += length
    }
    return result
}

extension LineBreaker {
    public func lines(runs: [StyledRun]) -> [[StyledRun]] {
        guard let lastStyle = runs.last?.style else { return [] }
        let attributed = attributedString(runs)
        let source = attributed.string as NSString
        let runSpans = spans(of: runs)
        var result: [[StyledRun]] = []
        var start = 0
        while start <= source.length {
            var end = start
            while end < source.length && source.character(at: end) != 0x0A { end += 1 }
            if end == start {
                let style = runSpans.first { NSLocationInRange(start, $0.range) }?.style ?? lastStyle
                result.append([StyledRun("", style: style)])
            } else {
                let paragraph = NSRange(location: start, length: end - start)
                for local in ranges(of: attributed.attributedSubstring(from: paragraph)) {
                    let global = NSRange(location: paragraph.location + local.location, length: local.length)
                    result.append(styledRuns(in: global, spans: runSpans, source: source))
                }
            }
            start = end + 1
        }
        return result
    }

    private func styledRuns(in range: NSRange, spans: [StyledSpan], source: NSString) -> [StyledRun] {
        var runs: [StyledRun] = []
        for span in spans {
            let shared = NSIntersectionRange(range, span.range)
            if shared.length > 0 {
                runs.append(StyledRun(source.substring(with: shared), style: span.style))
            }
        }
        return runs
    }
}

extension TextRenderer {
    public func render(runs: [StyledRun], indent: Int = 0) -> Bitmap1 {
        render(lines: LineBreaker(width: printableWidth - indent).lines(runs: runs), indent: indent)
    }

    func render(lines: [[StyledRun]], indent: Int) -> Bitmap1 {
        let metrics = lines.map { StyledLineMetrics(runs: $0) }
        let height = metrics.reduce(0) { $0 + $1.rowHeight }
        let width = Bitmap1.contentWidth

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Bitmap1(height: height)
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)
        context.setShouldAntialias(true)

        var top = 0
        for (runs, metric) in zip(lines, metrics) {
            let line = LineBreaker.makeLine(attributedString(runs))
            let shift = CGFloat(LineBreaker.inkLeadingOverhang(of: line))
            let halfLeading = (CGFloat(metric.rowHeight) - (metric.ascent + metric.descent)) / 2
            context.textPosition = CGPoint(
                x: CGFloat(margin + indent) + shift,
                y: CGFloat(height) - CGFloat(top) - halfLeading - metric.ascent
            )
            CTLineDraw(line, context)
            top += metric.rowHeight
        }

        var bitmap = Bitmap1(height: height)
        guard let data = context.data else { return bitmap }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                bitmap.set(x: x, y: y)
            }
        }
        return bitmap
    }
}

struct StyledLineMetrics {
    let rowHeight: Int
    let ascent: CGFloat
    let descent: CGFloat

    init(runs: [StyledRun]) {
        var rowHeight = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        for run in runs {
            rowHeight = max(rowHeight, run.style.lineHeight)
            ascent = max(ascent, CTFontGetAscent(run.style.ctFont))
            descent = max(descent, CTFontGetDescent(run.style.ctFont))
        }
        self.rowHeight = rowHeight
        self.ascent = ascent
        self.descent = descent
    }
}
