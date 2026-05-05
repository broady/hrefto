import SwiftUI

enum SettingsTab: Hashable {
    case general, browsers, rules
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            BrowsersTab()
                .tabItem { Label("Browsers", systemImage: "globe") }
                .tag(SettingsTab.browsers)

            RulesTab()
                .tabItem { Label("Rules", systemImage: "list.bullet") }
                .tag(SettingsTab.rules)
        }
        .frame(minWidth: 550, minHeight: 400)
        .onReceive(NotificationCenter.default.publisher(for: .openRulesTab)) { _ in
            selectedTab = .rules
        }
    }
}
