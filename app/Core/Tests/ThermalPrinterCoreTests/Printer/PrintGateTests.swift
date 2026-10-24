import Testing
@testable import ThermalPrinterCore

private func gate(
    previewReady: Bool = true, rows: Int = 400, isPrinting: Bool = false,
    isRefreshingStatus: Bool = false, pendingCards: Int = 0
) -> PrintGate {
    PrintGate(
        previewReady: previewReady, rows: rows, isPrinting: isPrinting,
        isRefreshingStatus: isRefreshingStatus, pendingCards: pendingCards)
}

@Test func aReadyPreviewWithRowsAllowsPrinting() {
    #expect(gate().canPrint)
}

@Test func aMissingPreviewBlocksPrinting() {
    #expect(!gate(previewReady: false).canPrint)
}

@Test func anEmptyStripBlocksPrinting() {
    #expect(!gate(rows: 0).canPrint)
}

@Test func aRunningPrintBlocksPrinting() {
    #expect(!gate(isPrinting: true).canPrint)
}

@Test func aRunningStatusCheckBlocksPrinting() {
    #expect(!gate(isRefreshingStatus: true).canPrint)
}

@Test func pendingCardsBlockPrinting() {
    #expect(!gate(pendingCards: 1).canPrint)
}

@Test func aShortStripPrintsWithoutAsking() {
    #expect(gate(rows: 2400).decision(policy: LengthPolicy(thresholdCentimeters: 30)) == .printNow)
}

@Test func aLongStripAsksForConfirmation() {
    #expect(gate(rows: 2401).decision(policy: LengthPolicy(thresholdCentimeters: 30)) == .confirmLongPrint)
}

@Test func aBlockedGateIgnoresTheRequestEvenWhenTheStripIsLong() {
    let blocked = gate(rows: 5000, isRefreshingStatus: true)
    #expect(blocked.decision(policy: LengthPolicy(thresholdCentimeters: 30)) == .ignore)
}

@Test func theThresholdMovesTheLine() {
    let strip = gate(rows: 1500)
    #expect(strip.decision(policy: LengthPolicy(thresholdCentimeters: 30)) == .printNow)
    #expect(strip.decision(policy: LengthPolicy(thresholdCentimeters: 10)) == .confirmLongPrint)
}
