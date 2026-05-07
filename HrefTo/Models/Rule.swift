import Foundation

enum MatchMode: String, Codable, CaseIterable {
    case all
    case any
    case none
}

enum ConditionField: String, Codable, CaseIterable {
    case url
    case scheme
    case host
    case path
    case query
    case fragment
    case sourceApp
    case sourceBundleId
    case sourceName
    case modifiers
    case runningBrowserCount
    case isLocalFile
    case isHandoff
    case timeOfDay       // "HH:mm" format, e.g. "09:30"
    case dayOfWeek       // "mon", "tue", "wed", "thu", "fri", "sat", "sun"
    case runningApps     // space-separated bundle IDs of all running apps
}

enum ConditionOperator: String, Codable, CaseIterable {
    case equals
    case notEquals
    case contains
    case beginsWith
    case endsWith
    case matches  // regex

    var displayName: String {
        switch self {
        case .equals: return "is"
        case .notEquals: return "is not"
        case .contains: return "contains"
        case .beginsWith: return "begins with"
        case .endsWith: return "ends with"
        case .matches: return "matches (regex)"
        }
    }
}

struct Condition: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var field: ConditionField
    var `operator`: ConditionOperator
    var value: String
}

enum BehaviourType: String, Codable {
    case openInBrowser
    case showPicker
    case openInFrontmost
}

enum PickerFilter: String, Codable {
    case all
    case running
}

struct Behaviour: Codable, Hashable {
    var type: BehaviourType
    var bundleId: String?       // for openInBrowser
    var profileId: String?      // for openInBrowser with profile
    var filter: PickerFilter?   // for showPicker
}

/// Hosts where we treat the first two path segments as a "repository"
/// identifier (e.g. github.com/org/repo), so the picker can offer a
/// per-repo "always open in X" rule.
enum PathPrefixHost {
    static let supported: Set<String> = ["github.com"]

    /// Returns the canonical host and `/seg1/seg2` prefix when the URL
    /// matches a supported host and has at least two path segments.
    static func extract(from url: URL) -> (host: String, prefix: String)? {
        guard let rawHost = url.host?.lowercased() else { return nil }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        guard supported.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (host, "/\(parts[0])/\(parts[1])")
    }
}

struct Rule: Codable, Identifiable {
    var id: String
    var name: String
    var enabled: Bool
    var matchMode: MatchMode
    var conditions: [Condition]
    var behaviour: Behaviour

    var isDefault: Bool { id == "default" }

    static func makeDefault(browserBundleId: String) -> Rule {
        Rule(
            id: "default",
            name: "Default",
            enabled: true,
            matchMode: .all,
            conditions: [],
            behaviour: Behaviour(type: .openInBrowser, bundleId: browserBundleId, profileId: nil, filter: nil)
        )
    }
}
