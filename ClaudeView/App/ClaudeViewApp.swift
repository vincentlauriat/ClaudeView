import SwiftUI

@main
struct ClaudeViewApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .tint(appState.theme.accent.color)
                .preferredColorScheme(appState.theme.colorScheme)
        }
        .windowStyle(.automatic)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .tint(appState.theme.accent.color)
        }
    }
}
