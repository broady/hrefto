import Foundation
import AppKit

@MainActor
class BrowserDetector {
    /// Discover all installed browsers that handle https URLs
    func detectBrowsers() -> [Browser] {
        let dominated = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)

        let ownBundleId = Bundle.main.bundleIdentifier ?? "dev.cbro.HrefTo"

        var browsers: [Browser] = []
        for appURL in dominated {
            guard let bundle = Bundle(url: appURL),
                  let bundleId = bundle.bundleIdentifier,
                  bundleId != ownBundleId else { continue }

            let name = FileManager.default.displayName(atPath: appURL.path)
            let profiles = detectProfiles(for: bundleId)

            browsers.append(Browser(
                bundleId: bundleId,
                name: name,
                path: appURL.path,
                enabled: true,
                profiles: profiles
            ))
        }
        return browsers
    }

    /// Detect Chromium profiles by reading Local State JSON
    func detectProfiles(for bundleId: String) -> [BrowserProfile] {
        guard let appSupportDir = chromiumAppSupportDir(for: bundleId) else { return [] }

        let localStatePath = appSupportDir.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileInfo = json["profile"] as? [String: Any],
              let infoCache = profileInfo["info_cache"] as? [String: Any] else {
            return []
        }

        return infoCache.compactMap { key, value -> BrowserProfile? in
            guard let profileDict = value as? [String: Any],
                  let name = profileDict["name"] as? String else { return nil }
            return BrowserProfile(id: key, name: name, enabled: true)
        }.sorted { $0.id < $1.id }
    }

    private func chromiumAppSupportDir(for bundleId: String) -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let mapping: [String: String] = [
            "com.google.Chrome": "Google/Chrome",
            "com.google.Chrome.canary": "Google/Chrome Canary",
            "com.microsoft.edgemac": "Microsoft Edge",
            "com.brave.Browser": "BraveSoftware/Brave-Browser",
            "com.vivaldi.Vivaldi": "Vivaldi",
            "com.operasoftware.Opera": "com.operasoftware.Opera",
        ]

        guard let subpath = mapping[bundleId] else { return nil }
        let dir = appSupport.appendingPathComponent(subpath)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Count how many enabled browsers are currently running
    func countRunningBrowsers(enabledBrowsers: [Browser]) -> Int {
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })
        return enabledBrowsers.filter { $0.enabled && runningBundleIds.contains($0.bundleId) }.count
    }
}
