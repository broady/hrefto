import SwiftUI

struct RuleEditorView: View {
    @State var rule: Rule
    let onSave: (Rule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var predicateText: String = ""
    @State private var predicateError: String?
    @State private var editingPredicate = false

    private let engine = RuleEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Name
            HStack {
                Text("Name:")
                    .frame(width: 80, alignment: .trailing)
                TextField("Rule name", text: $rule.name)
            }

            // Predicate editor — two-way sync between GUI and text
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    // Match mode
                    HStack {
                        Text("Match:")
                        Picker("", selection: $rule.matchMode) {
                            Text("ALL of").tag(MatchMode.all)
                            Text("ANY of").tag(MatchMode.any)
                            Text("NONE of").tag(MatchMode.none)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                        .onChange(of: rule.matchMode) { _, _ in syncToText() }
                        Spacer()
                    }

                    // Structured condition rows
                    ForEach(Array(rule.conditions.enumerated()), id: \.element.id) { index, _ in
                        ConditionRow(condition: $rule.conditions[index]) {
                            rule.conditions.remove(at: index)
                            syncToText()
                        }
                        .onChange(of: rule.conditions[index]) { _, _ in syncToText() }
                    }

                    Button("Add Condition") {
                        rule.conditions.append(Condition(field: .host, operator: .endsWith, value: ""))
                        syncToText()
                    }
                    .font(.caption)

                    Divider()

                    // Predicate text field — editable
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Predicate:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if editingPredicate {
                                Button("Apply") { syncFromText() }
                                    .font(.caption)
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                        }

                        TextField("e.g. host ENDSWITH \"google.com\"", text: $predicateText, axis: .vertical)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .onChange(of: predicateText) { _, _ in
                                editingPredicate = true
                                // Validate live
                                if predicateText.isEmpty {
                                    predicateError = nil
                                } else if engine.validate(predicateString: predicateText) != nil {
                                    predicateError = nil
                                } else {
                                    predicateError = "Invalid predicate syntax"
                                }
                            }

                        if let error = predicateError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(4)
            }
            .disabled(rule.isDefault)

            // Behaviour
            GroupBox("Action") {
                BehaviourEditor(behaviour: $rule.behaviour)
                    .padding(4)
            }

            // Enabled
            Toggle("Enabled", isOn: $rule.enabled)

            Spacer()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(predicateError != nil)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 450)
        .onAppear { syncToText() }
    }

    /// GUI → predicate string
    private func syncToText() {
        guard !rule.conditions.isEmpty else {
            predicateText = ""
            editingPredicate = false
            return
        }
        predicateText = engine.predicateString(for: rule)
        editingPredicate = false
        predicateError = nil
    }

    /// Predicate string → GUI
    private func syncFromText() {
        guard !predicateText.isEmpty else {
            rule.conditions = []
            editingPredicate = false
            predicateError = nil
            return
        }

        if let parsed = engine.parse(predicateString: predicateText) {
            rule.conditions = parsed.conditions
            rule.matchMode = parsed.matchMode
            editingPredicate = false
            predicateError = nil
        } else if engine.validate(predicateString: predicateText) != nil {
            // Valid predicate but can't decompose into GUI — store as single raw condition
            // For now, show a note
            predicateError = "Valid predicate, but too complex for the GUI editor. Conditions left unchanged."
        } else {
            predicateError = "Invalid predicate syntax"
        }
    }
}

struct ConditionRow: View {
    @Binding var condition: Condition
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Picker("", selection: $condition.field) {
                ForEach(ConditionField.allCases, id: \.self) { field in
                    Text(field.rawValue).tag(field)
                }
            }
            .frame(width: 140)

            Picker("", selection: $condition.operator) {
                ForEach(ConditionOperator.allCases, id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 120)

            TextField("value", text: $condition.value)
                .textFieldStyle(.roundedBorder)

            Button(action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }
}

struct BehaviourEditor: View {
    @Binding var behaviour: Behaviour
    @ObservedObject private var config = AppConfig.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action:", selection: $behaviour.type) {
                Text("Open in browser").tag(BehaviourType.openInBrowser)
                Text("Show picker").tag(BehaviourType.showPicker)
                Text("Open in frontmost").tag(BehaviourType.openInFrontmost)
            }
            .frame(width: 300)

            switch behaviour.type {
            case .openInBrowser:
                Picker("Browser:", selection: Binding(
                    get: { behaviour.bundleId ?? "" },
                    set: { behaviour.bundleId = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Select...").tag("")
                    ForEach(config.data.browsers) { browser in
                        Text(browser.name).tag(browser.bundleId)
                    }
                }
                .frame(width: 300)

                if let bundleId = behaviour.bundleId,
                   let browser = config.data.browsers.first(where: { $0.bundleId == bundleId }),
                   !browser.profiles.isEmpty {
                    Picker("Profile:", selection: Binding(
                        get: { behaviour.profileId ?? "" },
                        set: { behaviour.profileId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Any").tag("")
                        ForEach(browser.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .frame(width: 300)
                }

            case .showPicker:
                Picker("Show:", selection: Binding(
                    get: { behaviour.filter ?? .all },
                    set: { behaviour.filter = $0 }
                )) {
                    Text("All browsers").tag(PickerFilter.all)
                    Text("Running only").tag(PickerFilter.running)
                }
                .frame(width: 300)

            case .openInFrontmost:
                Text("Opens the URL in whichever enabled browser is currently active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
