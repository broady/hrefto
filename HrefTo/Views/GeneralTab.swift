import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject private var config = AppConfig.shared
    @State private var isDefaultBrowser = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $config.data.settings.launchAtLogin)
                    .onChange(of: config.data.settings.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                        config.save()
                    }

                Toggle("Show in Dock", isOn: $config.data.settings.showInDock)
                    .onChange(of: config.data.settings.showInDock) { _, _ in
                        config.save()
                    }
            }

            Section("Default Browser") {
                HStack {
                    Circle()
                        .fill(isDefaultBrowser ? .green : .orange)
                        .frame(width: 8, height: 8)
                    Text(isDefaultBrowser ? "HrefTo is your default browser" : "HrefTo is not the default browser")
                    Spacer()
                    if !isDefaultBrowser {
                        Button("Set as Default") {
                            setAsDefaultBrowser()
                        }
                    }
                }
            }

            Section("Services") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HrefTo provides two system services:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("  \u{2022} Open URL with HrefTo — routes through rules")
                        .font(.caption)
                    Text("  \u{2022} Pick Browser with HrefTo — always shows picker")
                        .font(.caption)

                    if !config.data.settings.servicesDismissed {
                        HStack {
                            Text("Enable in System Settings > Keyboard > Keyboard Shortcuts > Services")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                            }
                            .controlSize(.small)
                            Button("Done") {
                                config.data.settings.servicesDismissed = true
                                config.save()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("Picker") {
                Picker("Position:", selection: $config.data.settings.pickerPosition) {
                    Text("Near cursor").tag(AppSettings.PickerPosition.cursor)
                    Text("Center of screen").tag(AppSettings.PickerPosition.center)
                }
                .onChange(of: config.data.settings.pickerPosition) { _, _ in
                    config.save()
                }

                HStack {
                    Text("Timeout:")
                    TextField("", value: $config.data.settings.pickerTimeoutSeconds, format: .number)
                        .frame(width: 60)
                    Text("seconds (0 = no timeout)")
                        .foregroundStyle(.secondary)
                }
                .onChange(of: config.data.settings.pickerTimeoutSeconds) { _, _ in
                    config.save()
                }

                Toggle("Skip picker when only one browser is running", isOn: $config.data.settings.skipPickerForSingleBrowser)
                    .onChange(of: config.data.settings.skipPickerForSingleBrowser) { _, _ in
                        config.save()
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold keys to force picker:")
                    HStack {
                        ForEach(AppSettings.ModifierKey.allCases, id: \.self) { key in
                            Toggle(key.displayName, isOn: Binding(
                                get: { config.data.settings.forcePickerModifiers.contains(key) },
                                set: { enabled in
                                    if enabled {
                                        config.data.settings.forcePickerModifiers.insert(key)
                                    } else {
                                        config.data.settings.forcePickerModifiers.remove(key)
                                    }
                                    config.save()
                                }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                }
            }

            Section("History") {
                Text("Link history is stored locally in SQLite for rule testing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear History", role: .destructive) {
                    LinkHistory.shared.clear()
                }
            }

            Section {
                Button("Reset All Settings", role: .destructive) {
                    config.data = ConfigData()
                    config.save()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkDefaultBrowser()
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    private func setAsDefaultBrowser() {
        guard let appURL = Bundle.main.bundleURL as URL? else { return }
        Task {
            try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
            await MainActor.run { checkDefaultBrowser() }
        }
    }

    private func checkDefaultBrowser() {
        if let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) {
            let defaultBundleId = Bundle(url: defaultBrowser)?.bundleIdentifier
            isDefaultBrowser = defaultBundleId == Bundle.main.bundleIdentifier
        }
    }
}
