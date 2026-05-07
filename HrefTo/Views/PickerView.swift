import SwiftUI

struct QuickRuleOptions {
    var alwaysForDomain: Bool = false
    var alwaysForPathPrefix: Bool = false  // e.g. github.com/org/repo
    var alwaysForApp: Bool = false
    var includeSourceApp: Bool = false  // sub-option of domain/path-prefix rule
}

struct PickerView: View {
    let url: URL
    let sourceAppName: String?
    let browsers: [Browser]
    let onSelect: (Browser, BrowserProfile?, QuickRuleOptions) -> Void
    let onDismiss: () -> Void
    let onCreateRule: () -> Void

    @State private var alwaysForDomain = false
    @State private var alwaysForPathPrefix = false
    @State private var alwaysForApp = false
    @State private var includeSourceApp = false

    /// Registrable domain (e.g. "google.com" from "docs.google.com")
    private var domain: String {
        guard let host = url.host, !host.isEmpty else { return "" }
        let parts = host.split(separator: ".")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: ".")
        }
        return host
    }

    /// Path-prefix label like "github.com/anthropics/claude-code" when
    /// the URL is on a supported host and has an org/repo style path.
    private var pathPrefixLabel: String? {
        guard let info = PathPrefixHost.extract(from: url) else { return nil }
        return "\(info.host)\(info.prefix)"
    }

    private var quickRuleOptions: QuickRuleOptions {
        QuickRuleOptions(
            alwaysForDomain: alwaysForDomain,
            alwaysForPathPrefix: alwaysForPathPrefix,
            alwaysForApp: alwaysForApp,
            includeSourceApp: includeSourceApp
        )
    }

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
                let enabledProfiles = browser.profiles.filter(\.enabled)
                if enabledProfiles.isEmpty {
                    BrowserRow(browser: browser, profile: nil, shortcut: index + 1) {
                        onSelect(browser, nil, quickRuleOptions)
                    }
                } else if enabledProfiles.count == 1 {
                    let profile = enabledProfiles[0]
                    BrowserRow(browser: browser, profile: profile, shortcut: index + 1) {
                        onSelect(browser, profile, quickRuleOptions)
                    }
                } else {
                    ForEach(enabledProfiles) { profile in
                        BrowserRow(browser: browser, profile: profile, shortcut: nil) {
                            onSelect(browser, profile, quickRuleOptions)
                        }
                    }
                }
            }

            Divider()

            // Quick rule options
            VStack(alignment: .leading, spacing: 6) {
                if let label = pathPrefixLabel {
                    Toggle("Always for \(label)", isOn: $alwaysForPathPrefix)
                        .font(.caption)
                }

                if !domain.isEmpty {
                    Toggle("Always for \(domain)", isOn: $alwaysForDomain)
                        .font(.caption)
                }

                if (alwaysForDomain || alwaysForPathPrefix) && sourceAppName != nil && !alwaysForApp {
                    Toggle("Only from \(sourceAppName!)", isOn: $includeSourceApp)
                        .font(.caption)
                        .padding(.leading, 16)
                }

                if let source = sourceAppName {
                    Toggle("Always from \(source)", isOn: $alwaysForApp)
                        .font(.caption)
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
