import SwiftUI

struct QuickRuleSheet: View {
    let url: URL
    let sourceBundleId: String?
    let sourceAppName: String?
    let selectedBrowser: Browser
    let selectedProfile: BrowserProfile?
    let includeSourceApp: Bool
    let onSave: (Rule) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ruleName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Quick Rule")
                .font(.headline)

            TextField("Rule name", text: $ruleName)
                .textFieldStyle(.roundedBorder)

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("When: host ends with \"\(domain)\"")
                    if includeSourceApp, let name = sourceAppName {
                        Text("  and: opened from \(name)")
                    }
                    Text("Then: open in \(targetDescription)")
                }
                .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Rule") {
                    onSave(buildRule())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            ruleName = "\(domain) \u{2192} \(targetDescription)"
        }
    }

    private var domain: String {
        url.host ?? "unknown"
    }

    private var targetDescription: String {
        if let profile = selectedProfile {
            return "\(selectedBrowser.name) (\(profile.name))"
        }
        return selectedBrowser.name
    }

    private func buildRule() -> Rule {
        var conditions: [Condition] = [
            Condition(field: .host, operator: .endsWith, value: domain)
        ]

        if includeSourceApp, let bundleId = sourceBundleId {
            conditions.append(Condition(field: .sourceBundleId, operator: .equals, value: bundleId))
        }

        return Rule(
            id: UUID().uuidString,
            name: ruleName,
            enabled: true,
            matchMode: .all,
            conditions: conditions,
            behaviour: Behaviour(
                type: .openInBrowser,
                bundleId: selectedBrowser.bundleId,
                profileId: selectedProfile?.id,
                filter: nil
            )
        )
    }
}
