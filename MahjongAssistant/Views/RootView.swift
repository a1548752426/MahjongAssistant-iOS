import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            AssistantView()
                .tabItem {
                    Label("助手", systemImage: "viewfinder")
                }
            RulesView()
                .tabItem {
                    Label("规则", systemImage: "switch.2")
                }
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
    }
}

