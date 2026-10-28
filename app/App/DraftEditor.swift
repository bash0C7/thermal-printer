import AppKit
import SwiftUI
import ThermalPrinterCore

final class DraftTextView: NSTextView {
    var imageToken: ((Data) -> String?)?

    override func paste(_ sender: Any?) {
        guard let data = Self.pastedImage(NSPasteboard.general), let token = imageToken?(data) else {
            super.paste(sender)
            return
        }
        insertText(token, replacementRange: selectedRange())
    }

    private static func pastedImage(_ pasteboard: NSPasteboard) -> Data? {
        let files = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if let file = files.first, PasteRouter.route(fileURL: file) == .image {
            return try? Data(contentsOf: file)
        }
        guard files.isEmpty else { return nil }
        let type = [NSPasteboard.PasteboardType.png, .tiff].first { pasteboard.data(forType: $0) != nil }
        return type.flatMap { pasteboard.data(forType: $0) }
    }
}

struct DraftEditor: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = DraftTextView()
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.imageToken = { [model] in model.addDraftImage($0) }
        textView.string = model.draftText
        textView.setAccessibilityIdentifier("draftEditor")
        textView.setAccessibilityLabel("テキストボックス")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, textView.string != model.draftText else { return }
        textView.string = model.draftText
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel

        init(model: AppModel) {
            self.model = model
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            model.draftEdited(textView.string)
        }
    }
}
