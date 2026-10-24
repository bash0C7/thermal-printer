import Foundation
import Testing
@testable import ThermalPrinterCore

@Test(arguments: [
    ("https://github.com/a/b/issues/1", PasteRouter.Kind.card),
    ("  https://example.com/x  \n", .card),
    ("http://example.com", .card),
    ("# 見出し\n本文 https://example.com", .markdown),
    ("ただの文", .markdown),
    ("https://example.com/a https://example.com/b", .markdown),
    ("https://example.com/a\nhttps://example.com/b", .markdown),
    ("参考: https://example.com/a", .markdown),
    ("example.com/path", .markdown),
    ("ftp://example.com/file", .markdown),
    ("https://", .markdown),
])
func pastedTextIsRoutedByContent(text: String, kind: PasteRouter.Kind) {
    #expect(PasteRouter.route(text: text) == kind)
}

@Test(arguments: [
    ("photo.jpg", PasteRouter.Kind.image),
    ("photo.JPEG", .image),
    ("shot.png", .image),
    ("shot.heic", .image),
    ("notes.md", .markdown),
    ("notes.markdown", .markdown),
    ("notes.txt", .text),
])
func droppedFilesAreRoutedByExtension(name: String, kind: PasteRouter.Kind) {
    #expect(PasteRouter.route(fileURL: URL(filePath: "/tmp/\(name)")) == kind)
}

@Test func unknownFileExtensionsAreNotRouted() {
    #expect(PasteRouter.route(fileURL: URL(filePath: "/tmp/archive.zip")) == nil)
    #expect(PasteRouter.route(fileURL: URL(filePath: "/tmp/noextension")) == nil)
}

private func items(_ content: PasteboardContent, files: [String: Data] = [:]) -> [PasteItem] {
    PasteRouter.items(from: content) { url in
        guard let data = files[url.lastPathComponent] else { throw CocoaError(.fileReadNoSuchFile) }
        return data
    }
}

@Test func imageDataBecomesAnImagePart() {
    let data = Data([1, 2, 3])
    #expect(items(PasteboardContent(imageData: data)) == [.part(.image(data))])
}

@Test func urlTextBecomesACardRequestNotAPart() {
    #expect(items(PasteboardContent(text: " https://github.com/a/b/issues/1\n")) == [.cardURL("https://github.com/a/b/issues/1")])
}

@Test func otherTextBecomesAMarkdownPart() {
    #expect(items(PasteboardContent(text: "# 見出し\n本文")) == [.part(.markdown("# 見出し\n本文"))])
}

@Test func blankTextProducesNothing() {
    #expect(items(PasteboardContent(text: " \n\t ")).isEmpty)
    #expect(items(PasteboardContent()).isEmpty)
}

@Test func filesTakePrecedenceOverTheImageAndTextTheyAlsoCarry() {
    let content = PasteboardContent(
        imageData: Data([9]), fileURLs: [URL(filePath: "/tmp/a.md")], text: "a.md"
    )
    let result = items(content, files: ["a.md": Data("# a".utf8)])
    #expect(result == [.part(.markdown("# a", baseURL: URL(filePath: "/tmp", directoryHint: .isDirectory)))])
}

@Test func imageDataTakesPrecedenceOverText() {
    let result = items(PasteboardContent(imageData: Data([7]), text: "caption"))
    #expect(result == [.part(.image(Data([7])))])
}

@Test func droppedImageFileIsReadIntoAnImagePart() {
    let bytes = Data([0xff, 0xd8])
    let result = items(PasteboardContent(fileURLs: [URL(filePath: "/tmp/p.jpg")]), files: ["p.jpg": bytes])
    #expect(result == [.part(.image(bytes))])
}

@Test func droppedTextFileBecomesATextPart() {
    let result = items(PasteboardContent(fileURLs: [URL(filePath: "/tmp/a.txt")]), files: ["a.txt": Data("メモ".utf8)])
    #expect(result == [.part(.text("メモ"))])
}

@Test func multipleFilesKeepTheirOrder() {
    let urls = ["b.md", "a.png"].map { URL(filePath: "/tmp/\($0)") }
    let result = items(PasteboardContent(fileURLs: urls), files: ["b.md": Data("b".utf8), "a.png": Data([5])])
    #expect(result == [
        .part(.markdown("b", baseURL: URL(filePath: "/tmp", directoryHint: .isDirectory))),
        .part(.image(Data([5]))),
    ])
}

@Test func unsupportedFilesAreRejectedWithTheirName() {
    let result = items(PasteboardContent(fileURLs: [URL(filePath: "/tmp/a.zip")]))
    #expect(result == [.rejected("a.zip: 対応していない形式です")])
}

@Test func unreadableFilesAreRejectedWithTheirName() {
    let result = items(PasteboardContent(fileURLs: [URL(filePath: "/tmp/missing.md")]))
    guard case .rejected(let message) = result.first else {
        Issue.record("expected a rejection")
        return
    }
    #expect(message.hasPrefix("missing.md:"))
}

@Test func nonUTF8TextFilesAreRejected() {
    let result = items(PasteboardContent(fileURLs: [URL(filePath: "/tmp/a.txt")]), files: ["a.txt": Data([0xff, 0xfe, 0xfd])])
    #expect(result == [.rejected("a.txt: UTF-8 として読めません")])
}

@Test func partsOfProducesOnlyImmediateParts() {
    let result: [PasteItem] = [.part(.text("a")), .cardURL("https://example.com"), .rejected("x"), .part(.text("b"))]
    #expect(PasteItem.parts(of: result) == [.text("a"), .text("b")])
}
