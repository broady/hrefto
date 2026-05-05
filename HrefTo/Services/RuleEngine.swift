import Foundation
import AppKit

struct URLContext {
    let url: URL
    let sourceApp: NSRunningApplication?
    let modifiers: String  // space-separated: "shift option command control function"
    let runningBrowserCount: Int
    let isHandoff: Bool

    /// Build the dictionary used for NSPredicate evaluation
    var dictionary: [String: Any] {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let timeOfDay = String(format: "%02d:%02d", hour, minute)

        let weekdayIndex = calendar.component(.weekday, from: now)  // 1=Sun, 2=Mon, ...
        let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let dayOfWeek = dayNames[weekdayIndex - 1]

        let runningApps = NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
            .joined(separator: " ")

        return [
            "url": url.absoluteString,
            "scheme": url.scheme ?? "",
            "host": url.host ?? "",
            "path": url.path,
            "query": url.query ?? "",
            "fragment": url.fragment ?? "",
            "sourceApp": sourceApp?.bundleURL?.path ?? "",
            "sourceBundleId": sourceApp?.bundleIdentifier ?? "",
            "sourceName": sourceApp?.localizedName ?? "",
            "modifiers": modifiers,
            "runningBrowserCount": runningBrowserCount,
            "isLocalFile": url.isFileURL,
            "isHandoff": isHandoff,
            "timeOfDay": timeOfDay,
            "dayOfWeek": dayOfWeek,
            "runningApps": runningApps,
        ]
    }
}

class RuleEngine {
    /// Evaluate rules in order, return the first matching rule
    func evaluate(rules: [Rule], context: URLContext) -> Rule? {
        let dict = context.dictionary as NSDictionary

        for rule in rules where rule.enabled {
            if rule.conditions.isEmpty {
                // Empty conditions = always matches (default rule)
                return rule
            }

            let predicate = compilePredicate(conditions: rule.conditions, matchMode: rule.matchMode)
            if predicate.evaluate(with: dict) {
                return rule
            }
        }
        return nil
    }

    /// Compile conditions into an NSPredicate
    func compilePredicate(conditions: [Condition], matchMode: MatchMode) -> NSPredicate {
        guard !conditions.isEmpty else {
            return NSPredicate(value: true)
        }

        let predicates = conditions.map { condition -> NSPredicate in
            switch condition.operator {
            case .endsWith:
                return NSPredicate(format: "%K ENDSWITH[cd] %@", condition.field.rawValue, condition.value)
            case .beginsWith:
                return NSPredicate(format: "%K BEGINSWITH[cd] %@", condition.field.rawValue, condition.value)
            case .contains:
                return NSPredicate(format: "%K CONTAINS[cd] %@", condition.field.rawValue, condition.value)
            case .equals:
                return NSPredicate(format: "%K ==[cd] %@", condition.field.rawValue, condition.value)
            case .notEquals:
                return NSPredicate(format: "%K !=[cd] %@", condition.field.rawValue, condition.value)
            case .matches:
                return NSPredicate(format: "%K MATCHES %@", condition.field.rawValue, condition.value)
            }
        }

        switch matchMode {
        case .all:
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        case .any:
            return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        case .none:
            return NSCompoundPredicate(notPredicateWithSubpredicate:
                NSCompoundPredicate(orPredicateWithSubpredicates: predicates))
        }
    }

    /// Generate a human-readable predicate string for display
    func predicateString(for rule: Rule) -> String {
        let predicate = compilePredicate(conditions: rule.conditions, matchMode: rule.matchMode)
        return predicate.predicateFormat
    }

    // MARK: - Parse predicate string back into structured conditions

    /// Parse a predicate format string into conditions and match mode.
    /// Returns nil if parsing fails.
    func parse(predicateString: String) -> (conditions: [Condition], matchMode: MatchMode)? {
        guard let predicate = try? NSPredicate(format: predicateString) else { return nil }
        return decompose(predicate)
    }

    private func decompose(_ predicate: NSPredicate) -> (conditions: [Condition], matchMode: MatchMode)? {
        if let comparison = predicate as? NSComparisonPredicate {
            if let condition = decomposeComparison(comparison) {
                return ([condition], .all)
            }
            return nil
        }

        if let compound = predicate as? NSCompoundPredicate {
            switch compound.compoundPredicateType {
            case .and:
                let conditions = compound.subpredicates.compactMap { sub -> Condition? in
                    guard let comp = sub as? NSComparisonPredicate else { return nil }
                    return decomposeComparison(comp)
                }
                guard conditions.count == compound.subpredicates.count else { return nil }
                return (conditions, .all)

            case .or:
                let conditions = compound.subpredicates.compactMap { sub -> Condition? in
                    guard let comp = sub as? NSComparisonPredicate else { return nil }
                    return decomposeComparison(comp)
                }
                guard conditions.count == compound.subpredicates.count else { return nil }
                return (conditions, .any)

            case .not:
                // NOT(OR(...)) = .none match mode
                if let inner = compound.subpredicates.first as? NSCompoundPredicate,
                   inner.compoundPredicateType == .or {
                    let conditions = inner.subpredicates.compactMap { sub -> Condition? in
                        guard let comp = sub as? NSComparisonPredicate else { return nil }
                        return decomposeComparison(comp)
                    }
                    guard conditions.count == inner.subpredicates.count else { return nil }
                    return (conditions, .none)
                }
                return nil

            @unknown default:
                return nil
            }
        }

        return nil
    }

    private func decomposeComparison(_ comparison: NSComparisonPredicate) -> Condition? {
        // Left side should be a keypath expression
        guard comparison.leftExpression.expressionType == .keyPath else { return nil }
        let fieldName = comparison.leftExpression.keyPath

        // Right side should be a constant value
        guard comparison.rightExpression.expressionType == .constantValue else { return nil }
        let value = comparison.rightExpression.constantValue as? String ?? "\(comparison.rightExpression.constantValue ?? "")"

        // Map field name to our enum
        guard let field = ConditionField(rawValue: fieldName) else { return nil }

        // Map operator type
        let op: ConditionOperator?
        switch comparison.predicateOperatorType {
        case .equalTo:
            op = .equals
        case .notEqualTo:
            op = .notEquals
        case .contains:
            op = .contains
        case .beginsWith:
            op = .beginsWith
        case .endsWith:
            op = .endsWith
        case .matches:
            op = .matches
        default:
            op = nil
        }

        guard let conditionOp = op else { return nil }
        return Condition(field: field, operator: conditionOp, value: value)
    }

    /// Validate a predicate string without decomposing it.
    /// Returns the parsed NSPredicate if valid, nil otherwise.
    func validate(predicateString: String) -> NSPredicate? {
        return try? NSPredicate(format: predicateString)
    }
}
