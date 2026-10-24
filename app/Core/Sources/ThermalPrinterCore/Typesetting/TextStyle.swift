import CoreGraphics
import CoreText
import Foundation

private final class FontCache: @unchecked Sendable {
    static let shared = FontCache()

    private let lock = NSLock()
    private var fonts: [TextStyle: CTFont] = [:]

    func font(for style: TextStyle) -> CTFont {
        lock.lock()
        defer { lock.unlock() }
        if let cached = fonts[style] { return cached }
        let created = style.makeFont()
        fonts[style] = created
        return created
    }
}

public struct TextStyle: Hashable, Sendable {
    public var fontName: String
    public var size: Double
    public var isOblique: Bool
    public var lineSpacing: Double

    public init(fontName: String, size: Double, isOblique: Bool = false, lineSpacing: Double = 1.35) {
        self.fontName = fontName
        self.size = size
        self.isOblique = isOblique
        self.lineSpacing = lineSpacing
    }

    public static let obliqueShear = tan(14.0 * Double.pi / 180.0)

    public static let small = TextStyle(fontName: "HiraginoSans-W6", size: 18)
    public static let body = TextStyle(fontName: "HiraginoSans-W7", size: 22)
    public static let large = TextStyle(fontName: "HiraginoSans-W7", size: 28)
    public static let strong = TextStyle(fontName: "HiraginoSans-W8", size: 22)
    public static let heading1 = TextStyle(fontName: "HiraginoSans-W8", size: 40, lineSpacing: 1.25)
    public static let heading2 = TextStyle(fontName: "HiraginoSans-W8", size: 32, lineSpacing: 1.3)
    public static let heading3 = TextStyle(fontName: "HiraginoSans-W7", size: 26)
    public static let monospaced = TextStyle(fontName: "Menlo-Bold", size: 20, lineSpacing: 1.3)

    public var oblique: TextStyle {
        var copy = self
        copy.isOblique = true
        return copy
    }

    public var ctFont: CTFont {
        FontCache.shared.font(for: self)
    }

    fileprivate func makeFont() -> CTFont {
        var shear = CGAffineTransform(a: 1, b: 0, c: isOblique ? TextStyle.obliqueShear : 0, d: 1, tx: 0, ty: 0)
        return CTFontCreateWithName(fontName as CFString, CGFloat(size), &shear)
    }

    public var resolvedPostScriptName: String {
        CTFontCopyPostScriptName(ctFont) as String
    }

    public var lineHeight: Int {
        let font = ctFont
        let natural = CTFontGetAscent(font) + CTFontGetDescent(font)
        return Int(max(CGFloat(size * lineSpacing), natural).rounded(.up))
    }
}
