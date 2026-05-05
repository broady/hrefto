import Foundation
import SwiftUI

struct AppSettings: Codable {
    var launchAtLogin: Bool = false
    var showInDock: Bool = false
    var pickerPosition: PickerPosition = .cursor
    var pickerTimeoutSeconds: Int = 0
    var enabled: Bool = true
    var servicesDismissed: Bool = false
    var skipPickerForSingleBrowser: Bool = true

    enum PickerPosition: String, Codable {
        case cursor
        case center
    }
}

struct ConfigData: Codable {
    var version: Int = 1
    var browsers: [Browser] = []
    var rules: [Rule] = []
    var settings: AppSettings = AppSettings()
}

extension Notification.Name {
    static let openRulesTab = Notification.Name("HrefTo.openRulesTab")
}

@MainActor
class AppConfig: ObservableObject {
    @Published var data: ConfigData = ConfigData()
    /// Set by picker's "Create Rule..." to pre-fill the rule editor.
    @Published var pendingEditRule: Rule?

    static let shared = AppConfig()

    private static var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("HrefTo")
        return dir.appendingPathComponent("config.json")
    }

    func load() {
        let url = Self.configURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            self.data = try JSONDecoder().decode(ConfigData.self, from: data)
        } catch {
            print("Failed to load config: \(error)")
        }
    }

    func save() {
        let url = Self.configURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self.data)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save config: \(error)")
        }
    }
}
