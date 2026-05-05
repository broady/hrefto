import SwiftUI

struct PickerView: View {
    let url: URL
    let sourceAppName: String?
    let browsers: [Browser]
    let onSelect: (Browser, BrowserProfile?) -> Void
    let onDismiss: () -> Void
    let onCreateRule: () -> Void

    @State private var alwaysForDomain = false
    @State private var includeSourceApp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // URL header
            VStack(alignment: .leading, spacing: 2) {
                Text(url.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)

                if let source = sourceAppName {
                    Text("from: \(source)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Browser list
            ForEach(Array(browsers.enumerated()), id: \.element.bundleId) { index, browser in
                if browser.profiles.isEmpty || browser.profiles.filter(\.enabled).count <= 1 {
                    BrowserRow(browser: browser, profile: nil, shortcut: index + 1) {
                        onSelect(browser, nil)
                    }
                } else {
                    ForEach(browser.profiles.filter(\.enabled)) { profile in
                        BrowserRow(browser: browser, profile: profile, shortcut: nil) {
                            onSelect(browser, profile)
                        }
                    }
                }
            }

            Divider()

            // Quick rule options
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Always for this domain", isOn: $alwaysForDomain)
                    .font(.caption)

                if alwaysForDomain && sourceAppName != nil {
                    Toggle("Only from \(sourceAppName!)", isOn: $includeSourceApp)
                        .font(.caption)
                        .padding(.leading, 16)
                }

                Button("Create Rule...") {
                    onCreateRule()
                }
                .font(.caption)
                .buttonStyle(.link)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .onExitCommand { onDismiss() }
    }
}

struct BrowserRow: View {
    let browser: Browser
    let profile: BrowserProfile?
    let shortcut: Int?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                // Browser icon
                if let icon = NSWorkspace.shared.icon(forFile: browser.path) as NSImage? {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }

                Text(displayName)
                    .font(.system(size: 13))

                Spacer()

                if let shortcut = shortcut, shortcut <= 9 {
                    Text("\u{2318}\(shortcut)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.accentColor.opacity(0.1) : .clear)
        .onHover { isHovered = $0 }
    }

    private var displayName: String {
        if let profile = profile {
            return "\(browser.name) (\(profile.name))"
        }
        return browser.name
    }
}
