import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ThermalPrinterCore

struct ChekiShotTests {
    static func encoded(
        _ type: UTType, width: Int, height: Int, blackFromX: Int, blackToX: Int, orientation: Int = 1
    ) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: blackFromX, y: 0, width: blackToX - blackFromX, height: height))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(
            destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    static func png(width: Int, height: Int, blackFromX: Int) -> Data {
        encoded(.png, width: width, height: height, blackFromX: blackFromX, blackToX: width)
    }

    @Test func theWholeShotIsKeptAtThePaperWidth() throws {
        let shot = try ChekiShot(photoData: Self.png(width: 300, height: 400, blackFromX: 0))
        #expect(shot.photo.height == 491)
        #expect(shot.photo[x: 0, y: 0])
        #expect(shot.photo[x: Bitmap1.contentWidth - 1, y: shot.photo.height - 1])
    }

    @Test func aWideShotIsTurnedSoItsShortSideSpansThePaper() throws {
        let shot = try ChekiShot(photoData: Self.png(width: 800, height: 300, blackFromX: 700))
        let middle = Bitmap1.contentWidth / 2
        #expect(shot.photo.height == 981)
        #expect(shot.photo[x: middle, y: 0] != shot.photo[x: middle, y: shot.photo.height - 1])
        #expect(!shot.photo[x: middle, y: shot.photo.height / 2])
    }

    @Test func aShotStoredSidewaysIsPrintedUpright() throws {
        let sideways = Self.encoded(.jpeg, width: 400, height: 300, blackFromX: 0, blackToX: 200, orientation: 6)
        let shot = try ChekiShot(photoData: sideways)
        let middle = Bitmap1.contentWidth / 2
        #expect(shot.photo.height == 491)
        #expect(shot.photo[x: middle, y: 0])
        #expect(!shot.photo[x: middle, y: shot.photo.height - 1])
    }

    @Test func theStripPlacesThePhotoInTheContentColumnsAndAddsTheFeed() throws {
        let shot = try ChekiShot(photoData: Self.png(width: 300, height: 400, blackFromX: 0))
        #expect(shot.strip.height == shot.photo.height + StripComposer.defaultFeedRows)
        #expect(shot.strip[x: Bitmap1.contentLeft, y: 0])
        #expect(shot.strip[x: Bitmap1.contentLeft + Bitmap1.contentWidth - 1, y: shot.photo.height - 1])
        #expect(!shot.strip[x: Bitmap1.contentLeft - 1, y: 0])
        #expect(!shot.strip[x: Bitmap1.contentLeft, y: shot.photo.height])
    }

    @Test func theMonochromePNGPrintsBackAsTheSamePhoto() throws {
        let shot = try ChekiShot(photoData: Self.png(width: 600, height: 800, blackFromX: 250))
        let saved = try shot.monochromePNG()
        let source = CGImageSourceCreateWithData(saved as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        #expect(image.width == Bitmap1.contentWidth)
        #expect(image.height == shot.photo.height)
        #expect(try ImageLoader.bitmap(from: saved) == shot.photo)
    }

    @Test func nothingIsRevealedBeforeTheLead() {
        #expect(ChekiShot.revealedRows(elapsedMs: 0, totalRows: 491, finished: false) == 0)
        #expect(ChekiShot.revealedRows(elapsedMs: ChekiShot.leadMs, totalRows: 491, finished: false) == 0)
    }

    @Test func rowsAreRevealedAtThePrintSpeedAfterTheLead() {
        let rows = ChekiShot.revealedRows(elapsedMs: ChekiShot.leadMs + 2000, totalRows: 491, finished: false)
        #expect(rows == 2 * ChekiShot.rowsPerSecond)
    }

    @Test func theLastRowWaitsForTheResult() {
        #expect(ChekiShot.revealedRows(elapsedMs: 60_000, totalRows: 491, finished: false) == 490)
        #expect(ChekiShot.revealedRows(elapsedMs: 0, totalRows: 491, finished: true) == 491)
    }
}
