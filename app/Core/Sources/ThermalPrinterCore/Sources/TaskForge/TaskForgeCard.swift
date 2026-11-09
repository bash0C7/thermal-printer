import Foundation

public enum TaskForgeLink {
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func url(for task: TaskNote, vaultName: String) -> String {
        if let stableID = task.stableID {
            return "taskforge:///task/" + encoded(stableID)
        }
        let file = task.relativePath.hasSuffix(".md") ? String(task.relativePath.dropLast(3)) : task.relativePath
        return "obsidian://open?vault=" + encoded(vaultName) + "&file=" + encoded(file)
    }

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }
}

public enum TaskForgeCard {
    public static let qrOmittedNote = "リンクが長く QR に入らないため、QR を省いています"

    public static func make(
        _ task: TaskNote, vaultName: String, now: Date, calendar: Calendar = .current, summarizer: any Summarizer
    ) async -> Card {
        let link = TaskForgeLink.url(for: task, vaultName: vaultName)
        let linkFits = QRCode.moduleCount(for: link).map { $0 <= QRPayload.maxCardModules } ?? false
        let header = Card.Header(
            lines: [task.projects.isEmpty ? "TaskForge" : task.projects.joined(separator: " ・ ")],
            emphasis: task.status,
            sublines: sublines(task, now: now, calendar: calendar))
        let text = [task.title, task.body].filter { !$0.isEmpty }.joined(separator: "\n")

        var notes = linkFits ? [] : [qrOmittedNote]
        var title = "☐ " + task.title
        var sections = task.body.isEmpty ? [] : [Card.Section(text: task.body)]
        if text.count > SummaryKind.heading.characterLimit {
            let digest = await TextDigest.make(text, summarizer: summarizer)
            title = "☐ " + (digest.heading.text.isEmpty ? task.title : digest.heading.text)
            sections = digest.sections
            if digest.usedFallback { notes.insert(GitHubHandler.fallbackNote, at: 0) }
        }
        return Card(
            kind: .task, url: linkFits ? link : nil, header: header, title: title, sections: sections,
            note: notes.isEmpty ? nil : notes.joined(separator: "\n"))
    }

    private static func sublines(_ task: TaskNote, now: Date, calendar: Calendar) -> [String] {
        let scheduled = task.scheduled.map {
            "予定 " + ReminderCard.dateText($0, hasTime: task.scheduledHasTime, now: now, calendar: calendar)
        }
        let due = task.due.map {
            "期限 " + ReminderCard.dateText($0, hasTime: task.dueHasTime, now: now, calendar: calendar)
        }
        return [scheduled, due].compactMap { $0 }
    }
}
