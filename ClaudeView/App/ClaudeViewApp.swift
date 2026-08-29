import SwiftUI

@main
struct ClaudeViewApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updater = UpdaterModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .tint(appState.theme.accent.color)
                .preferredColorScheme(appState.theme.colorScheme)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updater: updater)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .tint(appState.theme.accent.color)
        }
    }
}
