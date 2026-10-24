import SwiftUI
import ThermalPrinterCore

struct PreviewColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let width = model.scale.points(forDots: Bitmap1.paperWidth)
        ScrollView {
            switch model.previews.phase {
            case .ready(let cliPreview):
                if let image = cliPreview.image {
                    strip(image: image, width: width)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                }
            case .generating:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("CLIでプレビューを作っています…")
                }
                .foregroundStyle(.secondary)
                .padding(24)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("previewGeneratingLabel")
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("previewFailedLabel")
            case .empty:
                Text("部品を追加すると、ここに実寸のプレビューが出ます")
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("emptyPreviewLabel")
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .navigationSplitViewColumnWidth(min: width + 48, ideal: width + 80)
    }

    private func strip(image: CGImage, width: Double) -> some View {
        let height = model.scale.points(forDots: image.height)
        let headWidth = model.scale.points(forDots: Bitmap1.width)
        let gap = model.scale.points(forDots: Bitmap1.paperLeftGap)
        return ZStack(alignment: .topLeading) {
            Color.white
            Image(image, scale: 1, label: Text("実寸プレビュー"))
                .resizable()
                .interpolation(.none)
                .antialiased(false)
                .frame(width: headWidth, height: height)
                .offset(x: gap)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isImage)
                .accessibilityLabel("実寸プレビュー")
                .accessibilityValue("\(image.height)行")
                .accessibilityIdentifier("previewImage")
        }
        .frame(width: width, height: height)
        .overlay(alignment: .topLeading) { selectionOutline(width: width) }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
    }

    @ViewBuilder
    private func selectionOutline(width: Double) -> some View {
        if let preview = model.preview,
           let index = model.parts.firstIndex(where: { $0.id == model.selection }),
           index < preview.strip.partRanges.count {
            let range = preview.strip.partRanges[index]
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: width, height: model.scale.points(forDots: range.count))
                .offset(y: model.scale.points(forDots: range.lowerBound))
                .allowsHitTesting(false)
        }
    }
}
