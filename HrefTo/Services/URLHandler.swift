import Foundation
import AppKit
import SwiftUI

@MainActor
class URLHandler: ObservableObject {
    let ruleEngine = RuleEngine()
    let browserDetector = BrowserDetector()
    let modifierMonitor = ModifierKeyMonitor()

    @Published var pendingURL: URL?
    @Published var pendingContext: URLContext?
    @Published var showingPicker = false
    @Published var pickerFilter: PickerFilter = .all

    func handleURL(_ url: URL) {
        let config = AppConfig.shared

        // If disabled, pass straight to default browser
        guard config.data.settings.enabled else {
            if let defaultRule = config.data.rules.last {
                executeBehaviour(defaultRule.behaviour, url: url)
            }
            return
        }

        // Handle hrefto:// scheme
        if url.scheme == "hrefto" {
            handleInternalScheme(url)
            return
        }

        // Build context
        let modifiers = modifierMonitor.currentModifierString()
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let runningCount = browserDetector.countRunningBrowsers(enabledBrowsers: config.data.browsers)

        let context = URLContext(
            url: url,
            sourceApp: sourceApp,
            modifiers: modifiers,
            runningBrowserCount: runningCount,
            isHandoff: false
        )

        // Evaluate rules
        let matchedRule = ruleEngine.evaluate(rules: config.data.rules, context: context)

        if let rule = matchedRule {
            executeBehaviour(rule.behaviour, url: url, context: context, matchedRule: rule)
        } else {
            // No match — show picker as fallback
            recordHistory(url: url, context: context, matchedRule: nil, targetBundleId: nil, targetProfileId: nil)
            showPicker(url: url, context: context, filter: .all)
        }
    }

    func executeBehaviour(_ behaviour: Behaviour, url: URL, context: URLContext? = nil, matchedRule: Rule? = nil) {
        switch behaviour.type {
        case .openInBrowser:
            guard let bundleId = behaviour.bundleId else { return }
            let browser = AppConfig.shared.data.browsers.first { $0.bundleId == bundleId }
            let profile = browser?.profiles.first { $0.id == behaviour.profileId }
            if let context = context {
                recordHistory(url: url, context: context, matchedRule: matchedRule, targetBundleId: bundleId, targetProfileId: behaviour.profileId)
            }
            openURL(url, bundleId: bundleId, profile: profile, isChromium: browser?.isChromiumBased ?? false)

        case .showPicker:
            if let context = context {
                recordHistory(url: url, context: context, matchedRule: matchedRule, targetBundleId: nil, targetProfileId: nil)
            }
            showPicker(url: url, context: context, filter: behaviour.filter ?? .all)

        case .openInFrontmost:
            openInFrontmostBrowser(url, context: context, matchedRule: matchedRule)
        }
    }

    /// Called from the picker when user selects a browser
    func recordPickerSelection(url: URL, context: URLContext?, bundleId: String, profileId: String?) {
        guard let context = context else { return }
        recordHistory(url: url, context: context, matchedRule: nil, targetBundleId: bundleId, targetProfileId: profileId)
    }

    func openURL(_ url: URL, bundleId: String, profile: BrowserProfile?, isChromium: Bool) {
        guard let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            print("[HrefTo] Browser not found: \(bundleId)")
            return
        }

        let config = NSWorkspace.OpenConfiguration()

        if let profile = profile, isChromium {
            config.arguments = ["--profile-directory=\(profile.id)", url.absoluteString]
            NSWorkspace.shared.openApplication(at: browserURL, configuration: config)
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: browserURL, configuration: config)
        }
    }

    private func openInFrontmostBrowser(_ url: URL, context: URLContext?, matchedRule: Rule?) {
        let runningApps = NSWorkspace.shared.runningApplications
        let enabledBundleIds = Set(AppConfig.shared.data.browsers.filter(\.enabled).map(\.bundleId))

        if let frontBrowser = runningApps.first(where: {
            $0.isActive && enabledBundleIds.contains($0.bundleIdentifier ?? "")
        }) {
            let bundleId = frontBrowser.bundleIdentifier!
            if let context = context {
                recordHistory(url: url, context: context, matchedRule: matchedRule, targetBundleId: bundleId, targetProfileId: nil)
            }
            openURL(url, bundleId: bundleId, profile: nil, isChromium: false)
        } else {
            // Fallback: use default rule browser
            if let defaultRule = AppConfig.shared.data.rules.last {
                executeBehaviour(defaultRule.behaviour, url: url, context: context, matchedRule: defaultRule)
            }
        }
    }

    func showPicker(url: URL, context: URLContext?, filter: PickerFilter) {
        let config = AppConfig.shared

        // Skip picker if only one browser is running and setting is on
        if config.data.settings.skipPickerForSingleBrowser {
            let runningBundleIds = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let runningBrowsers = config.data.browsers.filter { $0.enabled && runningBundleIds.contains($0.bundleId) }

            if runningBrowsers.count == 1, let browser = runningBrowsers.first {
                let profile = browser.profiles.first(where: \.enabled)
                if let context = context {
                    recordHistory(url: url, context: context, matchedRule: nil, targetBundleId: browser.bundleId, targetProfileId: profile?.id)
                }
                openURL(url, bundleId: browser.bundleId, profile: profile, isChromium: browser.isChromiumBased)
                return
            }
        }

        pendingURL = url
        pendingContext = context
        pickerFilter = filter
        showingPicker = true
    }

    // MARK: - History

    private func recordHistory(url: URL, context: URLContext, matchedRule: Rule?, targetBundleId: String?, targetProfileId: String?) {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let weekdayIndex = calendar.component(.weekday, from: now)
        let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

        let targetBrowser = AppConfig.shared.data.browsers.first { $0.bundleId == targetBundleId }

        let entry = LinkHistoryEntry(
            id: UUID(),
            timestamp: now,
            url: url.absoluteString,
            scheme: url.scheme ?? "",
            host: url.host ?? "",
            path: url.path,
            query: url.query ?? "",
            sourceBundleId: context.sourceApp?.bundleIdentifier ?? "",
            sourceAppName: context.sourceApp?.localizedName ?? "",
            modifiers: context.modifiers,
            timeOfDay: String(format: "%02d:%02d", hour, minute),
            dayOfWeek: dayNames[weekdayIndex - 1],
            runningApps: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier),
            matchedRuleId: matchedRule?.id,
            matchedRuleName: matchedRule?.name,
            targetBundleId: targetBundleId,
            targetProfileId: targetProfileId,
            targetBrowserName: targetBrowser?.name
        )

        LinkHistory.shared.record(entry: entry)
    }

    // MARK: - Internal Scheme

    private func handleInternalScheme(_ url: URL) {
        guard let host = url.host else { return }
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "open":
            guard let urlString = params.first(where: { $0.name == "url" })?.value,
                  let targetURL = URL(string: urlString),
                  let bundleId = params.first(where: { $0.name == "browser" })?.value else { return }
            let profileId = params.first(where: { $0.name == "profile" })?.value
            let browser = AppConfig.shared.data.browsers.first { $0.bundleId == bundleId }
            let profile = browser?.profiles.first { $0.id == profileId }
            openURL(targetURL, bundleId: bundleId, profile: profile, isChromium: browser?.isChromiumBased ?? false)

        case "pick":
            guard let urlString = params.first(where: { $0.name == "url" })?.value,
                  let targetURL = URL(string: urlString) else { return }
            showPicker(url: targetURL, context: nil, filter: .all)

        case "toggle":
            AppConfig.shared.data.settings.enabled.toggle()
            AppConfig.shared.save()

        default:
            break
        }
    }
}
