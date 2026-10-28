import Foundation

public enum QRPayload {
    public static let maxCardModules = QRCode.cardSideDots / QRCode.minimumDotsPerModule

    public struct Packed: Equatable, Sendable {
        public let payload: String
        public let packedCharacters: Int
        public let totalCharacters: Int

        public var isComplete: Bool { packedCharacters == totalCharacters }
    }

    public static func payload(for text: String) -> String {
        let lowered = text.lowercased()
        let looksLikeAScheme = text.firstMatch(of: /^\s*[A-Za-z][A-Za-z0-9+.\-]*:/) != nil
        let isWebURL = lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        return looksLikeAScheme && !isWebURL ? "メモ\n" + text : text
    }

    public static func pack(_ text: String, maxModules: Int = maxCardModules) -> Packed {
        let characters = Array(text)
        let total = characters.count
        func fits(_ count: Int) -> Bool {
            QRCode.moduleCount(for: payload(for: String(characters.prefix(count)))).map { $0 <= maxModules } ?? false
        }
        if total == 0 || fits(total) {
            return Packed(payload: payload(for: text), packedCharacters: total, totalCharacters: total)
        }
        var low = 0
        var high = total - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle) {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return Packed(
            payload: payload(for: String(characters.prefix(low))), packedCharacters: low, totalCharacters: total)
    }
}
