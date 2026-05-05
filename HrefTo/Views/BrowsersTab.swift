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
                        // Merge: keep user preferences for existing browsers, add new ones
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
                        Text(profile.name)
                            .font(.caption)
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
