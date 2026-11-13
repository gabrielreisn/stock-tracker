import Foundation

/// App-sandbox storage, intentionally independent from the desktop and Expo installations.
enum DataAccount {
    static let current = Account.personal
    enum Account { case personal, demo }
    static let baseDirectory = folder(.applicationSupportDirectory)
    static let dataDirectory = baseDirectory
    static let cacheDirectory = folder(.cachesDirectory)
    private static func folder(_ kind: FileManager.SearchPathDirectory) -> URL {
        let url = FileManager.default.urls(for: kind, in: .userDomainMask)[0].appendingPathComponent("StockBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
