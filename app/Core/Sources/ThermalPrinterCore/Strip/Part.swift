import Foundation

public enum TextSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var style: TextStyle {
        switch self {
        case .small: return .small
        case .medium: return .body
        case .large: return .large
        }
    }
}

public struct PhotoSettings: Equatable, Sendable {
    public static let neutral = PhotoSettings()

    public var brightness: Double
    public var contrast: Double
    public var gamma: Double
    public var rotation: ImageRotation

    public init(brightness: Double = 0, contrast: Double = 1, gamma: Double = 1, rotation: ImageRotation = .degrees0) {
        self.brightness = brightness
        self.contrast = contrast
        self.gamma = gamma
        self.rotation = rotation
    }

    public var adjust: PhotoAdjust {
        PhotoAdjust(brightness: brightness, contrast: contrast, gamma: gamma)
    }
}

public enum Part: Equatable, Sendable {
    case text(String, size: TextSize = .medium)
    case markdown(String, baseURL: URL? = nil, asPlainText: Bool = false)
    case image(Data, PhotoSettings = .neutral)
    case card(Card)
}
