import CoreGraphics
import Foundation
import Testing
import Vision
@testable import ThermalPrinterCore

enum QRFixture {
    static let githubIssue = "https://github.com/bash0C7/thermal-printer/issues/1"
    static let slackPermalink = "https://example.slack.com/archives/C0123456789/p1792565843307099?thread_ts=1792565800.000100&cid=C0123456789"
    static let longURL = "https://example.com/" + String(repeating: "a", count: 200)
    static let all = [githubIssue, slackPermalink, longURL]
}

enum QRDecoder {
    struct Failure: Error {
        let reason: String
    }

    static func decode(_ bitmap: Bitmap1) throws -> String {
        let image = try cgImage(bitmap)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let payload = request.results?.first?.payloadStringValue else {
            throw Failure(reason: "no QR code detected")
        }
        return payload
    }

    static func cgImage(_ bitmap: Bitmap1) throws -> CGImage {
        let width = bitmap.width
        let height = bitmap.height
        var gray = [UInt8](repeating: 255, count: width * height)
        for y in 0..<height {
            for x in 0..<width where bitmap[x: x, y: y] {
                gray[y * width + x] = 0
            }
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else {
            throw Failure(reason: "cannot build CGImage")
        }
        return image
    }
}

@Test(arguments: QRFixture.all)
func qrDecodesBackToTheURL(url: String) throws {
    let qr = try QRCode(url)
    #expect(try QRDecoder.decode(qr.bitmap) == url)
}

@Test(arguments: QRFixture.all)
func everyModuleIsAtLeastThreeDots(url: String) throws {
    let qr = try QRCode(url)
    #expect(qr.dotsPerModule >= 3)
    #expect(qr.sideDots == qr.moduleCount * qr.dotsPerModule)
}

@Test(arguments: [
    (QRFixture.githubIssue, 35, 3, 105),
    (QRFixture.slackPermalink, 43, 3, 129),
    (QRFixture.longURL, 63, 3, 189),
])
func sideFollowsFromTheScaleChosenFirst(url: String, modules: Int, scale: Int, side: Int) throws {
    let qr = try QRCode(url)
    #expect(qr.moduleCount == modules)
    #expect(qr.dotsPerModule == scale)
    #expect(qr.sideDots == side)
}

@Test func githubIssueURLFitsWithinTheTargetSideAtThreeDots() throws {
    let qr = try QRCode(QRFixture.githubIssue)
    #expect(qr.dotsPerModule == 3)
    #expect(qr.sideDots <= 128)
}

@Test func slackPermalinkKeepsThreeDotsEvenWhenWiderThanTheTarget() throws {
    let qr = try QRCode(QRFixture.slackPermalink)
    #expect(qr.dotsPerModule == 3)
    #expect(qr.sideDots > 128)
}

@Test func tinyPayloadIsEnlargedTowardTheTargetSide() throws {
    let qr = try QRCode("x")
    #expect(qr.dotsPerModule > 3)
    #expect(qr.sideDots <= 128)
}

@Test func bitmapIsExactlyAsTallAsTheSideAndInkStaysInsideIt() throws {
    let qr = try QRCode(QRFixture.githubIssue)
    #expect(qr.bitmap.height == qr.sideDots)
    #expect(qr.bitmap.blackPixels(inColumns: qr.sideDots..<Bitmap1.width).isEmpty)
    #expect(!qr.bitmap.blackPixels(inColumns: 0..<qr.sideDots).isEmpty)
}

@Test func quietZoneOfOneModuleIsWhite() throws {
    let qr = try QRCode(QRFixture.githubIssue)
    let border = qr.dotsPerModule
    for i in 0..<qr.sideDots {
        for k in 0..<border {
            #expect(!qr.bitmap[x: k, y: i])
            #expect(!qr.bitmap[x: qr.sideDots - 1 - k, y: i])
            #expect(!qr.bitmap[x: i, y: k])
            #expect(!qr.bitmap[x: i, y: qr.sideDots - 1 - k])
        }
    }
}

@Test func everyModuleIsFilledUniformlyWithoutInterpolation() throws {
    let qr = try QRCode(QRFixture.githubIssue)
    let scale = qr.dotsPerModule
    for my in 0..<qr.moduleCount {
        for mx in 0..<qr.moduleCount {
            let first = qr.bitmap[x: mx * scale, y: my * scale]
            for dy in 0..<scale {
                for dx in 0..<scale {
                    #expect(qr.bitmap[x: mx * scale + dx, y: my * scale + dy] == first)
                }
            }
        }
    }
}

@Test func drawCopiesTheQRIntoAWiderBitmapAtTheGivenOrigin() throws {
    let qr = try QRCode(QRFixture.githubIssue)
    var card = Bitmap1(height: 200)
    qr.draw(into: &card, x: 250, y: 20)
    for y in 0..<qr.sideDots {
        for x in 0..<qr.sideDots {
            #expect(card[x: 250 + x, y: 20 + y] == qr.bitmap[x: x, y: y])
        }
    }
    #expect(card.blackPixels(inColumns: 0..<250).isEmpty)
}

@Test func payloadWiderThanThePaperIsRejected() {
    let huge = String(repeating: "a", count: 2000)
    #expect(throws: QRCode.Failure.self) {
        try QRCode(huge)
    }
}

@Test(arguments: QRFixture.all)
func qrFitsWithinTheContentWidth(url: String) throws {
    let qr = try QRCode(url)
    #expect(qr.sideDots <= Bitmap1.contentWidth)
}

@Test func qrNarrowerThanTheContentWidthIsAccepted() throws {
    let qr = try QRCode(String(repeating: "a", count: 920))
    #expect(qr.sideDots == 357)
    #expect(qr.sideDots <= Bitmap1.contentWidth)
}

@Test func qrWiderThanTheContentWidthIsRejectedEvenWhenItWouldFitTheBitmap() {
    #expect(throws: QRCode.Failure.tooWide(sideDots: 369)) {
        try QRCode(String(repeating: "a", count: 1000))
    }
}
