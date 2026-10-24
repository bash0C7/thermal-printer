import Foundation
import Testing
@testable import ThermalPrinterCore

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

@Test func pbmOfStripesMatchesTheRubyFixtureByteForByte() throws {
    var bmp = Bitmap1(height: 600)
    for y in 0..<600 where y % 2 == 0 { bmp.fillRow(y) }
    let fixture = try Data(contentsOf: repoRoot.appending(path: "test/fixtures/stripes-600.pbm"))
    #expect(PBMWriter.data(bmp) == fixture)
}

@Test func pbmHeaderIsP4WithWidthAndHeight() {
    let data = PBMWriter.data(Bitmap1(height: 5))
    #expect(data.prefix(9) == Data("P4\n384 5\n".utf8))
    #expect(data.count == 9 + 48 * 5)
}
