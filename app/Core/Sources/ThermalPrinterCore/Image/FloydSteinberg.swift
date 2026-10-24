import Foundation

public enum FloydSteinberg {
    private static let kernel: [(dx: Int, dy: Int, weight: Double)] = [
        (1, 0, 7), (-1, 1, 3), (0, 1, 5), (1, 1, 1),
    ]

    public static func dither(_ gray: GrayImage) -> Bitmap1 {
        precondition(gray.width == Bitmap1.contentWidth, "dither input must be \(Bitmap1.contentWidth) dots wide")
        let width = gray.width
        let height = gray.height
        var v = gray.values
        var bitmap = Bitmap1(height: height)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                let value = Double(v[i])
                let out: Double = value < 128 ? 0 : 255
                if out == 0 {
                    bitmap.set(x: x, y: y)
                }
                let err = (value - out) / 16
                for k in kernel {
                    let xx = x + k.dx
                    let yy = y + k.dy
                    if xx >= 0 && xx < width && yy < height {
                        let j = yy * width + xx
                        v[j] = Float(Double(v[j]) + err * k.weight)
                    }
                }
            }
        }
        return bitmap
    }
}
