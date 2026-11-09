import Foundation

public struct TaskNote: Equatable, Sendable {
    public var title: String
    public var relativePath: String
    public var status: String
    public var priority: String?
    public var due: Date?
    public var dueHasTime: Bool
    public var scheduled: Date?
    public var scheduledHasTime: Bool
    public var projects: [String]
    public var stableID: String?
    public var body: String

    public static func parse(
        relativePath: String, contents: String, dialect: TaskForgeDialect, calendar: Calendar = .current
    ) -> TaskNote? {
        guard let (frontmatter, body) = Frontmatter.split(contents),
              let status = frontmatter.scalar(dialect.fields.status)
        else { return nil }
        let due = frontmatter.scalar(dialect.fields.due).flatMap { TaskDate.parse($0, calendar: calendar) }
        let scheduled = frontmatter.scalar(dialect.fields.scheduled).flatMap { TaskDate.parse($0, calendar: calendar) }
        return TaskNote(
            title: title(of: relativePath),
            relativePath: relativePath,
            status: status,
            priority: frontmatter.scalar(dialect.fields.priority),
            due: due?.date,
            dueHasTime: due?.hasTime ?? false,
            scheduled: scheduled?.date,
            scheduledHasTime: scheduled?.hasTime ?? false,
            projects: frontmatter.list(dialect.fields.projects).map(wikilinkTarget),
            stableID: frontmatter.scalar(dialect.fields.id),
            body: body
        )
    }

    private static func title(of relativePath: String) -> String {
        let name = (relativePath as NSString).lastPathComponent
        return name.hasSuffix(".md") ? String(name.dropLast(3)) : name
    }

    private static func wikilinkTarget(_ link: String) -> String {
        guard link.hasPrefix("[["), link.hasSuffix("]]") else { return link }
        return String(link.dropFirst(2).dropLast(2))
    }
}

private struct Frontmatter {
    private var scalars: [String: String] = [:]
    private var lists: [String: [String]] = [:]

    func scalar(_ key: String) -> String? {
        scalars[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    func list(_ key: String) -> [String] {
        lists[key] ?? scalar(key).map { [$0] } ?? []
    }

    static func split(_ contents: String) -> (Frontmatter, body: String)? {
        let withoutBOM = contents.hasPrefix("\u{FEFF}") ? String(contents.dropFirst()) : contents
        let lines = withoutBOM.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard lines.first.map(isDelimiter) == true,
              let closing = lines.dropFirst().firstIndex(where: isDelimiter)
        else { return nil }
        let body = lines[(closing + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (Frontmatter(lines: lines[1..<closing]), body)
    }

    private static func isDelimiter(_ line: String) -> Bool {
        line.hasPrefix("---") && line.dropFirst(3).allSatisfy { $0 == " " }
    }

    private init(lines: ArraySlice<String>) {
        var listKey: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let listKey, trimmed.hasPrefix("- ") {
                lists[listKey, default: []].append(Self.unquoted(String(trimmed.dropFirst(2))))
                continue
            }
            guard !line.hasPrefix(" "), let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            listKey = value.isEmpty ? key : nil
            scalars[key] = Self.unquoted(value)
        }
    }

    private static func unquoted(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == trimmed.last, first == "\"" || first == "'"
        else { return trimmed }
        return String(trimmed.dropFirst().dropLast())
    }
}

private enum TaskDate {
    static func parse(_ text: String, calendar: Calendar) -> (date: Date, hasTime: Bool)? {
        let halves = text.split(separator: "T", maxSplits: 1).map(String.init)
        guard let day = halves.first.flatMap(dayComponents) else { return nil }
        guard halves.count == 2 else { return calendar.date(from: day).map { ($0, false) } }
        let time = halves[1]
        if time.contains(where: { "Z+-".contains($0) }) {
            return zoned(text).map { ($0, true) }
        }
        let clock = time.split(separator: ":").compactMap { Int($0) }
        guard clock.count >= 2 else { return nil }
        var components = day
        components.hour = clock[0]
        components.minute = clock[1]
        components.second = clock.count > 2 ? clock[2] : 0
        return calendar.date(from: components).map { ($0, true) }
    }

    private static func dayComponents(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func zoned(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}
