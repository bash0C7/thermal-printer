import Foundation

public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Int { x }
    public var maxX: Int { x + width }
    public var minY: Int { y }
    public var maxY: Int { y + height }
}

extension Bitmap1 {
    public mutating func draw(_ source: Bitmap1, columns: Range<Int>, toX originX: Int, y originY: Int) {
        for sy in 0..<source.height {
            let y = originY + sy
            guard y >= 0, y < height, source.rowBytes(sy).contains(where: { $0 != 0 }) else { continue }
            for sx in columns where source[x: sx, y: sy] {
                set(x: originX + sx - columns.lowerBound, y: y)
            }
        }
    }

    public mutating func fill(_ rect: PixelRect) {
        let (xs, ys) = clamped(rect)
        for y in ys {
            for x in xs {
                set(x: x, y: y)
            }
        }
    }

    public func crop(_ rect: PixelRect) -> Bitmap1 {
        var result = Bitmap1(height: rect.height)
        result.draw(self, columns: rect.minX..<rect.maxX, toX: 0, y: -rect.minY)
        return result
    }

    public func blackPixels(in rect: PixelRect) -> [Point] {
        var points: [Point] = []
        let (xs, ys) = clamped(rect)
        for y in ys {
            for x in xs where self[x: x, y: y] {
                points.append(Point(x: x, y: y))
            }
        }
        return points
    }

    private func clamped(_ rect: PixelRect) -> (Range<Int>, Range<Int>) {
        let left = max(rect.minX, 0)
        let top = max(rect.minY, 0)
        let xs = left..<max(left, min(rect.maxX, Bitmap1.width))
        let ys = top..<max(top, min(rect.maxY, height))
        return (xs, ys)
    }
}
