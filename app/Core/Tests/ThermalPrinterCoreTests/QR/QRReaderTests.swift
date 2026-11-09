import Foundation
import Testing
@testable import ThermalPrinterCore

extension String {
    var strictlyEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
    }
}

private let longestTaskName = "記事化 Example's Learning Hubでエンジニアリングの見識を高めるにはこの方が手がけた本をまず読んでみよう"

@Test(arguments: [
    "taskforge:///task/weekly-report",
    "obsidian://open?vault=my-vault&file=" + "00_TaskNotes/週次レポート — draft PR #1234 & 手直し + 提出".strictlyEncoded,
    "obsidian://open?vault=my-vault&file=" + "00_TaskNotes/\(longestTaskName)".strictlyEncoded,
    "x-apple-reminderkit://REMCDReminder/0E1F",
])
func aQRDrawnByThisAppIsReadBackToTheSameText(text: String) throws {
    let qr = try QRCode(text)
    var bitmap = Bitmap1(height: qr.sideDots + 32)
    qr.draw(into: &bitmap, x: 16, y: 16)
    #expect(try QRReader.payloads(in: #require(bitmap.cgImage())) == [text])
}

@Test func anImageWithoutAQRYieldsNothing() throws {
    let blank = Bitmap1(height: 64)
    #expect(try QRReader.payloads(in: #require(blank.cgImage())) == [])
}
