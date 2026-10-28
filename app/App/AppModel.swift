import AppKit
import Foundation
import Observation
import ThermalPrinterCore

struct PartEntry: Identifiable, Equatable {
    let id = UUID()
    var part: Part
    var todayKey: String?
}

struct StripPreview: Sendable {
    let strip: ComposedStrip
}

struct Banner: Equatable {
    enum Kind {
        case success
        case warning
        case failure
    }

    var kind: Kind
    var text: String
}

@MainActor
@Observable
final class AppModel {
    static let thresholdDefaultsKey = "lengthThresholdCentimeters"
    static let densityRange = 1...5
    static let defaultDensity = 4

    var parts: [PartEntry] = []
    var selection: PartEntry.ID?
    private(set) var preview: StripPreview?
    var scale: PhysicalScale = .fallback

    var density = AppModel.defaultDensity
    private(set) var thresholdCentimeters: Double

    private(set) var issues: [TodayIssue] = []
    private(set) var issuesMessage: String?
    private(set) var issuesLoading = false
    private(set) var reminders: [TodayReminder] = []
    private(set) var remindersMessage: String?
    private(set) var remindersLoading = false
    private(set) var remindersNeedAccess = false
    private(set) var pendingKeys: Set<String> = []
    private(set) var pendingCards = 0

    private(set) var draft = DraftDocument(
        directory: FileManager.default.temporaryDirectory.appending(path: "thermal-printer-draft-\(UUID().uuidString)"))
    private(set) var isDigesting = false

    private(set) var status: PrinterStatusSnapshot?
    private(set) var isRefreshingStatus = false
    private(set) var isPrinting = false
    var banner: Banner?
    var confirmingLongPrint = false

    @ObservationIgnored private let launch: PrinterLaunch
    @ObservationIgnored let previews: PreviewCoordinator
    @ObservationIgnored private let runner: any ProcessRunner = SystemProcessRunner()
    @ObservationIgnored private let composer = StripComposer()
    @ObservationIgnored private var composeGeneration = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private let summarizer = SummarizerSelector().summarizer
    @ObservationIgnored private lazy var registry = URLHandlerRegistry.standard(
        runner: runner, summarizer: summarizer)
    @ObservationIgnored private var draftRecompose: Task<Void, Never>?

    static let draftDebounce = Duration.milliseconds(350)

    static var defaultLaunch: PrinterLaunch {
        #if DEBUG
        return .resolving()
        #else
        return .bundled()
        #endif
    }

    init(launch: PrinterLaunch = AppModel.defaultLaunch) {
        self.launch = launch
        self.previews = PreviewCoordinator(client: PrinterClient(launch: launch))
        let saved = UserDefaults.standard.double(forKey: Self.thresholdDefaultsKey)
        self.thresholdCentimeters = saved > 0 ? saved : LengthPolicy.defaultThresholdCentimeters
    }

    var policy: LengthPolicy { LengthPolicy(thresholdCentimeters: thresholdCentimeters) }
    var rows: Int { preview?.strip.bitmap.height ?? 0 }
    var lengthText: String { LengthPolicy.lengthText(rows: rows) }
    var lengthWarning: String? { policy.warningText(rows: rows) }
    var printGate: PrintGate {
        PrintGate(
            previewReady: previews.readyPreview != nil, rows: rows, isPrinting: isPrinting,
            isRefreshingStatus: isRefreshingStatus, pendingCards: pendingCards)
    }
    var canPrint: Bool { printGate.canPrint }
    var cliAvailable: Bool { FileManager.default.isExecutableFile(atPath: launch.executable.path) }

    func setThreshold(_ centimeters: Double) {
        thresholdCentimeters = centimeters
        UserDefaults.standard.set(centimeters, forKey: Self.thresholdDefaultsKey)
    }

    func start() async {
        guard !started else { return }
        started = true
        async let printer: Void = refreshStatus()
        async let today: Void = refreshToday(requestRemindersAccess: false)
        _ = await (printer, today)
    }

    func add(_ part: Part, todayKey: String? = nil) {
        let entry = PartEntry(part: part, todayKey: todayKey)
        parts.append(entry)
        selection = entry.id
        recompose()
    }

    func remove(ids: Set<PartEntry.ID>) {
        parts.removeAll { ids.contains($0.id) }
        if let selection, ids.contains(selection) { self.selection = nil }
        recompose()
    }

    func removeSelected() {
        guard let selection else { return }
        remove(ids: [selection])
    }

    func move(from source: IndexSet, to destination: Int) {
        parts.move(fromOffsets: source, toOffset: destination)
        recompose()
    }

    func update(_ id: PartEntry.ID, _ change: (inout Part) -> Void) {
        guard let index = parts.firstIndex(where: { $0.id == id }) else { return }
        change(&parts[index].part)
        recompose()
    }

    func receive(_ content: PasteboardContent) async {
        let items = PasteRouter.items(from: content)
        if items.isEmpty {
            banner = Banner(kind: .warning, text: "貼り付けられる内容がありません")
            return
        }
        var rejections: [String] = []
        for item in items {
            switch item {
            case .part(let part):
                add(part)
            case .cardURL(let text):
                guard let url = URL(string: text) else { continue }
                pendingCards += 1
                let card = await registry.card(for: url)
                pendingCards -= 1
                add(.card(card))
            case .rejected(let message):
                rejections.append(message)
            }
        }
        if !rejections.isEmpty {
            banner = Banner(kind: .failure, text: rejections.joined(separator: "\n"))
        }
    }

    func receive(providers: [NSItemProvider]) {
        Task { await receive(PasteLoader.load(providers)) }
    }

    func receive(photos: [ImportedPhoto]) {
        for photo in photos { add(.image(photo.data)) }
    }

    var draftText: String { draft.text }

