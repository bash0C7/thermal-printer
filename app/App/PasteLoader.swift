import AppKit
import CoreTransferable
import Foundation
import ThermalPrinterCore
import UniformTypeIdentifiers

struct ImportedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { ImportedPhoto(data: $0) }    }
}

enum PasteLoader {
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .plainText]

    @MainActor
    static func load(_ providers: [NSItemProvider]) async -> PasteboardContent {
        var content = PasteboardContent()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
               let url = await loadURL(provider) {
                content.fileURLs.append(url)
                continue
            }
            if content.imageData == nil, let type = imageType(of: provider),
               let data = await loadData(provider, type: type) {
                content.imageData = data
                continue
            }
            if content.text == nil {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(provider) {
                    content.text = text
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let url = await loadURL(provider) {
                    content.text = url.absoluteString
                }
            }
        }
        return content
    }

    @MainActor
    static func pasteboardContent(_ pasteboard: NSPasteboard = .general) -> PasteboardContent {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL]) ?? []
        var content = PasteboardContent(fileURLs: files)
        if files.isEmpty {
            if let type = [NSPasteboard.PasteboardType.png, .tiff].first(where: { pasteboard.data(forType: $0) != nil }) {
                content.imageData = pasteboard.data(forType: type)
            }
            content.text = pasteboard.string(forType: .string)
        }
        return content
    }

    private static func imageType(of provider: NSItemProvider) -> UTType? {
        provider.registeredTypeIdentifiers.compactMap(UTType.init).first { $0.conforms(to: .image) }
    }

    @MainActor
    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    @MainActor
    private static func loadData(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
