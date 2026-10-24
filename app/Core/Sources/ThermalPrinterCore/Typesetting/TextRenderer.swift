import CoreGraphics
import CoreText
import Foundation

public struct TextRenderer: Sendable {
    public let margin: Int

    public init(margin: Int = 8) {
        self.margin = margin
    }

    public var printableWidth: Int { Bitmap1.contentWidth - 2 * margin }

    public func render(_ text: String, style: TextStyle, indent: Int = 0) -> Bitmap1 {
        let lines = LineBreaker(width: printableWidth - indent).lines(text, style: style)
        let font = style.ctFont
        let rowHeight = style.lineHeight
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let halfLeading = (CGFloat(rowHeight) - (ascent + descent)) / 2
        let height = rowHeight * lines.count
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

        for (index, text) in lines.enumerated() {
            let line = LineBreaker.makeLine(text, font: font)
            let shift = CGFloat(LineBreaker.inkLeadingOverhang(of: line))
            let top = CGFloat(index * rowHeight)
            context.textPosition = CGPoint(x: CGFloat(margin + indent) + shift, y: CGFloat(height) - top - halfLeading - ascent)
            CTLineDraw(line, context)
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
