import Testing
@testable import ThermalPrinterCore

@Test func a27InchFiveKDisplayGivesAboutTwoPointsPerMillimeter() {
    let s = PhysicalScale(pixelsWide: 5120, millimetersWide: 597, backingScale: 2)
    #expect(abs(s.pointsPerMillimeter - 4.288) < 0.01)
}

@Test func previewWidthIs48Millimeters() {
    let s = PhysicalScale(pixelsWide: 5120, millimetersWide: 597, backingScale: 2)
    #expect(abs(s.points(forDots: 384) - 48 * s.pointsPerMillimeter) < 0.01)
}

@Test func eightDotsMakeOneMillimeter() {
    let s = PhysicalScale(pixelsWide: 3024, millimetersWide: 344, backingScale: 2)
    #expect(abs(s.points(forDots: 8) - s.pointsPerMillimeter) < 1e-9)
}

@Test func aThirtyCentimeterStripIsThirtyCentimetersOnScreen() {
    let s = PhysicalScale(pixelsWide: 3456, millimetersWide: 302, backingScale: 2)
    #expect(abs(s.points(forDots: 2400) - 300 * s.pointsPerMillimeter) < 1e-6)
}

@Test func theBackingScaleDoesNotChangeThePhysicalSize() {
    let retina = PhysicalScale(pixelsWide: 3024, millimetersWide: 344, backingScale: 2)
    let logical = PhysicalScale(pixelsWide: 1512, millimetersWide: 344, backingScale: 1)
    #expect(abs(retina.pointsPerMillimeter - logical.pointsPerMillimeter) < 1e-9)
}

@Test func unknownDisplaySizeFallsBackToSeventyTwoPointsPerInch() {
    let s = PhysicalScale.measured(pixelsWide: 2560, millimetersWide: 0, backingScale: 2)
    #expect(s == .fallback)
    #expect(abs(s.pointsPerMillimeter - 72 / 25.4) < 1e-9)
}

@Test func aMeasuredDisplayIsUsedAsIs() {
    let s = PhysicalScale.measured(pixelsWide: 5120, millimetersWide: 597, backingScale: 2)
    #expect(s == PhysicalScale(pixelsWide: 5120, millimetersWide: 597, backingScale: 2))
}
