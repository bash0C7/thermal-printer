import Foundation

public enum SummaryKind: Sendable, Hashable {
    case overview
    case comment

    public var characterLimit: Int {
        switch self {
        case .overview: 60
        case .comment: 40
        }
    }

    public var lineLimit: Int {
        switch self {
        case .overview: 3
        case .comment: 2
        }
    }

    var hardCharacterLimit: Int { characterLimit * 3 / 2 }

    func fit(_ modelOutput: String) -> String {
        let lines = modelOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.prefix(lineLimit).joined(separator: "\n")
        guard joined.count > hardCharacterLimit else { return joined }
        return String(joined.prefix(hardCharacterLimit)) + "…"
    }
}

public struct Summary: Sendable, Equatable {
    public let text: String
    public let usedModel: Bool
    public let fallbackReason: String?

    public init(text: String, usedModel: Bool, fallbackReason: String? = nil) {
        self.text = text
        self.usedModel = usedModel
        self.fallbackReason = fallbackReason
    }
}

public protocol Summarizer: Sendable {
    func summarize(_ text: String, kind: SummaryKind) async -> Summary
}

public struct SummarizerSelector: Sendable {
    public let summarizer: any Summarizer

    public init(modelAvailable: Bool) {
        summarizer = modelAvailable ? FoundationModelSummarizer() : TruncatingSummarizer()
    }

    public init() {
        self.init(modelAvailable: FoundationModelSummarizer.isAvailable)
    }
}
