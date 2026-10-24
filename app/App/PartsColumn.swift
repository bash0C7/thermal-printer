import SwiftUI
import ThermalPrinterCore

extension Part {
    var kindLabel: String {
        switch self {
        case .text: "テキスト"
        case .markdown: "MD"
        case .image: "写真"
        case .card(let card):
            switch card.kind {
            case .github: "GitHub"
            case .slack: "Slack"
            case .url: "URL"
            case .reminder: "リマインダー"
            }
        }
    }

    var summary: String {
        switch self {
        case .text(let text, _): Self.firstLine(text)
        case .markdown(let text, _, _): Self.firstLine(text)
        case .image(let data, _): "画像（\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))）"
        case .card(let card):
            [card.header.lines.first, card.header.emphasis, card.title].compactMap { $0 }.joined(separator: " ")
        }
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return String(line.prefix(60))
    }
}

struct PartsColumn: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            dropZone
            List(selection: $model.selection) {
                ForEach(Array(model.parts.enumerated()), id: \.element.id) { index, entry in
                    PartRow(entry: entry)
                        .tag(entry.id)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("partRow-\(index)")
                }
                .onMove { model.move(from: $0, to: $1) }
                .onDelete { offsets in model.remove(ids: Set(offsets.map { model.parts[$0].id })) }
            }
            .accessibilityIdentifier("partsList")
            .overlay {
                if model.parts.isEmpty {
                    Text("部品がありません")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("emptyPartsLabel")
                }
            }
            if let selected = model.parts.first(where: { $0.id == model.selection }) {
                Divider()
                PartInspector(entry: selected)
                    .padding(12)
            }
        }
        .onPasteCommand(of: PasteLoader.acceptedTypes) { model.receive(providers: $0) }
        .onDrop(of: PasteLoader.acceptedTypes, isTargeted: $isDropTargeted) { providers in
            model.receive(providers: providers)
            return true
        }
        .importsItemProviders([.image]) { providers in
            model.receive(providers: providers)
            return true
        }
        .importableFromServices(for: ImportedPhoto.self) { photos in
            model.receive(photos: photos)
            return true
        }
        .onDeleteCommand { model.removeSelected() }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(2)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Text("ここにドロップ / ⌘V で追加")
                .foregroundStyle(.secondary)
            HStack {
                Button("クリップボードから追加") { model.pasteFromPasteboard() }
                    .accessibilityIdentifier("pasteButton")
                if model.pendingCards > 0 {
                    ProgressView().controlSize(.small)
                    Text("カードを取得中").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .foregroundStyle(.tertiary)
        )
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dropZone")
    }
}

struct PartRow: View {
    @Environment(AppModel.self) private var model
    let entry: PartEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.part.kindLabel)
                .font(.caption)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(entry.part.summary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                model.remove(ids: [entry.id])
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("この部品を削除")
            .accessibilityLabel("削除")
            .accessibilityIdentifier("removePartButton")
        }
    }
}

struct PartInspector: View {
    @Environment(AppModel.self) private var model
    let entry: PartEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.part {
            case .image(_, let settings):
                Text("写真の設定").bold()
                slider("明るさ", value: settings.brightness, range: -80...80, id: "brightnessSlider") { $0.brightness = $1 }
                slider("コントラスト", value: settings.contrast, range: 0.5...2, id: "contrastSlider") { $0.contrast = $1 }
                slider("ガンマ", value: settings.gamma, range: 0.5...2, id: "gammaSlider") { $0.gamma = $1 }
                HStack {
                    Text("向き")
                    Spacer()
                    Button {
                        updateSettings { $0.rotation = Self.rotated($0.rotation) }
                    } label: {
                        Label("右に回転", systemImage: "rotate.right")
                    }
                    .accessibilityIdentifier("rotateButton")
                    Button("元に戻す") { updateSettings { $0 = .neutral } }
                        .accessibilityIdentifier("resetPhotoButton")
                }
            case .text(_, let size):
                Text("テキストの設定").bold()
                Picker("文字サイズ", selection: Binding(
                    get: { size },
                    set: { newSize in
                        model.update(entry.id) { part in
                            if case .text(let text, _) = part { part = .text(text, size: newSize) }
                        }
                    })
                ) {
                    Text("小").tag(TextSize.small)
                    Text("中").tag(TextSize.medium)
                    Text("大").tag(TextSize.large)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("textSizePicker")
            case .markdown(_, _, let asPlainText):
                Text("markdown の設定").bold()
                Toggle("プレーンテキストとして組む", isOn: Binding(
                    get: { asPlainText },
                    set: { plain in
                        model.update(entry.id) { part in
                            if case .markdown(let text, let baseURL, _) = part {
                                part = .markdown(text, baseURL: baseURL, asPlainText: plain)
                            }
                        }
                    })
                )
                .accessibilityIdentifier("plainTextToggle")
            case .card(let card):
                Text("カードの設定").bold()
                Text(card.note ?? "設定できる項目はありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slider(
        _ title: String, value: Double, range: ClosedRange<Double>, id: String,
        set: @escaping (inout PhotoSettings, Double) -> Void
    ) -> some View {
        HStack {
            Text(title)
            Slider(value: Binding(get: { value }, set: { new in updateSettings { set(&$0, new) } }), in: range)
                .accessibilityIdentifier(id)
            Text(String(format: "%.2f", value)).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }

    private func updateSettings(_ change: @escaping (inout PhotoSettings) -> Void) {
        model.update(entry.id) { part in
            if case .image(let data, var settings) = part {
                change(&settings)
                part = .image(data, settings)
            }
        }
    }

    private static func rotated(_ rotation: ImageRotation) -> ImageRotation {
        ImageRotation(rawValue: (rotation.rawValue + 90) % 360) ?? .degrees0
    }
}
