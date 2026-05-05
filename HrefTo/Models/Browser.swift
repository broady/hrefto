import Foundation

struct BrowserProfile: Codable, Identifiable, Hashable {
    var id: String          // e.g., "Default", "Profile 1"
    var name: String        // e.g., "Personal", "Work"
    var enabled: Bool
}

struct Browser: Codable, Identifiable, Hashable {
    var id: String { bundleId }
    var bundleId: String
    var name: String
    var path: String        // /Applications/Google Chrome.app
    var enabled: Bool
    var profiles: [BrowserProfile]

    var isChromiumBased: Bool {
        let chromiumBundles = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "company.thebrowser.Browser",  // Arc
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera"
        ]
        return chromiumBundles.contains(bundleId)
    }
}
