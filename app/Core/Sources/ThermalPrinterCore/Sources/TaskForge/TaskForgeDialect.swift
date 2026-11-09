import Foundation

public struct TaskForgeDialect: Equatable, Sendable {
    public struct Fields: Equatable, Sendable {
        public var status: String
        public var priority: String
        public var due: String
        public var scheduled: String
        public var projects: String
        public var id: String
    }

    public var folder: String
    public var fields: Fields

    public static let standard = TaskForgeDialect(
        folder: "00_TaskNotes",
        fields: Fields(status: "status", priority: "priority", due: "due",
                       scheduled: "scheduled", projects: "projects", id: "id")
    )

    public static func load(vault: URL) -> TaskForgeDialect {
        let url = vault.appending(path: "TaskForge/Settings/dialect.json")
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(DialectFile.self, from: data)
        else { return .standard }
        return file.tasknotes.dialect
    }
}

private struct DialectFile: Decodable {
    struct FieldNames: Decodable {
        let status, priority, due, scheduled, projects: String
        let userTaskID: String

        enum CodingKeys: String, CodingKey {
            case status, priority, due, scheduled, projects
            case userTaskID = "user_task_id"
        }
    }

    struct TaskNotes: Decodable {
        let folder: String
        let fieldNames: FieldNames

        enum CodingKeys: String, CodingKey {
            case folder
            case fieldNames = "field_names"
        }

        var dialect: TaskForgeDialect {
            TaskForgeDialect(
                folder: folder,
                fields: .init(status: fieldNames.status, priority: fieldNames.priority, due: fieldNames.due,
                              scheduled: fieldNames.scheduled, projects: fieldNames.projects, id: fieldNames.userTaskID)
            )
        }
    }

    let tasknotes: TaskNotes
}
