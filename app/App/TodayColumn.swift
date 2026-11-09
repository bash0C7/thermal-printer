import SwiftUI
import ThermalPrinterCore

struct TodayColumn: View {
    @Environment(AppModel.self) private var model
    @State private var urlText = ""

    private var githubHeading: String {
        guard let repo = model.repoFilter else { return "GitHub（自分 assign・レビュー依頼・open）" }
        return "GitHub（\(repo.nameWithOwner)）"
    }

    private static func caption(for task: TaskNote, now: Date) -> String {
        let dates = [
            task.scheduled.map { "予定 " + ReminderCard.dateText($0, hasTime: task.scheduledHasTime, now: now) },
            task.due.map { "期限 " + ReminderCard.dateText($0, hasTime: task.dueHasTime, now: now) },
        ].compactMap { $0 }
        return ([task.status] + dates).joined(separator: " ・ ")
    }

    var body: some View {
        List {
            Section(githubHeading) {
                TextField("URL を直接指定（GitHub 以外も取り込み・要約）", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let text = urlText
                        urlText = ""
                        Task { await model.receive(PasteboardContent(text: text)) }
                    }
                    .accessibilityIdentifier("urlField")
                TextField("repo（owner/repo か URL。空なら全 repo）", text: Binding(get: { model.repoText }, set: { model.repoText = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.applyRepoText(model.repoText) } }
                    .accessibilityIdentifier("repoField")
                if let message = model.repoMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("repoMessage")
                }
                if model.issuesLoading {
                    ProgressView().controlSize(.small)
                }
                ForEach(model.issues) { issue in
                    Toggle(isOn: Binding(
                        get: { model.isChecked(issue.id) },
                        set: { model.setIssue(issue, checked: $0) })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.label).font(.caption.bold())
                            Text(issue.title).lineLimit(2)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("todayIssue-\(issue.number)")
                }
                if let message = model.issuesMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("issuesMessage")
                }
            }
            Section("リマインダー（今日以降・期限の昇順）") {
                if !model.reminderLists.isEmpty {
                    Picker("リスト", selection: Binding(
                        get: { model.reminderList },
                        set: { model.selectReminderList($0) })
                    ) {
                        Text("すべてのリスト").tag(String?.none)
                        ForEach(model.reminderLists, id: \.self) { list in
                            Text(list).tag(Optional(list))
                        }
                    }
                    .accessibilityIdentifier("reminderListPicker")
                }
                if model.remindersLoading {
                    ProgressView().controlSize(.small)
                }
                ForEach(model.reminders) { reminder in
                    Toggle(isOn: Binding(
                        get: { model.isChecked(reminder.id) },
                        set: { model.setReminder(reminder, checked: $0) })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.item.title).lineLimit(2)
                            Text(reminder.item.list).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("todayReminder-\(reminder.item.title)")
                }
                if let message = model.remindersMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("remindersMessage")
                }
                if model.remindersNeedAccess {
                    Button("許可して読み込む") {
                        Task { await model.loadReminders(requestAccess: true) }
                    }
                    .accessibilityIdentifier("allowRemindersButton")
                }
            }
            Section("TaskForge（未完了）") {
                if model.tasksLoading {
                    ProgressView().controlSize(.small)
                }
                ForEach(model.tasks, id: \.id) { task in
                    Toggle(isOn: Binding(
                        get: { model.isChecked(task.id) },
                        set: { model.setTask(task, checked: $0) })
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).lineLimit(2)
                            Text(Self.caption(for: task, now: Date())).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("todayTask-\(task.title)")
                }
                if let message = model.tasksMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tasksMessage")
                }
            }
        }
        .accessibilityIdentifier("todayList")
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.refreshToday() }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }
            .disabled(model.issuesLoading || model.remindersLoading || model.tasksLoading)
            .padding(8)
            .accessibilityIdentifier("refreshTodayButton")
        }
    }
}
