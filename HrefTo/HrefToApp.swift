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

        Task { @MainActor in
            urlHandler.handleURL(url)

            if urlHandler.showingPicker, let pendingURL = urlHandler.pendingURL {
                showPicker(for: pendingURL)
            }
        }
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
            onSelect: { [weak self] browser, profile in
                self?.urlHandler.recordPickerSelection(url: url, context: self?.urlHandler.pendingContext, bundleId: browser.bundleId, profileId: profile?.id)
                self?.urlHandler.openURL(url, bundleId: browser.bundleId, profile: profile, isChromium: browser.isChromiumBased)
                self?.pickerController.close()
                self?.urlHandler.showingPicker = false
            },
            onDismiss: { [weak self] in
                self?.pickerController.close()
                self?.urlHandler.showingPicker = false
            },
            onCreateRule: { [weak self] in
                self?.pickerController.close()
                self?.urlHandler.showingPicker = false
                // Open settings to rules tab
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        )

        pickerController.show(with: pickerView)
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
