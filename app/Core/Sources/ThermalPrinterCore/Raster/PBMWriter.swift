import Foundation

public enum PBMWriter {
    public static func data(_ bitmap: Bitmap1) -> Data {
        var data = Data("P4\n\(bitmap.width) \(bitmap.height)\n".utf8)
        data.append(contentsOf: bitmap.bytes)
        return data
    }
}
