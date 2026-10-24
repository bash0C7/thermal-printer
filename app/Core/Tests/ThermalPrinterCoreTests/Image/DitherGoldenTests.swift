import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ThermalPrinterCore

enum SyntheticGray {
    static func make(width: Int, height: Int) -> GrayImage {
        var values: [Float] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                values.append(Float((x * 223) / 383 + abs((y * 9) % 64 - 32)))
            }
        }
        return GrayImage(width: width, height: height, values: values)
    }
}

struct DitherCase: Sendable, CustomTestStringConvertible {
    let name: String
    let brightness: Double
    let contrast: Double
    let gamma: Double

    static let all = [
        DitherCase(name: "neutral", brightness: 0, contrast: 1, gamma: 1),
        DitherCase(name: "adjusted", brightness: 20, contrast: 1.3, gamma: 0.8),
    ]

    var testDescription: String { name }

    func goldenRows() throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/dither-golden-\(name).txt")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}

private extension Bitmap1 {
    var hexRows: [String] {
        (0..<height).map { y in
            rowBytes(y).map { String(format: "%02x", $0) }.joined()
        }
    }
}

struct ImageDitherGoldenTests {
    @Test(arguments: DitherCase.all)
    func floydSteinbergMatchesTheMockupReference(c: DitherCase) throws {
        let gray = SyntheticGray.make(width: Bitmap1.contentWidth, height: 32)
        let adjusted = PhotoAdjust(brightness: c.brightness, contrast: c.contrast, gamma: c.gamma).apply(gray)
        let bits = FloydSteinberg.dither(adjusted)
        #expect(bits.hexRows == (try c.goldenRows()))
        #expect(bits.blackPixels(inColumns: Bitmap1.contentWidth..<Bitmap1.width).isEmpty)
    }

    @Test func pureBlackAndPureWhiteStayUnchanged() {
        let black = GrayImage(width: Bitmap1.contentWidth, height: 2, values: [Float](repeating: 0, count: Bitmap1.contentWidth * 2))
        let white = GrayImage(width: Bitmap1.contentWidth, height: 2, values: [Float](repeating: 255, count: Bitmap1.contentWidth * 2))
        #expect(FloydSteinberg.dither(black).blackPixels(inColumns: 0..<Bitmap1.width).count == Bitmap1.contentWidth * 2)
        #expect(FloydSteinberg.dither(white).blackPixels(inColumns: 0..<384).isEmpty)
    }
}

func makeRGBAContext(width: Int, height: Int) -> CGContext {
    CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func encode(_ image: CGImage, as type: UTType, orientation: Int? = nil) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
}

func topLeftBlackImage() -> CGImage {
    let context = makeRGBAContext(width: 100, height: 50)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 25, width: 50, height: 25))
    return context.makeImage()!
}

struct ImageLoaderTests {
    @Test func anyImageIsResizedToTheContentWidthAndPaddedToTheBitmapWidth() throws {
        let jpeg = encode(ImageLoader.sampleImage(), as: .jpeg)
        let bmp = try ImageLoader.bitmap(from: jpeg)
        #expect(bmp.width == 384)
        #expect(bmp.height == Int((450.0 * Double(Bitmap1.contentWidth) / 600).rounded()))
    }

    @Test func exifOrientationIsAppliedBeforeResizing() throws {
        let context = makeRGBAContext(width: 200, height: 100)
        let png = encode(context.makeImage()!, as: .png, orientation: 6)
        let bmp = try ImageLoader.bitmap(from: png)
        #expect(bmp.height == 736)
    }

    @Test func rotating90SwapsTheAspectAndMovesTopLeftToTopRight() throws {
        let png = encode(topLeftBlackImage(), as: .png)
        let bmp = try ImageLoader.bitmap(from: png, rotation: .degrees90)
        #expect(bmp.height == 736)
        #expect(bmp[x: 350, y: 100])
        #expect(!bmp[x: 50, y: 100])
        #expect(!bmp[x: 350, y: 600])
    }

    @Test func rotating180MovesTopLeftToBottomRight() throws {
        let png = encode(topLeftBlackImage(), as: .png)
        let bmp = try ImageLoader.bitmap(from: png, rotation: .degrees180)
        #expect(bmp.height == 184)
        #expect(bmp[x: 350, y: 170])
        #expect(!bmp[x: 50, y: 20])
    }

    @Test func rotating270MovesTopLeftToBottomLeft() throws {
        let png = encode(topLeftBlackImage(), as: .png)
        let bmp = try ImageLoader.bitmap(from: png, rotation: .degrees270)
        #expect(bmp[x: 50, y: 600])
        #expect(!bmp[x: 350, y: 600])
        #expect(!bmp[x: 50, y: 100])
    }

    @Test func transparentPixelsPrintAsWhite() throws {
        let png = encode(makeRGBAContext(width: 40, height: 40).makeImage()!, as: .png)
        let bmp = try ImageLoader.bitmap(from: png)
        #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty)
    }

    @Test func solidBlackPhotoIsBlackUpToTheContentWidthAndWhiteFromThere() throws {
        let context = makeRGBAContext(width: 120, height: 60)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 120, height: 60))
        let bmp = try ImageLoader.bitmap(from: encode(context.makeImage()!, as: .png))
        #expect(bmp.blackPixels(inColumns: 0..<Bitmap1.contentWidth).count == Bitmap1.contentWidth * bmp.height)
        #expect(bmp.blackPixels(inColumns: Bitmap1.contentWidth..<Bitmap1.width).isEmpty)
    }

    @Test func whiteToBlackGradientPhotoReachesTheLastContentColumnAndLeavesTheRestWhite() throws {
        let context = makeRGBAContext(width: 400, height: 40)
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 400, y: 0), options: [])
        let bmp = try ImageLoader.bitmap(from: encode(context.makeImage()!, as: .png))
        #expect(bmp.blackPixels(inColumns: (Bitmap1.contentWidth - 1)..<Bitmap1.contentWidth).count == bmp.height)
        #expect(bmp.blackPixels(inColumns: Bitmap1.contentWidth..<Bitmap1.width).isEmpty)
    }

    @Test func unreadableDataThrows() {
        #expect(throws: ImageLoaderError.unreadable) {
            try ImageLoader.bitmap(from: Data([1, 2, 3]))
        }
    }

    @Test func rotationRawValuesAreDegrees() {
        #expect(ImageRotation(rawValue: 270) == .degrees270)
        #expect(ImageRotation(rawValue: 45) == nil)
    }
}
