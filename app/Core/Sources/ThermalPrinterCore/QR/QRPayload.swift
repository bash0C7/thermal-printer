import Foundation

public enum Base45 {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)
    private static let reverse: [UInt8: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    public static func encode(_ data: Data) -> String {
        var out: [UInt8] = []
        var index = data.startIndex
        while index < data.endIndex {
            if data.index(after: index) < data.endIndex {
                let n = Int(data[index]) * 256 + Int(data[data.index(after: index)])
                out += [alphabet[n % 45], alphabet[n / 45 % 45], alphabet[n / 2025]]
                index = data.index(index, offsetBy: 2)
            } else {
                let n = Int(data[index])
                out += [alphabet[n % 45], alphabet[n / 45]]
                index = data.index(after: index)
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    public static func decode(_ text: String) -> Data? {
        let values = text.utf8.map { reverse[$0] }
        guard !values.contains(where: { $0 == nil }), values.count % 3 != 1 else { return nil }
        let digits = values.compactMap { $0 }
        var out = Data()
        var index = 0
        while index < digits.count {
            if index + 2 < digits.count {
                let n = digits[index] + digits[index + 1] * 45 + digits[index + 2] * 2025
                guard n <= 0xFFFF else { return nil }
                out.append(UInt8(n / 256))
                out.append(UInt8(n % 256))
                index += 3
            } else {
                let n = digits[index] + digits[index + 1] * 45
                guard n <= 0xFF else { return nil }
                out.append(UInt8(n))
                index += 2
            }
        }
        return out
    }
}

public enum QRPayload {
    public static let prefix = "TP1:"
    public static let maxCardModules = (Bitmap1.contentWidth - 2 * 8) / QRCode.minimumDotsPerModule

    public struct Packed: Equatable, Sendable {
        public let payload: String
        public let packedCharacters: Int
        public let totalCharacters: Int

        public var isComplete: Bool { packedCharacters == totalCharacters }
    }

    public static func encode(_ text: String) -> String? {
        guard let compressed = try? (Data(text.utf8) as NSData).compressed(using: .zlib) else { return nil }
        return prefix + Base45.encode(compressed as Data)
    }

    public static func decode(_ payload: String) -> String? {
        guard payload.hasPrefix(prefix), let compressed = Base45.decode(String(payload.dropFirst(prefix.count))),
            let raw = try? (compressed as NSData).decompressed(using: .zlib)
        else { return nil }
        return String(data: raw as Data, encoding: .utf8)
    }

    public static func pack(_ text: String, maxModules: Int = maxCardModules) -> Packed {
        let characters = Array(text)
        let total = characters.count
        func fitting(_ count: Int) -> String? {
            guard let payload = encode(String(characters.prefix(count))),
                let modules = QRCode.moduleCount(for: payload), modules <= maxModules
            else { return nil }
            return payload
        }
        if let whole = fitting(total) {
            return Packed(payload: whole, packedCharacters: total, totalCharacters: total)
        }
        var low = 0
        var high = total - 1
        var best = fitting(0) ?? prefix
        while low < high {
            let middle = (low + high + 1) / 2
            if let payload = fitting(middle) {
                low = middle
                best = payload
            } else {
                high = middle - 1
            }
        }
        return Packed(payload: best, packedCharacters: low, totalCharacters: total)
    }
}
