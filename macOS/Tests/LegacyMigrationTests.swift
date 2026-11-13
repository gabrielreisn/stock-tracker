import Foundation

@main
struct LegacyMigrationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = root.appendingPathComponent("support")
        let caches = root.appendingPathComponent("cache")
        let domain = "CymbaMigrationTests.\(UUID())"
        let legacyDomain = "StockBarMigrationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            defaults.removePersistentDomain(forName: domain)
            defaults.removePersistentDomain(forName: legacyDomain)
            try? fm.removeItem(at: root)
        }
        func write(_ value: String, _ path: String, in base: URL) throws {
            let url = base.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: url)
        }
        try write("old trades", "StockBar/trades.json", in: support)
        try write("keep current", "Cymba/trades.json", in: support)
        try write("bonds", "StockBar/bonds.json", in: support)
        try write("demo", "StockBar/Demo/funds.json", in: support)
        try write("model", "StockBar/Models/old-model", in: support)
        try write("cache", "StockBar/CVM/registry.json", in: caches)
        defaults.setPersistentDomain(["pluggyItems": ["old"], "theme": "dark"], forName: legacyDomain)
        defaults.setPersistentDomain(["pluggyItems": ["current"]], forName: domain)
        LegacyMigration.run(defaults: defaults, applicationSupport: support, caches: caches,
                            defaultsDomain: domain, legacyDefaultsDomain: legacyDomain)
        func check(_ value: Bool) throws { precondition(value) }
        func read(_ path: String, in base: URL) throws -> String {
            try String(contentsOf: base.appendingPathComponent(path), encoding: .utf8)
        }
        try check(read("Cymba/trades.json", in: support) == "keep current")
        try check(read("Cymba/bonds.json", in: support) == "bonds")
        try check(read("StockBar/trades.json", in: support) == "old trades")
        try check(read("Cymba/Demo/funds.json", in: support) == "demo")
        try check(read("Cymba/CVM/registry.json", in: caches) == "cache")
        precondition(!fm.fileExists(atPath: support.appendingPathComponent("Cymba/Models").path))
        precondition(defaults.stringArray(forKey: "pluggyItems") == ["current"])
        precondition(defaults.string(forKey: "theme") == "dark")
        try write("later", "StockBar/later.json", in: support)
        LegacyMigration.run(defaults: defaults, applicationSupport: support, caches: caches,
                            defaultsDomain: domain, legacyDefaultsDomain: legacyDomain)
        precondition(!fm.fileExists(atPath: support.appendingPathComponent("Cymba/later.json").path))
        print("PASS: migrate data, nested demo/cache files and settings; preserve originals and current data; skip obsolete models; run once")
    }
}
