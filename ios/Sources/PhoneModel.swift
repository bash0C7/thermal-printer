import Foundation
import Observation
import PhotosUI
import SwiftUI
import ThermalPrinterCore
import UIKit

struct PhonePart: Identifiable, Equatable {
    let id = UUID()
    let part: Part
    let reminderKey: String?
}

@MainActor
@Observable
final class PhoneModel {
    static let density = 4
    static let draftDebounce = Duration.milliseconds(350)

    private(set) var parts: [PhonePart] = []
    private(set) var draft = DraftDocument(
        directory: FileManager.default.temporaryDirectory.appending(path: "thermal-printer-draft-\(UUID().uuidString)"))
    private(set) var isDigesting = false
    private(set) var preview: UIImage?
    private(set) var rows = 0
    private(set) var reminders: [ReminderItem] = []
    private(set) var remindersMessage: String?
    private(set) var isPrinting = false
    var banner: String?

    @ObservationIgnored private let summarizer = SummarizerSelector().summarizer
    @ObservationIgnored private let composer = StripComposer()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var recomposeTask: Task<Void, Never>?

    var lengthText: String { LengthPolicy.lengthText(rows: rows) }
    var canPrint: Bool { rows > 0 && !isPrinting }
    var canDigest: Bool { !isDigesting && draft.canDigest }

    func edit(_ text: String) {
        draft.edit(text)
        recompose(after: Self.draftDebounce)
    }

    func clearDraft() {
        draft.clear()
        recompose()
    }

    func digest() {
        guard canDigest else { return }
        let source = draft.text
        isDigesting = true
        Task {
            let card = await MemoCard.make(Draft.plainText(source), summarizer: summarizer)
            isDigesting = false
            draft.apply(card, to: source)
            recompose()
        }
    }

    func appendToDraft(image data: Data) {
        do {
            append(try draft.addImage(data))
        } catch {
            banner = "画像を保存できません（\(error.localizedDescription)）"
        }
    }

    func append(_ text: String) {
        let separator = draft.text.isEmpty || draft.text.hasSuffix("\n") ? "" : "\n"
        edit(draft.text + separator + text + "\n")
    }

    func pasted(_ providers: [NSItemProvider]) {
        Task {
            for provider in providers {
                if let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: { $0.conforms(to: .image) }),
                    let data = await Self.data(of: provider, type: type) {
                    appendToDraft(image: data)
                } else if provider.canLoadObject(ofClass: String.self), let text = await Self.text(of: provider) {
                    append(text)
                }
            }
        }
    }

    func picked(photo item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) { appendToDraft(image: data) }
        }
    }

    func picked(files result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            banner = error.localizedDescription
        case .success(let urls):
            let content = PasteboardContent(fileURLs: urls)
            for item in PasteRouter.items(from: content, readFile: Self.readScoped) {
                switch item {
                case .part(let part): add(part)
                case .rejected(let message): banner = message
                case .cardURL: break
                }
            }
        }
    }

    func add(_ part: Part, reminderKey: String? = nil) {
        parts.append(PhonePart(part: part, reminderKey: reminderKey))
        recompose()
    }

    func remove(_ id: PhonePart.ID) {
        parts.removeAll { $0.id == id }
        recompose()
    }

    func isChecked(_ key: String) -> Bool {
        parts.contains { $0.reminderKey == key }
    }

    func setReminder(_ item: ReminderItem, checked: Bool) {
        let key = item.key
        if checked {
            guard !isChecked(key) else { return }
            add(.card(ReminderCard.make(item, now: Date())), reminderKey: key)
        } else if let existing = parts.first(where: { $0.reminderKey == key }) {
            remove(existing.id)
        }
    }

    func loadReminders() async {
        do {
            reminders = try await RemindersSource(store: EventKitRemindersStore()).todaysReminders()
            remindersMessage = reminders.isEmpty ? "今日以降のリマインダーはありません" : nil
        } catch RemindersSource.Failure.accessDenied {
            reminders = []
            remindersMessage = "リマインダーへのアクセスが許可されていません。設定アプリで許可してください"
        } catch {
            reminders = []
            remindersMessage = error.localizedDescription
        }
    }

    func printStrip() async {
        guard canPrint else { return }
        isPrinting = true
        banner = nil
        let length = lengthText
        let snapshot = parts.map(\.part) + draft.parts
        let bitmap = composer.compose(snapshot).bitmap
        do {
            let result = try await VMPrinter.shared.print(bitmap, density: Self.density)
            banner = result.ok
                ? "印刷しました（\(length)）"
                : PrinterStatusText.message(for: result.error ?? .unknown)
        } catch {
            banner = error.localizedDescription
        }
        isPrinting = false
    }

    private func recompose(after delay: Duration = .zero) {
        recomposeTask?.cancel()
        generation += 1
        let current = generation
        let snapshot = parts.map(\.part) + draft.parts
        let composer = composer
        recomposeTask = Task {
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            let strip = await Task.detached(priority: .userInitiated) { composer.compose(snapshot) }.value
            guard current == generation else { return }
            rows = strip.bitmap.height
            preview = (try? PNGWriter.data(strip.bitmap)).flatMap(UIImage.init(data:))
            if let failure = strip.failures.first { banner = failure.message }
        }
    }

    private static let readScoped: @Sendable (URL) throws -> Data = { url in
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    private static func data(of provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func text(of provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}

extension ReminderItem {
    var key: String { "\(list)|\(title)|\(due?.timeIntervalSince1970 ?? 0)" }
}
