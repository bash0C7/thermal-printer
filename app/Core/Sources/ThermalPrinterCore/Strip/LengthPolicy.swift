import Foundation

public struct LengthPolicy: Equatable, Sendable {
    public static let defaultThresholdCentimeters = 30.0

    public var thresholdCentimeters: Double

    public init(thresholdCentimeters: Double = LengthPolicy.defaultThresholdCentimeters) {
        self.thresholdCentimeters = thresholdCentimeters
    }

    public static func millimeters(rows: Int) -> Double {
        Double(rows) / Bitmap1.dotsPerMillimeter
    }

    public static func centimeters(rows: Int) -> Double {
        millimeters(rows: rows) / 10
    }

    public static func lengthText(rows: Int) -> String {
        String(format: "%.1f cm", centimeters(rows: rows))
    }

    public func isTooLong(rows: Int) -> Bool {
        LengthPolicy.centimeters(rows: rows) > thresholdCentimeters
    }

    public func isTooLong(_ bitmap: Bitmap1) -> Bool {
        isTooLong(rows: bitmap.height)
    }

    public func warningText(rows: Int) -> String? {
        guard isTooLong(rows: rows) else { return nil }
        let threshold = String(format: "%g", thresholdCentimeters)
        return "長さ \(LengthPolicy.lengthText(rows: rows))。\(threshold) cm を超えています"
    }
}
