import PhotosUI
import SwiftUI
import ThermalPrinterCore
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PhoneModel.self) private var model
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false

    var body: some View {
        NavigationStack {
            List {
                draftSection
                remindersSection
                partsSection
                previewSection
            }
            .navigationTitle("サーマルプリンター")
            .task { await model.loadReminders() }
            .fileImporter(
                isPresented: $importingFile,
                allowedContentTypes: [.plainText, .image, UTType(filenameExtension: "md") ?? .plainText]
            ) { model.picked(files: $0.map { [$0] }) }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                model.picked(photo: item)
                photo = nil
            }
        }
    }

    private var draftSection: some View {
        @Bindable var model = model
        return Section("テキスト") {
            TextEditor(text: Binding(get: { model.draftText }, set: { model.edit($0) }))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .accessibilityIdentifier("draftEditor")
            HStack {
                PasteButton(supportedContentTypes: [.image, .plainText]) { model.pasted($0) }
                PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                Button { importingFile = true } label: { Image(systemName: "doc") }
                Spacer()
                Button("クリア", role: .destructive) { model.clearDraft() }
                    .disabled(model.draftText.isEmpty)
            }
            .buttonStyle(.bordered)
            Button {
                model.digest()
            } label: {
                if model.isDigesting {
                    ProgressView()
                } else {
                    Label("見出しと要約にして、原文をQRに圧縮", systemImage: "wand.and.stars")
                }
            }
            .disabled(!model.canDigest)
            .accessibilityIdentifier("digestButton")
        }
    }

    private var remindersSection: some View {
        Section("リマインダー") {
            if let message = model.remindersMessage {
                Text(message).foregroundStyle(.secondary)
            }
            ForEach(model.reminders, id: \.title) { item in
                Toggle(isOn: Binding(
                    get: { model.isChecked(PhoneModel.key(item)) },
                    set: { model.setReminder(item, checked: $0) })
                ) {
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text(item.list).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var partsSection: some View {
        Section("部品") {
            ForEach(model.parts) { entry in
                Text(entry.part.title)
            }
            .onDelete { offsets in
                for index in offsets { model.remove(model.parts[index].id) }
            }
        }
    }

    private var previewSection: some View {
        Section("プレビュー") {
            if let image = model.preview {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .accessibilityIdentifier("previewImage")
                Text(model.lengthText).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("プレビューはまだありません").foregroundStyle(.secondary)
            }
            Button {
                Task { await model.printStrip() }
            } label: {
                if model.isPrinting { ProgressView() } else { Label("印刷", systemImage: "printer") }
            }
            .disabled(!model.canPrint)
            .accessibilityIdentifier("printButton")
            if let banner = model.banner {
                Text(banner).font(.callout).accessibilityIdentifier("messageLabel")
            }
        }
    }
}

extension Part {
    var title: String {
        switch self {
        case .text(let text, _), .markdown(let text, _, _): String(text.prefix(60))
        case .image: "画像"
        case .card(let card): card.title
        }
    }
}
