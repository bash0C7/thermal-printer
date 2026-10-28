import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

public struct QRCode: Equatable, Sendable {
    public static let targetSideDots = 128
    public static let longTargetSideDots = 300
    public static let shortMaxModules = 45
    public static let minimumDotsPerModule = 3

    public enum Failure: Error, Equatable {
        case generationFailed
        case tooWide(sideDots: Int)
    }

    public let moduleCount: Int
    public let dotsPerModule: Int
    public let bitmap: Bitmap1

    public var sideDots: Int { moduleCount * dotsPerModule }

    public static func moduleCount(for text: String) -> Int? {
        modulesOutput(for: text).map { Int($0.extent.width) }
    }

    private static func modulesOutput(for text: String) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        return filter.outputImage
    }

    public init(_ text: String) throws {
        guard let output = Self.modulesOutput(for: text) else { throw Failure.generationFailed }
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let modules = context.createCGImage(
            output, from: output.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()
        ) else {
            throw Failure.generationFailed
        }

        let count = modules.width
        let target = count <= QRCode.shortMaxModules ? QRCode.targetSideDots : QRCode.longTargetSideDots
        let scale = max(QRCode.minimumDotsPerModule, target / count)
        let side = count * scale
        guard side <= Bitmap1.contentWidth else { throw Failure.tooWide(sideDots: side) }

        guard let gray = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let data = gray.data else {
            throw Failure.generationFailed
        }
        gray.interpolationQuality = .none
        gray.draw(modules, in: CGRect(x: 0, y: 0, width: side, height: side))

        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side)
        var bitmap = Bitmap1(height: side)
        for y in 0..<side {
            for x in 0..<side where pixels[y * side + x] < 128 {
                bitmap.set(x: x, y: y)
            }
        }

        self.moduleCount = count
        self.dotsPerModule = scale
        self.bitmap = bitmap
    }

    public func draw(into target: inout Bitmap1, x originX: Int, y originY: Int) {
        let side = sideDots
        for y in 0..<side {
            for x in 0..<side where bitmap[x: x, y: y] {
                target.set(x: originX + x, y: originY + y)
            }
        }
    }
}
