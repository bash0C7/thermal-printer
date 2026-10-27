import Foundation

public struct TextDigest: Sendable {
    static let modelInputLimit = 4000

    public let heading: Summary
    public let digest: Summary

    public var usedFallback: Bool { !heading.usedModel || !digest.usedModel }

    public static func make(_ text: String, summarizer: any Summarizer) async -> TextDigest {
        let body = String(text.prefix(modelInputLimit))
        async let heading = summarizer.summarize(body, kind: .heading)
        async let digest = summarizer.summarize(body, kind: .digest)
        return await TextDigest(heading: heading, digest: digest)
    }

    var sections: [Card.Section] {
        digest.text.isEmpty ? [] : [Card.Section(text: digest.text)]
    }
}

public enum MemoCard {
    public static func make(_ text: String, summarizer: any Summarizer) async -> Card {
        let digest = await TextDigest.make(text, summarizer: summarizer)
        let packed = QRPayload.pack(text)

        var notes: [String] = []
        if digest.usedFallback { notes.append(GitHubHandler.fallbackNote) }
        if !packed.isComplete {
            notes.append("QRには全\(packed.totalCharacters)文字のうち先頭\(packed.packedCharacters)文字を収めています")
        }
        return Card(
            kind: .memo, url: nil,
            header: Card.Header(lines: ["メモ"], sublines: ["\(packed.totalCharacters)文字"]),
            title: digest.heading.text.isEmpty ? "メモ" : digest.heading.text,
            sections: digest.sections,
            note: notes.isEmpty ? nil : notes.joined(separator: "\n"),
            qr: packed.payload)
    }
}
