import SwiftUI

struct BrowsersTab: View {
    @ObservedObject private var config = AppConfig.shared

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(Array(config.data.browsers.enumerated()), id: \.element.bundleId) { index, browser in
                    BrowserListRow(browser: binding(for: index))
                }
                .onMove { source, destination in
                    config.data.browsers.move(fromOffsets: source, toOffset: destination)
                    config.save()
                }
            }

            HStack {
                Button("Re-scan Browsers") {
                    Task {
                        let detector = BrowserDetector()
                        let detected = detector.detectBrowsers()
                        let detectedById = Dictionary(uniqueKeysWithValues: detected.map { ($0.bundleId, $0) })

                        // Merge new profiles into already-known browsers, preserving
                        // the user's enable/disable toggles for existing profiles.
                        for index in config.data.browsers.indices {
                            let bundleId = config.data.browsers[index].bundleId
                            guard let scanned = detectedById[bundleId] else { continue }
                            let existingProfiles = config.data.browsers[index].profiles
                            let existingById = Dictionary(uniqueKeysWithValues: existingProfiles.map { ($0.id, $0) })
                            config.data.browsers[index].profiles = scanned.profiles.map { scannedProfile in
                                existingById[scannedProfile.id] ?? scannedProfile
                            }
                        }

                        // Append browsers we haven't seen before.
                        let existingIds = Set(config.data.browsers.map(\.bundleId))
                        let newBrowsers = detected.filter { !existingIds.contains($0.bundleId) }
                        config.data.browsers.append(contentsOf: newBrowsers)
                        config.save()
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func binding(for index: Int) -> Binding<Browser> {
        Binding(
            get: { config.data.browsers[index] },
            set: {
                config.data.browsers[index] = $0
                config.save()
            }
        )
    }
}

struct BrowserListRow: View {
    @Binding var browser: Browser
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if let icon = NSWorkspace.shared.icon(forFile: browser.path) as NSImage? {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading) {
                    Text(browser.name)
                        .font(.body)
                    Text(browser.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !browser.profiles.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    }
                    .buttonStyle(.plain)
                }

                Toggle("", isOn: $browser.enabled)
                    .labelsHidden()
            }

            if isExpanded {
                ForEach(Array(browser.profiles.enumerated()), id: \.element.id) { profileIndex, profile in
                    HStack {
                        TextField("Profile name", text: Binding(
                            get: { browser.profiles[profileIndex].name },
                            set: { browser.profiles[profileIndex].name = $0 }
                        ))
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .padding(.leading, 40)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { browser.profiles[profileIndex].enabled },
                            set: { browser.profiles[profileIndex].enabled = $0 }
                        ))
                        .labelsHidden()
                    }
                }
            }
        }
    }
}
