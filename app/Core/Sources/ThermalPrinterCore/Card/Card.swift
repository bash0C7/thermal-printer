import Foundation

public struct Card: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case github
        case slack
        case url
        case reminder
        case memo
    }

    public struct Header: Codable, Equatable, Sendable {
        public var lines: [String]
        public var emphasis: String?
        public var sublines: [String]

        public init(lines: [String], emphasis: String? = nil, sublines: [String] = []) {
            self.lines = lines
            self.emphasis = emphasis
            self.sublines = sublines
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(lines, forKey: .lines)
            try container.encode(emphasis, forKey: .emphasis)
            try container.encode(sublines, forKey: .sublines)
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public var label: String?
        public var text: String

        public init(label: String? = nil, text: String) {
            self.label = label
            self.text = text
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(text, forKey: .text)
        }
    }

    public var version: Int
    public var kind: Kind
    public var url: String?
    public var header: Header
    public var title: String
    public var sections: [Section]
    public var note: String?
    public var qr: String?

    public init(
        version: Int = 1, kind: Kind, url: String?, header: Header,
        title: String, sections: [Section] = [], note: String? = nil, qr: String? = nil
    ) {
        self.version = version
        self.kind = kind
        self.url = url
        self.header = header
        self.title = title
        self.sections = sections
        self.note = note
        self.qr = qr
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(kind, forKey: .kind)
        try container.encode(url, forKey: .url)
        try container.encode(header, forKey: .header)
        try container.encode(title, forKey: .title)
        try container.encode(sections, forKey: .sections)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(qr, forKey: .qr)
    }
}
