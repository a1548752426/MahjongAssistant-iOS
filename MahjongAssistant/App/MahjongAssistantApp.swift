import SwiftUI

@main
struct MahjongAssistantApp: App {
    @StateObject private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Color("AccentColor"))
                .preferredColorScheme(.light)
        }
    }
}

