import AppKit
import Security

/// Updates StockBar in place from the GitHub releases: finds a newer DMG, copies the app out of it, checks that it's
/// signed with the same certificate as the running app, swaps the bundle and relaunches.
@MainActor
@Observable
final class Updater {
    struct Release: Equatable {
        var version: String
        var notes: String
        var dmg: URL
        var page: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate
        case available(Release)
        case downloading(Release), installing(Release)
        case failed(String)

        var isDownloading: Bool {
            if case .downloading = self { true } else { false }
        }
    }

    private(set) var state = State.idle
    private(set) var lastCheck: Date?
    /// Set when an install fails; the release stays available to retry or download by hand.
    var installError: String?

    var checkAutomatically = UserDefaults.standard.object(forKey: "updateCheckAutomatically") as? Bool ?? true {
        didSet { UserDefaults.standard.set(checkAutomatically, forKey: "updateCheckAutomatically") }
    }
    /// Pre-releases (v3.0.0-beta-1) are offered by default only to someone already running one.
    var includeBetas = UserDefaults.standard.object(forKey: "updateIncludeBetas") as? Bool ?? Version(Updater.currentVersion).isPrerelease {
        didSet {
            UserDefaults.standard.set(includeBetas, forKey: "updateIncludeBetas")
            Task { await check() }
        }
    }

    /// The full version, beta suffix included (CFBundleShortVersionString must be numeric, so it drops it).
    static let currentVersion = Bundle.main.object(forInfoDictionaryKey: "StockBarVersion") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    private static let releasesURL = URL(string: "https://api.github.com/repos/gabrielreisn/stock-tracker/releases?per_page=20")!

    init() {
        Task {
            // Every 6 hours while the app runs; the check itself is one small API call.
            while true {
                if checkAutomatically { await check() }
                try? await Task.sleep(for: .seconds(6 * 3600))
            }
        }
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    func check() async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        do {
            var request = URLRequest(url: Self.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let newest = try JSONDecoder().decode([GitHubRelease].self, from: data)
                .filter { !$0.draft && (includeBetas || !$0.prerelease) }
                .compactMap { $0.release }
                .max { Version($0.version) < Version($1.version) }
            lastCheck = .now
            if let newest, Version(Self.currentVersion) < Version(newest.version) {
                state = .available(newest)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(String(localized: "Couldn't reach GitHub to check for updates."))
        }
    }

    func install() {
        guard case .available(let release) = state else { return }
        installError = nil
        state = .downloading(release)
        Task {
            do {
                let (dmg, _) = try await URLSession.shared.download(from: release.dmg)
                defer { try? FileManager.default.removeItem(at: dmg) }
                state = .installing(release)
                let target = Bundle.main.bundleURL
                try await Task.detached { try Self.replace(target, withAppIn: dmg) }.value
                relaunch()
            } catch {
                state = .available(release)
                installError = (error as? UpdateError)?.message ?? error.localizedDescription
            }
        }
    }

    /// Mounts the DMG, copies its app next to the installed one (same volume, so the swap is a rename),
    /// verifies the copy and swaps it in. Blocking: runs off the main thread.
    nonisolated private static func replace(_ target: URL, withAppIn dmg: URL) throws {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateError(message: String(localized: "StockBar can't write to the folder it's installed in. Download the update from GitHub instead."))
        }
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? fm.removeItem(at: work) }
        let mount = work.appendingPathComponent("mount")
        let staged = work.appendingPathComponent("StockBar.app")

        try run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path)
        do {
            // ditto keeps the signature and extended attributes intact.
            try run("/usr/bin/ditto", mount.appendingPathComponent("StockBar.app").path, staged.path)
        } catch {
            try? run("/usr/bin/hdiutil", "detach", mount.path, "-force")
            throw error
        }
        try? run("/usr/bin/hdiutil", "detach", mount.path, "-force")

        try verifySignature(of: staged)
        _ = try fm.replaceItemAt(target, withItemAt: staged)
    }

    /// The new app must satisfy the running app's designated requirement: same bundle ID, same signing certificate.
    /// A local ad-hoc build has a per-build requirement, so it can't be updated this way.
    nonisolated private static func verifySignature(of app: URL) throws {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), requirement) == errSecSuccess
        else {
            throw UpdateError(message: String(localized: "The downloaded update isn't signed like this copy of StockBar, so it wasn't installed."))
        }
    }

    nonisolated private static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError(message: String(localized: "Installing the update failed (\(URL(fileURLWithPath: tool).lastPathComponent) exited with \(process.terminationStatus))."))
        }
    }

    /// Opens the new bundle once this process has exited.
    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier)]
        try? task.run()
        NSApp.terminate(nil)
    }

    private struct UpdateError: Error {
        var message: String
    }

    private struct GitHubRelease: Decodable {
        var tag_name: String
        var draft: Bool
        var prerelease: Bool
        var body: String?
        var html_url: URL
        var assets: [Asset]
        struct Asset: Decodable {
            var name: String
            var browser_download_url: URL
        }

        var release: Release? {
            guard let dmg = assets.first(where: { $0.name.hasSuffix(".dmg") }) else { return nil }
            let version = tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
            return Release(version: version, notes: body ?? "", dmg: dmg.browser_download_url, page: html_url)
        }
    }
}

/// "3.0.0-beta-1": numbers compared one by one; a release sorts after its own pre-releases.
struct Version: Comparable {
    var numbers: [Int]
    var prerelease: String?

    init(_ string: String) {
        let parts = string.split(separator: "-", maxSplits: 1)
        numbers = parts.first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    var isPrerelease: Bool { prerelease != nil }

    static func < (a: Version, b: Version) -> Bool {
        for i in 0..<max(a.numbers.count, b.numbers.count) {
            let x = i < a.numbers.count ? a.numbers[i] : 0, y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y }
        }
        switch (a.prerelease, b.prerelease) {
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        case (_?, nil): return true
        default: return false
        }
    }

    static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }
}
