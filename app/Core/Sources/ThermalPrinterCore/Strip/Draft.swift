import Foundation

public enum Draft {
    private static var imageToken: Regex<(Substring, Substring)> { /\[Image #(\d+)\]/ }

    public static func token(_ number: Int) -> String {
        "[Image #\(number)]"
    }

    public static func imageNumbers(in text: String) -> [Int] {
        text.matches(of: imageToken).compactMap { Int($0.1) }
    }

    public static func markdown(_ text: String, images: [Int: URL]) -> String {
        text.replacing(imageToken) { match in
            guard let number = Int(match.1), let url = images[number] else { return String(match.0) }
            return "\n\n![](\(url.absoluteString))\n\n"
        }
    }

    public static func plainText(_ text: String) -> String {
        text.replacing(imageToken, with: "")
    }
}
