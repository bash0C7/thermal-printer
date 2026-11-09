import Foundation

public enum ScannedPayload: Equatable, Sendable {
    case open(URL)
    case show(String)

    public static func classify(_ text: String) -> ScannedPayload {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), opens(url, scheme: scheme)
        else { return .show(text) }
        return .open(url)
    }

    private static func opens(_ url: URL, scheme: String) -> Bool {
        switch scheme {
        case "taskforge": return url.path(percentEncoded: false).hasPrefix("/task/")
        case "obsidian": return url.host(percentEncoded: false) == "open"
        case "x-apple-reminderkit": return true
        case "https", "http": return url.host(percentEncoded: false)?.isEmpty == false
        default: return false
        }
    }
}
