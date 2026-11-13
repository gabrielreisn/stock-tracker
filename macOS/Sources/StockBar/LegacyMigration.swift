import Foundation

/// Copy StockBar's data into Cymba once, preserving both the originals and any existing Cymba files.
enum LegacyMigration {
    static func run(defaults: UserDefaults = .standard,
                    applicationSupport: URL? = nil, caches: URL? = nil,
                    defaultsDomain: String = Bundle.main.bundleIdentifier ?? "app.cymba.macos",
                    legacyDefaultsDomain: String = "com.gabrielreis.stockbar") {
        let marker = "stockBarMigrationComplete"
        guard !defaults.bool(forKey: marker) else { return }
        let fm = FileManager.default
        do {
            for root in [applicationSupport ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                         caches ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]] {
                try copyMissing(from: root.appendingPathComponent("StockBar"), to: root.appendingPathComponent("Cymba"))
            }
            let existing = defaults.persistentDomain(forName: defaultsDomain) ?? [:]
            for (key, value) in defaults.persistentDomain(forName: legacyDefaultsDomain) ?? [:] where existing[key] == nil {
                defaults.set(value, forKey: key)
            }
            defaults.set(true, forKey: marker)
        } catch {
            // Leave the originals intact and retry next launch if a file wasn't readable or writable.
            NSLog("StockBar data migration could not finish: %@", error.localizedDescription)
        }
    }

    private static func copyMissing(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for file in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) where file.lastPathComponent != "Models" {
                try copyMissing(from: file, to: destination.appendingPathComponent(file.lastPathComponent))
            }
        } else if !fm.fileExists(atPath: destination.path) {
            try fm.copyItem(at: source, to: destination)
        }
    }
}
