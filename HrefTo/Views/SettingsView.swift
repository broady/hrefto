import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            BrowsersTab()
                .tabItem { Label("Browsers", systemImage: "globe") }

            RulesTab()
                .tabItem { Label("Rules", systemImage: "list.bullet") }
        }
        .frame(minWidth: 550, minHeight: 400)
    }
}
