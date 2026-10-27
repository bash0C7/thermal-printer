import SwiftUI
import ThermalPrinterCore

struct TodayColumn: View {
    @Environment(AppModel.self) private var model
    @State private var urlText = ""

    var body: some View {
        List {
            Section("URL と GitHub（自分 assign・open の issue と PR）") {
                TextField("URL を直接指定（GitHub 以外も取り込み・要約）", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let text = urlText
                        urlText = ""
                        Task { await model.receive(PasteboardContent(text: text)) }
                    }
                    .accessibilityIdentifier("urlField")
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
            Section("リマインダー（今日以降）") {
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
        }
        .accessibilityIdentifier("todayList")
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.refreshToday() }
            } label: {
                Label("更新", systemImage: "arrow.clockwise")
            }
            .disabled(model.issuesLoading || model.remindersLoading)
            .padding(8)
            .accessibilityIdentifier("refreshTodayButton")
        }
    }
}
