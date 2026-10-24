import Foundation

public struct GrayImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let values: [Float]

    public init(width: Int, height: Int, values: [Float]) {
        precondition(width >= 0 && height >= 0, "size must not be negative")
        precondition(values.count == width * height, "values must hold width * height samples")
        self.width = width
        self.height = height
        self.values = values
    }
}

public struct PhotoAdjust: Equatable, Sendable {
    public static let neutral = PhotoAdjust(brightness: 0, contrast: 1, gamma: 1)

    public var brightness: Double
    public var contrast: Double
    public var gamma: Double

    public init(brightness: Double, contrast: Double, gamma: Double) {
        self.brightness = brightness
        self.contrast = contrast
        self.gamma = gamma
    }

    public static func luminance(r: Double, g: Double, b: Double) -> Double {
        0.299 * r + 0.587 * g + 0.114 * b
    }

    public func adjust(_ luminance: Double) -> Float {
        var y = 255 * pow(luminance / 255, gamma)
        y = (y - 128) * contrast + 128 + brightness
        return Float(y)
    }

    public func apply(_ gray: GrayImage) -> GrayImage {
        GrayImage(width: gray.width, height: gray.height, values: gray.values.map { adjust(Double($0)) })
    }
}
