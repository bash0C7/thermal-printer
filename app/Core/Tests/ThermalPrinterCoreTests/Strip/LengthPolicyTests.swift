import Testing
@testable import ThermalPrinterCore

@Test func lengthIsRowsOverEightMillimeters() {
    #expect(LengthPolicy.millimeters(rows: 2400) == 300)
    #expect(LengthPolicy.centimeters(rows: 2400) == 30.0)
}

@Test func lengthAgreesWithTheBitmapLength() {
    let bitmap = Bitmap1(height: 1234)
    #expect(LengthPolicy.millimeters(rows: bitmap.height) == bitmap.lengthMillimeters)
}

@Test func warningStartsAboveTheThreshold() {
    let policy = LengthPolicy(thresholdCentimeters: 30)
    #expect(!policy.isTooLong(rows: 2400))
    #expect(policy.isTooLong(rows: 2401))
}

@Test func defaultThresholdIsThirtyCentimeters() {
    #expect(LengthPolicy().thresholdCentimeters == 30)
    #expect(LengthPolicy.defaultThresholdCentimeters == 30)
}

@Test func thresholdCanBeChanged() {
    let policy = LengthPolicy(thresholdCentimeters: 12.5)
    #expect(!policy.isTooLong(rows: 1000))
    #expect(policy.isTooLong(rows: 1001))
}

@Test func bitmapOverloadUsesItsHeight() {
    let policy = LengthPolicy(thresholdCentimeters: 30)
    #expect(!policy.isTooLong(Bitmap1(height: 2400)))
    #expect(policy.isTooLong(Bitmap1(height: 2401)))
}

@Test func lengthTextIsAlwaysAvailableWithOneDecimal() {
    #expect(LengthPolicy.lengthText(rows: 2400) == "30.0 cm")
    #expect(LengthPolicy.lengthText(rows: 0) == "0.0 cm")
    #expect(LengthPolicy.lengthText(rows: 104) == "1.3 cm")
}

@Test func warningTextExistsOnlyWhenTooLong() {
    let policy = LengthPolicy(thresholdCentimeters: 30)
    #expect(policy.warningText(rows: 2400) == nil)
    let text = policy.warningText(rows: 3200)
    #expect(text?.contains("40.0 cm") == true)
    #expect(text?.contains("30") == true)
}
