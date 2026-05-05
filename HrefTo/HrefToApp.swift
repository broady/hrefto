import SwiftUI
import AppKit

@main
struct HrefToApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene — we manage windows manually for menu bar apps
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var pickerController = PickerWindowController()
    private let urlHandler = URLHandler()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon if configured
        if !AppConfig.shared.data.settings.showInDock {
            NSApp.setActivationPolicy(.accessory)
        }

        // Load config and open history database
        AppConfig.shared.load()
        LinkHistory.shared.open()

        // First launch: detect browsers and set up defaults
        if AppConfig.shared.data.browsers.isEmpty {
            performFirstLaunch()
        }

        // Set up menu bar
        setupMenuBar()

        // Register URL handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Register Services
        NSApp.servicesProvider = self
    }

    // MARK: - Services

    /// "Open URL with HrefTo" — routes through rule engine
    @objc func openURLService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urlString = extractURL(from: pboard),
              let url = URL(string: urlString) else {
            error.pointee = "No valid URL found in selection" as NSString
            return
        }
        urlHandler.handleURL(url)
        if urlHandler.showingPicker, let pendingURL = urlHandler.pendingURL {
            showPicker(for: pendingURL)
        }
    }

    /// "Pick Browser with HrefTo" — always shows picker
    @objc func pickBrowserService(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urlString = extractURL(from: pboard),
              let url = URL(string: urlString) else {
            error.pointee = "No valid URL found in selection" as NSString
            return
        }
        urlHandler.showPicker(url: url, context: nil, filter: .all)
        showPicker(for: url)
    }

    private func extractURL(from pboard: NSPasteboard) -> String? {
        // Try URL type first
        if let urlString = pboard.string(forType: .URL) {
            return urlString
        }
        // Fall back to plain text, try to find a URL in it
        if let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            if text.hasPrefix("http://") || text.hasPrefix("https://") {
                return text
            }
            // Try to detect bare domain
            if text.contains(".") && !text.contains(" ") {
                return "https://\(text)"
            }
        }
        return nil
    }

    private func performFirstLaunch() {
        let detector = BrowserDetector()
        let browsers = detector.detectBrowsers()
        AppConfig.shared.data.browsers = browsers

        // Default rule shows picker — user chooses and creates rules from there
        AppConfig.shared.data.rules = [
            Rule(
                id: "default",
                name: "Default",
                enabled: true,
                matchMode: .all,
                conditions: [],
                behaviour: Behaviour(type: .showPicker, bundleId: nil, profileId: nil, filter: .all)
            )
        ]
        AppConfig.shared.save()
    }

    private var isDefaultBrowser: Bool {
        guard let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return Bundle(url: defaultURL)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "HrefTo")
        }

        let menu = NSMenu()
        menu.delegate = self

        let enabledItem = NSMenuItem(title: "HrefTo Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = AppConfig.shared.data.settings.enabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Open Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ","))

        let defaultBrowserItem = NSMenuItem(title: "Set as Default Browser", action: #selector(setDefaultBrowser), keyEquivalent: "")
        defaultBrowserItem.tag = 100
        menu.addItem(defaultBrowserItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "About HrefTo", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit HrefTo", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Update enabled state
        if let enabledItem = menu.items.first {
            enabledItem.state = AppConfig.shared.data.settings.enabled ? .on : .off
        }

        // Update default browser item based on real state
        if let item = menu.item(withTag: 100) {
            if isDefaultBrowser {
                item.title = "Default Browser"
                item.action = nil  // grayed out
                item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "active")?.withSymbolConfiguration(.init(pointSize: 7, weight: .regular))?.tinted(with: .systemGreen)
            } else {
                item.title = "Set as Default Browser"
                item.action = #selector(setDefaultBrowser)
                item.image = nil
            }
        }
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        // Try to get the actual sender from the Apple Event's return address (authoritative).
        // Falls back to frontmost app heuristic if unavailable.
        let sourceApp = Self.sourceAppFromEvent(event) ?? Self.captureSourceApp()

        Task { @MainActor in
            urlHandler.handleURL(url, sourceApp: sourceApp)

            if urlHandler.showingPicker, let pendingURL = urlHandler.pendingURL {
                showPicker(for: pendingURL)
            }
        }
    }

    /// Extracts the sending app from the Apple Event's return address (PID-based).
    /// This is authoritative — it's the actual process that sent the URL, not a guess.
    private static func sourceAppFromEvent(_ event: NSAppleEventDescriptor) -> NSRunningApplication? {
        // The event's attributeDescriptor for keyAddressAttr contains sender info.
        // For local events, we can get the sender's PID from the process serial number or audit token.
        guard let senderDesc = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)) else {
            return nil
        }
        let pid = senderDesc.int32Value
        guard pid > 0 else { return nil }
        let app = NSRunningApplication(processIdentifier: pid)
        // Don't return ourselves
        if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        return app
    }

    /// Returns the frontmost app, excluding HrefTo itself.
    private static func captureSourceApp() -> NSRunningApplication? {
        URLHandler.captureSourceApp()
    }

    private func showPicker(for url: URL) {
        let browsers: [Browser]
        if urlHandler.pickerFilter == .running {
            let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            browsers = AppConfig.shared.data.browsers.filter { $0.enabled && runningBundleIds.contains($0.bundleId) }
        } else {
            browsers = AppConfig.shared.data.browsers.filter(\.enabled)
        }

        let sourceAppName = urlHandler.pendingContext?.sourceApp?.localizedName

        let pickerView = PickerView(
            url: url,
            sourceAppName: sourceAppName,
            browsers: browsers,
            onSelect: { [weak self] browser, profile, quickRule in
                self?.urlHandler.recordPickerSelection(url: url, context: self?.urlHandler.pendingContext, bundleId: browser.bundleId, profileId: profile?.id)
                self?.urlHandler.openURL(url, bundleId: browser.bundleId, profile: profile, isChromium: browser.isChromiumBased)
                self?.pickerController.close()
                self?.urlHandler.showingPicker = false

                // Create quick rule if any "always" checkbox was checked
                if quickRule.alwaysForDomain || quickRule.alwaysForApp {
                    self?.createQuickRule(
                        url: url,
                        options: quickRule,
                        browser: browser,
                        profile: profile
                    )
                }
            },
            onDismiss: { [weak self] in
                self?.pickerController.close()
                self?.urlHandler.showingPicker = false
            },
            onCreateRule: { [weak self] in
                self?.pickerController.close()
                self?.urlHandler.showingPicker = false

                // Build a pre-filled rule from the current URL context
                var conditions: [Condition] = []
                if let host = url.host, !host.isEmpty {
                    conditions.append(Condition(field: .host, operator: .endsWith, value: host))
                }
                if let sourceBundleId = self?.urlHandler.pendingContext?.sourceApp?.bundleIdentifier {
                    conditions.append(Condition(field: .sourceBundleId, operator: .equals, value: sourceBundleId))
                }

                let prefilled = Rule(
                    id: UUID().uuidString,
                    name: "New Rule",
                    enabled: true,
                    matchMode: .all,
                    conditions: conditions.isEmpty
                        ? [Condition(field: .host, operator: .endsWith, value: "example.com")]
                        : conditions,
                    behaviour: Behaviour(type: .showPicker, bundleId: nil, profileId: nil, filter: .all)
                )

                AppConfig.shared.pendingEditRule = prefilled
                self?.openSettings()
                NotificationCenter.default.post(name: .openRulesTab, object: nil)
            }
        )

        pickerController.show(with: pickerView)
    }

    private func createQuickRule(url: URL, options: QuickRuleOptions, browser: Browser, profile: BrowserProfile?) {
        var conditions: [Condition] = []

        if options.alwaysForDomain {
            let host = url.host ?? ""
            let parts = host.split(separator: ".")
            let domain = parts.count >= 2 ? parts.suffix(2).joined(separator: ".") : host
            conditions.append(Condition(field: .host, operator: .endsWith, value: domain))
        }

        if options.alwaysForApp {
            if let sourceBundleId = urlHandler.pendingContext?.sourceApp?.bundleIdentifier {
                conditions.append(Condition(field: .sourceBundleId, operator: .equals, value: sourceBundleId))
            }
        } else if options.includeSourceApp && options.alwaysForDomain {
            // "Only from <app>" sub-option under domain rule
            if let sourceBundleId = urlHandler.pendingContext?.sourceApp?.bundleIdentifier {
                conditions.append(Condition(field: .sourceBundleId, operator: .equals, value: sourceBundleId))
            }
        }

        guard !conditions.isEmpty else { return }

        let browserName = profile != nil ? "\(browser.name) (\(profile!.name))" : browser.name
        let conditionSummary: String
        if options.alwaysForDomain && (options.alwaysForApp || options.includeSourceApp) {
            let domain = url.host ?? ""
            let sourceName = urlHandler.pendingContext?.sourceApp?.localizedName ?? "app"
            conditionSummary = "\(domain) from \(sourceName)"
        } else if options.alwaysForApp {
            let sourceName = urlHandler.pendingContext?.sourceApp?.localizedName ?? "app"
            conditionSummary = "from \(sourceName)"
        } else {
            conditionSummary = url.host ?? "domain"
        }

        let rule = Rule(
            id: UUID().uuidString,
            name: "\(conditionSummary) \u{2192} \(browserName)",
            enabled: true,
            matchMode: .all,
            conditions: conditions,
            behaviour: Behaviour(type: .openInBrowser, bundleId: browser.bundleId, profileId: profile?.id, filter: nil)
        )

        // Insert before the default rule
        let insertIndex = max(0, AppConfig.shared.data.rules.count - 1)
        AppConfig.shared.data.rules.insert(rule, at: insertIndex)
        AppConfig.shared.save()
    }

    @objc private func toggleEnabled() {
        AppConfig.shared.data.settings.enabled.toggle()
        AppConfig.shared.save()

        // Update menu item state
        if let menu = statusItem.menu, let item = menu.items.first {
            item.state = AppConfig.shared.data.settings.enabled ? .on : .off
        }
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(AppConfig.shared)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "HrefTo Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window
    }

    @objc private func setDefaultBrowser() {
        guard let appURL = Bundle.main.bundleURL as URL? else { return }
        Task {
            try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
            try? await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
