import SwiftUI

struct RulesTab: View {
    @ObservedObject private var config = AppConfig.shared
    @State private var selectedRuleId: String?
    @State private var editingRule: Rule?

    var body: some View {
        VStack {
            List(selection: $selectedRuleId) {
                ForEach(config.data.rules) { rule in
                    RuleListRow(rule: rule)
                        .tag(rule.id)
                }
                .onMove { source, destination in
                    // Don't allow moving past the default rule
                    let maxDest = config.data.rules.count - 1
                    let clampedDest = min(destination, maxDest)
                    config.data.rules.move(fromOffsets: source, toOffset: clampedDest)
                    config.save()
                }
            }
            .onKeyPress(.return) {
                if let id = selectedRuleId,
                   let rule = config.data.rules.first(where: { $0.id == id }) {
                    editingRule = rule
                }
                return .handled
            }

            HStack {
                Button(action: addRule) {
                    Image(systemName: "plus")
                }

                Button(action: removeSelectedRule) {
                    Image(systemName: "minus")
                }
                .disabled(selectedRuleId == nil || selectedRuleId == "default")

                Spacer()

                Button("Edit") {
                    if let id = selectedRuleId,
                       let rule = config.data.rules.first(where: { $0.id == id }) {
                        editingRule = rule
                    }
                }
                .disabled(selectedRuleId == nil)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(item: $editingRule) { rule in
            RuleEditorView(rule: rule) { updatedRule in
                if let index = config.data.rules.firstIndex(where: { $0.id == updatedRule.id }) {
                    config.data.rules[index] = updatedRule
                    config.save()
                }
                editingRule = nil
            }
        }
    }

    private func addRule() {
        let newRule = Rule(
            id: UUID().uuidString,
            name: "New Rule",
            enabled: true,
            matchMode: .all,
            conditions: [Condition(field: .host, operator: .endsWith, value: "example.com")],
            behaviour: Behaviour(type: .showPicker, bundleId: nil, profileId: nil, filter: .all)
        )
        // Insert before the default rule
        let insertIndex = max(0, config.data.rules.count - 1)
        config.data.rules.insert(newRule, at: insertIndex)
        config.save()
        selectedRuleId = newRule.id
        editingRule = newRule
    }

    private func removeSelectedRule() {
        guard let id = selectedRuleId, id != "default" else { return }
        config.data.rules.removeAll { $0.id == id }
        config.save()
        selectedRuleId = nil
    }
}

struct RuleListRow: View {
    let rule: Rule

    var body: some View {
        HStack {
            Circle()
                .fill(rule.enabled ? .green : .gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading) {
                Text(rule.name)
                    .font(.body)

                Text(ruleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if rule.isDefault {
                Text("Default")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var ruleSummary: String {
        if rule.conditions.isEmpty { return "Always matches" }
        let parts = rule.conditions.prefix(2).map { "\($0.field.rawValue) \($0.operator.displayName) \"\($0.value)\"" }
        let summary = parts.joined(separator: " \(rule.matchMode.rawValue.uppercased()) ")
        if rule.conditions.count > 2 { return summary + " ..." }
        return summary
    }
}
