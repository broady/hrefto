import SwiftUI
import AppKit

/// Cached list of installed applications, discovered once and reused.
@MainActor
class InstalledApps: ObservableObject {
    static let shared = InstalledApps()

    struct AppInfo: Identifiable, Hashable {
        let id: String  // bundle ID
        let name: String
        let path: String
        var icon: NSImage? { NSWorkspace.shared.icon(forFile: path) }
    }

    @Published var apps: [AppInfo] = []

    private var scanned = false

    func scanIfNeeded() {
        guard !scanned else { return }
        scanned = true
        apps = Self.discoverApps()
    }

    private static func discoverApps() -> [AppInfo] {
        let fm = FileManager.default
        var results: [String: AppInfo] = [:]  // keyed by bundleId to dedupe

        let searchDirs = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
        ]

        for dir in searchDirs {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                if url.pathExtension == "app" {
                    // Don't recurse into .app bundles
                    enumerator.skipDescendants()

                    if let bundle = Bundle(url: url),
                       let bundleId = bundle.bundleIdentifier {
                        let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                            ?? bundle.infoDictionary?["CFBundleName"] as? String
                            ?? url.deletingPathExtension().lastPathComponent
                        if results[bundleId] == nil {
                            results[bundleId] = AppInfo(id: bundleId, name: name, path: url.path)
                        }
                    }
                }
            }
        }

        return results.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// A value field that shows a searchable app picker for sourceBundleId/sourceName conditions.
/// Falls back to a text field for custom entry.
struct AppPickerField: View {
    @Binding var value: String
    let fieldType: ConditionField

    @ObservedObject private var installedApps = InstalledApps.shared
    @State private var showCustom = false
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 4) {
            if showCustom {
                TextField("Bundle ID or path", text: $value)
                    .textFieldStyle(.roundedBorder)
                Button {
                    showCustom = false
                } label: {
                    Image(systemName: "list.bullet")
                }
                .buttonStyle(.plain)
                .help("Show app list")
            } else {
                appPicker
                Button {
                    showCustom = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Enter custom value")
            }
        }
        .onAppear {
            installedApps.scanIfNeeded()
            // If current value doesn't match any known app, start in custom mode
            if !value.isEmpty && !installedApps.apps.contains(where: { matchesValue($0) }) {
                showCustom = true
            }
        }
    }

    private var appPicker: some View {
        Picker("", selection: Binding(
            get: { value },
            set: { value = $0 }
        )) {
            Text("Select app...").tag("")
            ForEach(filteredApps) { app in
                HStack {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 14, height: 14)
                    }
                    Text(app.name)
                    Text("(\(app.id))").foregroundStyle(.secondary).font(.caption2)
                }
                .tag(appValue(for: app))
            }
        }
        .labelsHidden()
    }

    private var filteredApps: [InstalledApps.AppInfo] {
        installedApps.apps
    }

    private func matchesValue(_ app: InstalledApps.AppInfo) -> Bool {
        switch fieldType {
        case .sourceBundleId:
            return app.id == value
        case .sourceName:
            return app.name == value
        case .sourceApp:
            return app.path == value || app.id == value
        default:
            return app.id == value
        }
    }

    private func appValue(for app: InstalledApps.AppInfo) -> String {
        switch fieldType {
        case .sourceBundleId: return app.id
        case .sourceName: return app.name
        case .sourceApp: return app.path
        default: return app.id
        }
    }
}
