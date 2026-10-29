import AppKit

/// Which data StockBar runs on: the user's own, or the made-up demo account for showing the app (switched in the
/// Developer tab). Each has its own folders; the demo never talks to Open Finance, so it can't sync over or mix
/// with real data. The local AI model and CVM's public fund data are shared.
enum DataAccount: String, CaseIterable, Identifiable {
    case personal, demo
    var id: String { rawValue }

    private static let key = "dataAccount"
    private static let seededKey = "demoSeededMonth"

    /// Read once at launch: the stores open their files when the app starts, so switching relaunches it.
    static let current: DataAccount = UserDefaults.standard.string(forKey: key).flatMap(DataAccount.init) ?? .personal

    /// Application Support/StockBar, shared by both accounts (the local model lives here).
    static let baseDirectory: URL = folder(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("StockBar", isDirectory: true))

    /// The account's portfolio, bonds, funds, alerts and expense settings. Personal data stays where it always was.
    static let dataDirectory: URL = current == .demo ? folder(baseDirectory.appendingPathComponent("Demo", isDirectory: true)) : baseDirectory

    /// The account's downloaded transactions and bills.
    static let cacheDirectory: URL = {
        let base = folder(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("StockBar", isDirectory: true))
        return current == .demo ? folder(base.appendingPathComponent("Demo", isDirectory: true)) : base
    }()

    private static func folder(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saves the choice and relaunches into it.
    static func switchTo(_ account: DataAccount) {
        UserDefaults.standard.set(account.rawValue, forKey: key)
        relaunch()
    }

    /// Puts the demo data back as it ships, with this month's dates, and relaunches.
    static func resetDemo() {
        UserDefaults.standard.removeObject(forKey: seededKey)
        relaunch()
    }

    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Demo data

    /// The month the bundled transactions end in (scripts/demo-data.py), so they can be moved to the current one.
    private static let demoMonth = 202610

    /// Copies the bundled demo data in, the first time and again each new month (so the current month always has
    /// spending to show) or app language. Changes made to the demo don't survive the refresh.
    static func prepareDemo() {
        guard current == .demo else { return }
        let thisMonth = DayKey.from(.now) / 100
        let seed = "\(thisMonth)-\(Bundle.main.preferredLocalizations.first ?? "en")"
        guard UserDefaults.standard.string(forKey: seededKey) != seed
              || !FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("trades.json").path),
              let bundled = Bundle.main.url(forResource: "Demo", withExtension: nil) else { return }
        let fm = FileManager.default
        for name in ["trades.json", "bonds.json", "fund-holdings.json", "alerts.json", "expenses.json"] {
            let target = dataDirectory.appendingPathComponent(name)
            try? fm.removeItem(at: target)
            try? fm.copyItem(at: bundled.appendingPathComponent(name), to: target)
        }
        // Public market data (CDI, IPCA, IFIX) the personal account already downloaded: saves the first launch a wait.
        for name in ["cdi-cache.json", "ipca-cache.json", "ifix-cache.json"]
        where !fm.fileExists(atPath: dataDirectory.appendingPathComponent(name).path) {
            try? fm.copyItem(at: baseDirectory.appendingPathComponent(name), to: dataDirectory.appendingPathComponent(name))
        }
        localizeCategories(dataDirectory.appendingPathComponent("expenses.json"))
        try? fm.removeItem(at: cacheDirectory.appendingPathComponent("bills-and-loans.json"))
        if let data = try? Data(contentsOf: bundled.appendingPathComponent("transactions-by-month.json")),
           let moved = shiftTransactions(data, by: monthsBetween(demoMonth, thisMonth)) {
            try? moved.write(to: cacheDirectory.appendingPathComponent("transactions-by-month.json"), options: .atomic)
        }
        UserDefaults.standard.set(seed, forKey: seededKey)
    }

    /// The demo's categories are the app's starting set, named in English; show them in the app's language.
    private static func localizeCategories(_ url: URL) {
        guard let data = try? Data(contentsOf: url), var settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let categories = settings["categories"] as? [[String: Any]] else { return }
        settings["categories"] = categories.map { category in
            var category = category
            if let name = category["name"] as? String { category["name"] = String(localized: String.LocalizationValue(name)) }
            return category
        }
        try? JSONSerialization.data(withJSONObject: settings).write(to: url, options: .atomic)
    }

    private static func monthsBetween(_ from: Int, _ to: Int) -> Int { (to / 100 - from / 100) * 12 + (to % 100 - from % 100) }

    /// Moves every transaction `months` months later (same day, or the month's last), drops the ones that would land
    /// after today, and marks every month as just downloaded so the app never tries to sync them.
    private static func shiftTransactions(_ data: Data, by months: Int) -> Data? {
        guard var cache = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let byMonth = cache["months"] as? [String: [[String: Any]]] else { return nil }
        let today = DayKey.from(.now)
        func shift(_ iso: String) -> String {
            let day = Int(iso.prefix(10).replacingOccurrences(of: "-", with: "")) ?? today
            let moved = DayKey.addMonths(day / 100 * 100 + 1, months) / 100 * 100
            let clamped = moved + min(day % 100, DayKey.daysInMonth(moved + 1))
            return String(format: "%04d-%02d-%02d", clamped / 10_000, clamped / 100 % 100, clamped % 100) + iso.dropFirst(10)
        }
        var shifted: [String: [[String: Any]]] = [:]
        for (key, transactions) in byMonth {
            guard let month = Int(key) else { continue }
            let newMonth = DayKey.addMonths(month * 100 + 1, months) / 100
            shifted[String(newMonth)] = transactions.compactMap { t in
                var t = t
                guard let date = t["date"] as? String else { return nil }
                t["date"] = shift(date)
                if var card = t["creditCardMetadata"] as? [String: Any], let purchase = card["purchaseDate"] as? String {
                    card["purchaseDate"] = shift(purchase)
                    t["creditCardMetadata"] = card
                }
                let day = Int((t["date"] as! String).prefix(10).replacingOccurrences(of: "-", with: "")) ?? 0
                return day <= today ? t : nil
            }
        }
        cache["months"] = shifted
        // Far in the future (2127): never stale, so never fetched.
        cache["fetchedAt"] = Dictionary(uniqueKeysWithValues: shifted.keys.map { ($0, 4_000_000_000.0) })
        cache["currencyRead"] = shifted.keys.compactMap(Int.init)
        return try? JSONSerialization.data(withJSONObject: cache)
    }
}
