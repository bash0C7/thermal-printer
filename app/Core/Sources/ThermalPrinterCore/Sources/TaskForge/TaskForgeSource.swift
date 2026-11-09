import Foundation

public enum TaskForgeSourceError: Error, LocalizedError, Equatable {
    case vaultMissing(String)

    public var errorDescription: String? {
        switch self {
        case .vaultMissing(let path): "vault が見つかりません（\(path)）"
        }
    }
}

extension TaskNote {
    public var id: String { "task:\(relativePath)" }
}

public enum TaskForgeSource {
    public static let excludedStatuses: Set<String> = ["done", "cancelled"]

    public static func openTasks(vault: URL, fileManager: FileManager = .default) throws -> [TaskNote] {
        guard fileManager.fileExists(atPath: vault.path) else {
            throw TaskForgeSourceError.vaultMissing(vault.path)
        }
        let dialect = TaskForgeDialect.load(vault: vault)
        let folder = vault.appending(path: dialect.folder, directoryHint: .isDirectory)
        let fileNames = try fileManager.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }
        let notes = fileNames.compactMap { name -> TaskNote? in
            guard let contents = try? String(contentsOf: folder.appending(path: name), encoding: .utf8) else { return nil }
            return TaskNote.parse(relativePath: "\(dialect.folder)/\(name)", contents: contents, dialect: dialect)
        }
        return sorted(notes.filter(isOpen))
    }

    public static func vaultPath(from typed: String) -> String {
        (typed.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    static func isOpen(_ note: TaskNote) -> Bool {
        !excludedStatuses.contains(note.status)
    }

    public static let statusOrder = [
        "open", "in-progress", "on-hold", "planned", "deferred", "blocked", "someday", "ready",
    ]

    static func sorted(_ notes: [TaskNote]) -> [TaskNote] {
        notes.sorted { lhs, rhs in
            if statusRank(lhs) != statusRank(rhs) { return statusRank(lhs) < statusRank(rhs) }
            if lhs.due != rhs.due { return earlier(lhs.due, rhs.due) }
            if lhs.scheduled != rhs.scheduled { return earlier(lhs.scheduled, rhs.scheduled) }
            return lhs.title < rhs.title
        }
    }

    private static func statusRank(_ note: TaskNote) -> Int {
        statusOrder.firstIndex(of: note.status) ?? statusOrder.count
    }

    private static func earlier(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (let l?, let r?): l < r
        case (_?, nil): true
        default: false
        }
    }
}
