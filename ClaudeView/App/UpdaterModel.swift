import SwiftUI
import Sparkle

/// Wraps Sparkle's standard updater for SwiftUI (menu command + auto checks).
@MainActor
final class UpdaterModel: ObservableObject {
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    @Published var canCheckForUpdates = false

    init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommand: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Button("Rechercher les mises à jour…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
