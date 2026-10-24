import CoreText
import Foundation

public struct LineBreaker: Sendable {
    public let width: Double

    public init(width: Double) {
        self.width = width
    }

    public init(width: Int) {
        self.width = Double(width)
    }

    public func lines(_ text: String, style: TextStyle) -> [String] {
        let font = style.ctFont
        var result: [String] = []
        for paragraph in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            result.append(contentsOf: wrap(String(paragraph), font: font))
        }
        return result
    }

    private func wrap(_ paragraph: String, font: CTFont) -> [String] {
        let source = paragraph as NSString
        guard source.length > 0 else { return [""] }
        let attributed = NSAttributedString(
            string: paragraph,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return ranges(of: attributed).map { source.substring(with: $0) }
    }

    func ranges(of attributed: NSAttributedString) -> [NSRange] {
        let source = attributed.string as NSString
        let length = source.length
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var result: [NSRange] = []
        var start = 0
        while start < length {
            let fitted = fittingEnd(typesetter, attributed: attributed, start: start, length: length, source: source)
            let end = kinsokuAdjusted(fitted, start: start, length: length, source: source)
            result.append(NSRange(location: start, length: end - start))
            start = end
        }
        return result
    }

    static func makeLine(_ text: String, font: CTFont) -> CTLine {
        let attributed = NSAttributedString(
            string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        return CTLineCreateWithAttributedString(attributed)
    }

    static func makeLine(_ attributed: NSAttributedString) -> CTLine {
        CTLineCreateWithAttributedString(attributed)
    }

    static func inkLeadingOverhang(of line: CTLine) -> Double {
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : max(0, -Double(bounds.minX))
    }

    static func inkWidth(of line: CTLine) -> Double {
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : Double(bounds.maxX) + max(0, -Double(bounds.minX))
    }

    private func fittingEnd(_ typesetter: CTTypesetter, attributed: NSAttributedString, start: Int, length: Int, source: NSString) -> Int {
        var limit = width
        var end = min(start + CTTypesetterSuggestLineBreak(typesetter, start, limit), length)
        while end - start > 1 {
            let candidate = attributed.attributedSubstring(from: NSRange(location: start, length: end - start))
            let overshoot = LineBreaker.inkWidth(of: LineBreaker.makeLine(candidate)) - width
            if overshoot <= 0 { break }
            limit -= max(1, overshoot)
            let suggested = min(start + CTTypesetterSuggestLineBreak(typesetter, start, limit), length)
            let previous = composedStart(before: end, source: source)
            let next = suggested < end ? suggested : previous
            if next <= start { break }
            end = next
        }
        return end
    }

    private func kinsokuAdjusted(_ candidate: Int, start: Int, length: Int, source: NSString) -> Int {
        var end = candidate
        while end < length && end > start {
            let next = character(at: end, source: source)
            let last = lastNonSpace(before: end, start: start, source: source)
            let violates = Kinsoku.lineStartForbidden.contains(next)
                || (last.map { Kinsoku.lineEndForbidden.contains($0) } ?? false)
            if !violates { return end }
            end = composedStart(before: end, source: source)
        }
        return end > start ? end : candidate
    }

    private func character(at index: Int, source: NSString) -> Character {
        let range = source.rangeOfComposedCharacterSequence(at: index)
        return source.substring(with: range).first ?? " "
    }

    private func composedStart(before index: Int, source: NSString) -> Int {
        source.rangeOfComposedCharacterSequence(at: index - 1).location
    }

    private func lastNonSpace(before end: Int, start: Int, source: NSString) -> Character? {
        var index = end
        while index > start {
            index = composedStart(before: index, source: source)
            let candidate = character(at: index, source: source)
            if candidate != " " { return candidate }
        }
        return nil
    }
}
