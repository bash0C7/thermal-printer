import Foundation

public struct PhysicalScale: Equatable, Sendable {
    public static let fallback = PhysicalScale(pixelsWide: 72, millimetersWide: 25.4, backingScale: 1)

    public let pointsPerMillimeter: Double

    public init(pixelsWide: Double, millimetersWide: Double, backingScale: Double) {
        precondition(pixelsWide > 0 && millimetersWide > 0 && backingScale > 0, "display size must be positive")
        self.pointsPerMillimeter = pixelsWide / backingScale / millimetersWide
    }

    public func points(forMillimeters millimeters: Double) -> Double {
        millimeters * pointsPerMillimeter
    }

    public func points(forDots dots: Int) -> Double {
        points(forMillimeters: Double(dots) / Bitmap1.dotsPerMillimeter)
    }

    public static func measured(pixelsWide: Double, millimetersWide: Double, backingScale: Double) -> PhysicalScale {
        guard pixelsWide > 0, millimetersWide > 0, backingScale > 0 else { return .fallback }
        return PhysicalScale(pixelsWide: pixelsWide, millimetersWide: millimetersWide, backingScale: backingScale)
    }
}
