import CoreGraphics
import Foundation
import ImageIO

public enum ImageRotation: Int, Sendable {
    case degrees0 = 0
    case degrees90 = 90
    case degrees180 = 180
    case degrees270 = 270
}

public enum ImageLoaderError: Error, Equatable {
    case unreadable
    case renderFailed
}

public enum ImageLoader {
    public static func bitmap(
        from data: Data, adjust: PhotoAdjust = .neutral, rotation: ImageRotation = .degrees0
    ) throws -> Bitmap1 {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageLoaderError.unreadable
        }
        return try bitmap(from: uprightImage(source), adjust: adjust, rotation: rotation)
    }

    public static func bitmap(
        fromFile url: URL, adjust: PhotoAdjust = .neutral, rotation: ImageRotation = .degrees0
    ) throws -> Bitmap1 {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageLoaderError.unreadable
        }
        return try bitmap(from: uprightImage(source), adjust: adjust, rotation: rotation)
    }

    public static func bitmap(
        from image: CGImage, adjust: PhotoAdjust = .neutral, rotation: ImageRotation = .degrees0
    ) throws -> Bitmap1 {
        let width = Bitmap1.contentWidth
        let swapped = rotation == .degrees90 || rotation == .degrees270
        let rotatedWidth = swapped ? image.height : image.width
        let rotatedHeight = swapped ? image.width : image.height
        let height = max(1, Int((Double(rotatedHeight) * Double(width) / Double(rotatedWidth)).rounded()))

        guard let context = makeContext(width: width, height: height) else {
            throw ImageLoaderError.renderFailed
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.translateBy(x: Double(width) / 2, y: Double(height) / 2)
        context.rotate(by: -Double(rotation.rawValue) * Double.pi / 180)
        let drawWidth = swapped ? Double(height) : Double(width)
        let drawHeight = swapped ? Double(width) : Double(height)
        context.draw(image, in: CGRect(x: -drawWidth / 2, y: -drawHeight / 2, width: drawWidth, height: drawHeight))

        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else {
            throw ImageLoaderError.renderFailed
        }
        let rowStride = context.bytesPerRow
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let p = y * rowStride + x * 4
                let y255 = PhotoAdjust.luminance(r: Double(pixels[p]), g: Double(pixels[p + 1]), b: Double(pixels[p + 2]))
                values[y * width + x] = adjust.adjust(y255)
            }
        }
        return FloydSteinberg.dither(GrayImage(width: width, height: height, values: values))
    }

    public static func sampleImage() -> CGImage {
        let size = (width: 600, height: 450)
        let context = makeContext(width: size.width, height: size.height)!
        context.translateBy(x: 0, y: Double(size.height))
        context.scaleBy(x: 1, y: -1)

        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [rgb(0xdfe9f3), rgb(0x5a6b7d)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: []
        )

        func face(_ x: Double, _ y: Double, _ r: Double, skin: CGColor) {
            context.setFillColor(skin)
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            context.setFillColor(rgb(0x222222))
            for sign in [-1.0, 1.0] {
                let eye = r * 0.09
                context.fillEllipse(in: CGRect(x: x + sign * r * 0.35 - eye, y: y - r * 0.15 - eye, width: 2 * eye, height: 2 * eye))
            }
            context.setStrokeColor(rgb(0x5a2e1e))
            context.setLineWidth(r * 0.07)
            context.addArc(center: CGPoint(x: x, y: y + r * 0.15), radius: r * 0.4, startAngle: 0.2 * .pi, endAngle: 0.8 * .pi, clockwise: false)
            context.strokePath()
            context.setFillColor(rgb(0x2b1d14))
            context.addArc(center: CGPoint(x: x, y: y - r * 0.35), radius: r * 0.95, startAngle: 1.05 * .pi, endAngle: 1.95 * .pi, clockwise: false)
            context.fillPath()
        }
        face(200, 210, 95, skin: rgb(0xf1c9a5))
        face(400, 230, 85, skin: rgb(0xc98e64))
        context.setFillColor(rgb(0x333344))
        context.fill(CGRect(x: 90, y: 320, width: 220, height: 140))
        context.setFillColor(rgb(0xaa3333))
        context.fill(CGRect(x: 300, y: 330, width: 200, height: 130))
        return context.makeImage()!
    }

    private static func uprightImage(_ source: CGImageSource) throws -> CGImage {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw ImageLoaderError.unreadable
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageLoaderError.unreadable
        }
        return image
    }

    private static func makeContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(
            srgbRed: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