    var canDigestDraft: Bool { !isDigesting && draft.canDigest }

    func draftEdited(_ text: String) {
        draft.edit(text)
        previews.invalidate()
        draftRecompose?.cancel()
        draftRecompose = Task {
            do {
                try await Task.sleep(for: Self.draftDebounce)
            } catch {
                return
            }
            recompose()
        }
    }

    func addDraftImage(_ data: Data) -> String? {
        do {
            return try draft.addImage(data)
        } catch {
            banner = Banner(kind: .failure, text: "画像を保存できません（\(error.localizedDescription)）")
            return nil
        }
    }

    func digestDraft() {
        guard canDigestDraft else { return }
        let source = draft.text
        isDigesting = true
        pendingCards += 1
        Task {
            let card = await MemoCard.make(Draft.plainText(source), summarizer: summarizer)
            pendingCards -= 1
            isDigesting = false
            draft.apply(card, to: source)
            recompose()
        }
    }

    func clearDraft() {
        draft.clear()
        recompose()
    }

    func isChecked(_ key: String) -> Bool {
        pendingKeys.contains(key) || parts.contains { $0.todayKey == key }
    }

    func setIssue(_ issue: TodayIssue, checked: Bool) {
        let key = issue.id
        guard checked else {
            uncheck(key)
            return
        }
        guard let url = URL(string: issue.url), !isChecked(key) else { return }
        pendingKeys.insert(key)
        Task {
            let card = await registry.card(for: url)
            guard pendingKeys.remove(key) != nil else { return }
            add(.card(card), todayKey: key)
        }
    }

    func setReminder(_ reminder: TodayReminder, checked: Bool) {
        let key = reminder.id
        guard checked else {
            uncheck(key)
            return
        }
        guard !isChecked(key) else { return }
        add(.card(ReminderCard.make(reminder.item, now: Date())), todayKey: key)
    }

    func refreshToday(requestRemindersAccess: Bool = true) async {
        async let github: Void = loadIssues()
        async let reminders: Void = loadReminders(requestAccess: requestRemindersAccess)
        _ = await (github, reminders)
    }

    func loadReminders(requestAccess: Bool) async {
        guard requestAccess || TodayLoader.remindersAuthorized else {
            remindersNeedAccess = true
            reminders = []
            remindersMessage = "リマインダーの読み取りが未許可です"
            return
        }
        remindersNeedAccess = false
        remindersLoading = true
        defer { remindersLoading = false }
        do {
            reminders = try await TodayLoader.reminders()
            remindersMessage = reminders.isEmpty ? "今日以降のリマインダーはありません" : nil
        } catch RemindersSource.Failure.accessDenied {
            reminders = []
            remindersMessage = "リマインダーへのアクセスが許可されていません。システム設定の「プライバシーとセキュリティ」で許可してください"
        } catch {
            reminders = []
            remindersMessage = error.localizedDescription
        }
    }

    func refreshStatus() async {
        guard !isRefreshingStatus, !isPrinting else { return }
        guard cliAvailable else {
            status = PrinterStatusSnapshot(
                line: "プリンター連携なし", detail: "同梱のpicorubyが見つかりません（\(launch.executable.path)）")
            return
        }
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }
        status = await PrinterClient(launch: launch).refreshStatus(previous: status)
    }

    func requestPrint() {
        switch printGate.decision(policy: policy) {
        case .ignore: return
        case .confirmLongPrint: confirmingLongPrint = true
        case .printNow: Task { await printStrip() }
        }
    }

    func printStrip() async {
        guard canPrint else { return }
        guard cliAvailable else {
            banner = Banner(kind: .failure, text: "印刷用のCLIが見つかりません（\(launch.executable.path)）")
            return
        }
        isPrinting = true
        banner = nil
        let printedLength = lengthText
        do {
            let result = try await previews.printReady(density: density)
            banner = Self.banner(for: result, lengthText: printedLength)
        } catch {
            banner = Banner(kind: .failure, text: error.localizedDescription)
        }
        isPrinting = false
        await refreshStatus()
    }

    static func banner(for result: PrintResult, lengthText: String) -> Banner {
        guard result.ok else {
            return Banner(kind: .failure, text: PrinterStatusText.message(for: result.error ?? .unknown))
        }
        if result.warnings.isEmpty {
            return Banner(kind: .success, text: "印刷しました（\(lengthText)）")
        }
        let warnings = result.warnings.map(PrinterStatusText.warningMessage).joined(separator: "\n")
        return Banner(kind: .warning, text: "印刷しました（\(lengthText)）\n\(warnings)")
    }

    private func uncheck(_ key: String) {
        pendingKeys.remove(key)
        let ids = Set(parts.filter { $0.todayKey == key }.map(\.id))
        if !ids.isEmpty { remove(ids: ids) }
    }

    private func loadIssues() async {
        issuesLoading = true
        defer { issuesLoading = false }
        do {
            issues = try await TodayLoader.issues(runner: runner)
            issuesMessage = issues.isEmpty ? "自分に assign された open の issue と PR はありません" : nil
        } catch {
            issues = []
            issuesMessage = error.localizedDescription
        }
    }

    private func recompose() {
        composeGeneration += 1
        let generation = composeGeneration
        previews.invalidate()
        let snapshot = parts.map(\.part) + draft.parts
        let composer = composer
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StripPreview(strip: composer.compose(snapshot))
            }.value
            guard generation == composeGeneration else { return }
            preview = result
            if cliAvailable {
                previews.update(result.strip.bitmap)
            } else {
                previews.fail("印刷用のCLIが見つかりません（\(launch.executable.path)）")
            }
            if let failure = result.strip.failures.first {
                banner = Banner(kind: .warning, text: failure.message)
            }
        }
    }
}
