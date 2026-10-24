import Testing
@testable import ThermalPrinterCore

@Test func bitmapIsAlways384DotsWide() {
    #expect(Bitmap1(height: 1).width == 384)
}

@Test func inkOutsideColumnsIsReported() {
    var bmp = Bitmap1(height: 2)
    bmp.set(x: 3, y: 1)
    #expect(bmp.blackPixels(inColumns: 0..<8) == [Point(x: 3, y: 1)])
    #expect(bmp.blackPixels(inColumns: 376..<384).isEmpty)
}

@Test func lengthInMillimetersIsRowsOverEight() {
    #expect(Bitmap1(height: 2400).lengthMillimeters == 300)
}

@Test func aNewBitmapIsWhite() {
    let bmp = Bitmap1(height: 3)
    #expect(bmp.blackPixels(inColumns: 0..<384).isEmpty)
}

@Test func setAndGetRoundTripAtTheRowEdges() {
    var bmp = Bitmap1(height: 2)
    bmp.set(x: 0, y: 0)
    bmp.set(x: 383, y: 1)
    #expect(bmp[x: 0, y: 0])
    #expect(bmp[x: 383, y: 1])
    #expect(!bmp[x: 1, y: 0])
    #expect(bmp.blackPixels(inColumns: 0..<384) == [Point(x: 0, y: 0), Point(x: 383, y: 1)])
}

@Test func fillRowBlackensTheWholeRowOnly() {
    var bmp = Bitmap1(height: 3)
    bmp.fillRow(1)
    #expect(bmp.blackPixels(inColumns: 0..<384).count == 384)
    #expect(bmp.blackPixels(inColumns: 0..<384).allSatisfy { $0.y == 1 })
}

@Test func rowsAre48BytesWithMostSignificantBitOnTheLeft() {
    var bmp = Bitmap1(height: 2)
    bmp.set(x: 0, y: 1)
    #expect(bmp.rowBytes(1).count == 48)
    #expect(bmp.rowBytes(1).first == 0x80)
    #expect(bmp.rowBytes(0).allSatisfy { $0 == 0 })
}

@Test func paperGeometryFollowsFromTheMeasuredPaperAndHeadOffset() {
    #expect(Bitmap1.width == 384)
    #expect(Bitmap1.paperLeftGap == 16)
    #expect(Bitmap1.paperWidth == 404)
    #expect(Bitmap1.contentWidth == 368)
    #expect(Bitmap1.contentLeft == 2)
}

@Test func contentIsCentredOnThePaper() {
    let leftMargin = Bitmap1.paperLeftGap + Bitmap1.contentLeft
    let rightMargin = Bitmap1.paperWidth - (Bitmap1.paperLeftGap + Bitmap1.contentLeft + Bitmap1.contentWidth)
    #expect(leftMargin == rightMargin)
}

@Test func contentFitsInsideTheBitmap() {
    #expect(Bitmap1.contentLeft >= 0)
    #expect(Bitmap1.contentLeft + Bitmap1.contentWidth <= Bitmap1.width)
    #expect(Bitmap1(height: 1).width == Bitmap1.width)
}
