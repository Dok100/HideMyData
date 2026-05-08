import SwiftUI

@main
struct HideMyDataApp: App {
    @State private var updater = UpdaterModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(updater)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen…") {
                    updater.checkForUpdates()
                }
            }
        }
    }
}
