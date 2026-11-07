import CoreGraphics
import Foundation

public struct ChekiShot: Sendable {
    public static let rowsPerSecond = 48
    public static let leadMs = 600

    public let photo: Bitmap1
    public let strip: Bitmap1

    public init(photoData: Data) throws {
        let photo = try ImageLoader.bitmap(from: ImageLoader.portraitThreeByFour(from: photoData))
        var strip = Bitmap1(height: photo.height + StripComposer.defaultFeedRows)
        strip.draw(photo, columns: 0..<Bitmap1.contentWidth, toX: Bitmap1.contentLeft, y: 0)
        self.photo = photo
        self.strip = strip
    }

    public func monochromePNG() throws -> Data {
        let width = Bitmap1.contentWidth
        var pixels = [UInt8](repeating: 255, count: width * photo.height)
        for y in 0..<photo.height {
            for x in 0..<width where photo[x: x, y: y] {
                pixels[y * width + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width, height: photo.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw PNGWriter.Failure.encodeFailed }
        return try PNGWriter.data(image)
    }

    public static func revealedRows(elapsedMs: Int, totalRows: Int, finished: Bool) -> Int {
        if finished { return totalRows }
        let rows = max(0, elapsedMs - leadMs) * rowsPerSecond / 1000
        return min(rows, max(totalRows - 1, 0))
    }
}
