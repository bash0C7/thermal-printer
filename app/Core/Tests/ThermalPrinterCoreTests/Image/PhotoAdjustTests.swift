import Testing
@testable import ThermalPrinterCore

struct ImagePhotoAdjustTests {
    @Test func luminanceUsesRec601Weights() {
        #expect(PhotoAdjust.luminance(r: 255, g: 0, b: 0) == 0.299 * 255)
        #expect(PhotoAdjust.luminance(r: 0, g: 255, b: 0) == 0.587 * 255)
        #expect(PhotoAdjust.luminance(r: 0, g: 0, b: 255) == 0.114 * 255)
    }

    @Test func neutralAdjustmentIsIdentity() {
        let gray = SyntheticGray.make(width: Bitmap1.contentWidth, height: 4)
        #expect(PhotoAdjust.neutral.apply(gray) == gray)
    }

    @Test func gammaThenContrastAroundMidGrayThenBrightness() {
        let gray = GrayImage(width: 1, height: 1, values: [128])
        let adjusted = PhotoAdjust(brightness: 10, contrast: 2, gamma: 2).apply(gray)
        #expect(abs(adjusted.values[0] - 10.502) < 0.01)
    }

    @Test func adjustedValuesAreNotClampedBeforeDithering() {
        let gray = GrayImage(width: 1, height: 1, values: [255])
        let adjusted = PhotoAdjust(brightness: 80, contrast: 2, gamma: 1).apply(gray)
        #expect(adjusted.values[0] == 462)
    }
}
