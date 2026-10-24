import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Bitmap1 {
    public func cgImage() -> CGImage? {
        guard height > 0 else { return nil }
        var pixels = [UInt8](repeating: 255, count: Bitmap1.width * height)
        for y in 0..<height {
            for x in 0..<Bitmap1.width where self[x: x, y: y] {
                pixels[y * Bitmap1.width + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: Bitmap1.width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: Bitmap1.width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

public enum PNGWriter {
    public enum Failure: Error, Equatable {
        case emptyBitmap
        case encodeFailed
    }

    public static func data(_ bitmap: Bitmap1) throws -> Data {
        guard let image = bitmap.cgImage() else { throw Failure.emptyBitmap }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodeFailed }
        return output as Data
    }
}
