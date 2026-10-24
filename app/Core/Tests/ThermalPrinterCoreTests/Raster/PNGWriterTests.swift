import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ThermalPrinterCore

private func decode(_ data: Data) throws -> (width: Int, height: Int, pixels: [UInt8]) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    let context = try #require(
        CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (width, height, pixels)
}

@Test func pngKeepsTheBitmapSizeAtOneToOne() throws {
    let bitmap = Bitmap1(height: 7)
    let decoded = try decode(PNGWriter.data(bitmap))
    #expect(decoded.width == 384)
    #expect(decoded.height == 7)
}

@Test func pngPaintsBlackDotsBlackAndTheRestWhite() throws {
    var bitmap = Bitmap1(height: 3)
    bitmap.set(x: 0, y: 0)
    bitmap.set(x: 383, y: 2)
    bitmap.set(x: 100, y: 1)
    let decoded = try decode(PNGWriter.data(bitmap))
    #expect(decoded.pixels[0] == 0)
    #expect(decoded.pixels[1 * 384 + 100] == 0)
    #expect(decoded.pixels[2 * 384 + 383] == 0)
    #expect(decoded.pixels[1] == 255)
    #expect(decoded.pixels.filter { $0 == 0 }.count == 3)
}

@Test func anEmptyBitmapCannotBeEncodedAsPNG() {
    #expect(throws: PNGWriter.Failure.self) { try PNGWriter.data(Bitmap1(height: 0)) }
}
