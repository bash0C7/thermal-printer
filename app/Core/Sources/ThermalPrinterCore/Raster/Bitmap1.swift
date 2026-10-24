import Foundation

public struct Point: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct Bitmap1: Equatable, Sendable {
    public static let width = 384
    public static let paperLeftGap = 16
    public static let paperWidth = 404
    public static let contentWidth = 368
    public static let contentLeft = (paperWidth - contentWidth) / 2 - paperLeftGap
    public static let bytesPerRow = 48
    public static let dotsPerMillimeter = 8.0

    public let height: Int
    public private(set) var bytes: [UInt8]

    public var width: Int { Bitmap1.width }

    public var lengthMillimeters: Double { Double(height) / Bitmap1.dotsPerMillimeter }

    public init(height: Int) {
        precondition(height >= 0, "height must not be negative")
        self.height = height
        self.bytes = [UInt8](repeating: 0, count: Bitmap1.bytesPerRow * height)
    }

    public subscript(x x: Int, y y: Int) -> Bool {
        get {
            precondition(contains(x: x, y: y), "pixel out of range")
            return bytes[y * Bitmap1.bytesPerRow + x / 8] & (0x80 >> UInt8(x % 8)) != 0
        }
        set {
            precondition(contains(x: x, y: y), "pixel out of range")
            let index = y * Bitmap1.bytesPerRow + x / 8
            let mask: UInt8 = 0x80 >> UInt8(x % 8)
            if newValue {
                bytes[index] |= mask
            } else {
                bytes[index] &= ~mask
            }
        }
    }

    public mutating func set(x: Int, y: Int, black: Bool = true) {
        self[x: x, y: y] = black
    }

    public mutating func fillRow(_ y: Int) {
        precondition(y >= 0 && y < height, "row out of range")
        let start = y * Bitmap1.bytesPerRow
        for index in start..<(start + Bitmap1.bytesPerRow) {
            bytes[index] = 0xFF
        }
    }

    public func rowBytes(_ y: Int) -> ArraySlice<UInt8> {
        precondition(y >= 0 && y < height, "row out of range")
        let start = y * Bitmap1.bytesPerRow
        return bytes[start..<(start + Bitmap1.bytesPerRow)]
    }

    public func blackPixels(inColumns columns: Range<Int>) -> [Point] {
        var points: [Point] = []
        let lower = max(columns.lowerBound, 0)
        let upper = min(columns.upperBound, Bitmap1.width)
        guard lower < upper else { return points }
        for y in 0..<height {
            for x in lower..<upper where self[x: x, y: y] {
                points.append(Point(x: x, y: y))
            }
        }
        return points
    }

    private func contains(x: Int, y: Int) -> Bool {
        x >= 0 && x < Bitmap1.width && y >= 0 && y < height
    }
}
