import Foundation
import Testing
@testable import ThermalPrinterCore

@Test(arguments: PrintResult.ErrorKind.allCases)
func everyErrorKindHasAJapaneseMessage(kind: PrintResult.ErrorKind) {
    #expect(!PrinterStatusText.message(for: kind).isEmpty)
}

@Test func notFoundMessageCarriesTheWakeUpHints() {
    let m = PrinterStatusText.message(for: .notFound)
    #expect(m.contains("電源ボタン"))
    #expect(m.contains("公式アプリ"))
}

@Test func aRemovedPairingTellsToForgetTheT02AndShowsTheDetailCode() {
    let m = PrinterStatusText.message(for: .notFound, detail: "pairing_info_removed")
    #expect(m.contains("ペアリング情報"))
    #expect(m.contains("登録を解除"))
    #expect(m.contains("pairing_info_removed"))
}

@Test(arguments: ["pairing_info_removed", "auth_failed", "connect_timeout", "link_dropped"])
func everyConnectFailureHasItsOwnMessageWithItsCode(detail: String) {
    let m = PrinterStatusText.message(for: .notFound, detail: detail)
    #expect(m != PrinterStatusText.message(for: .notFound))
    #expect(m.contains("見つかりましたが"))
    #expect(m.contains(detail))
}

@Test(arguments: [nil, "name_not_seen", "something_new"] as [String?])
func withoutAConnectFailureNotFoundKeepsTheWakeUpMessage(detail: String?) {
    #expect(PrinterStatusText.message(for: .notFound, detail: detail) == PrinterStatusText.message(for: .notFound))
}

@Test func detailDoesNotChangeTheMessageOfOtherErrors() {
    #expect(PrinterStatusText.message(for: .busy, detail: "link_dropped") == PrinterStatusText.message(for: .busy))
}

@Test func paperCoverHeatAndBatteryMessagesNameTheirCause() {
    #expect(PrinterStatusText.message(for: .paperOut).contains("紙"))
    #expect(PrinterStatusText.message(for: .coverOpen).contains("カバー"))
    #expect(PrinterStatusText.message(for: .overheat).contains("高温"))
    #expect(PrinterStatusText.message(for: .lowBattery).contains("電池"))
}

@Test func statusLineShowsBatteryPaperAndCheckTime() throws {
    let r = try decodePrinterFixture("result_status_ok")
    let line = PrinterStatusText.titleBar(r.status!, checkedAt: printerDate(hour: 10, minute: 42))
    #expect(line == "電池83%・紙あり・カバー閉・温度正常（10:42確認）")
}

@Test func statusLineNamesEachFaultAndPadsTheMinute() {
    let status = PrintResult.Status(battery: 4, paper: "out", cover: "open", temperature: "overheat",
                                    firmware: nil, serial: nil, autoOff: nil)
    let line = PrinterStatusText.titleBar(status, checkedAt: printerDate(hour: 9, minute: 5))
    #expect(line == "電池4%・紙なし・カバー開・温度過熱（9:05確認）")
}

@Test func statusLineOmitsWhatTheCLIDidNotReport() {
    let status = PrintResult.Status(battery: 70, paper: nil, cover: nil, temperature: nil,
                                    firmware: nil, serial: nil, autoOff: nil)
    #expect(PrinterStatusText.titleBar(status, checkedAt: printerDate(hour: 10, minute: 42)) == "電池70%（10:42確認）")
}

@Test func statusLineWithNothingReportedSaysUnknown() {
    let status = PrintResult.Status(battery: nil, paper: nil, cover: nil, temperature: nil,
                                    firmware: nil, serial: nil, autoOff: nil)
    #expect(PrinterStatusText.titleBar(status, checkedAt: printerDate(hour: 10, minute: 42)) == "状態不明（10:42確認）")
}

@Test func knownWarningsAreTranslatedAndUnknownOnesPassThrough() {
    #expect(PrinterStatusText.warningMessage("status_unavailable").contains("状態"))
    #expect(PrinterStatusText.warningMessage("completion_unconfirmed").contains("完了"))
    #expect(PrinterStatusText.warningMessage("battery_low").contains("電池"))
    #expect(PrinterStatusText.warningMessage("brand_new") == "brand_new")
}
