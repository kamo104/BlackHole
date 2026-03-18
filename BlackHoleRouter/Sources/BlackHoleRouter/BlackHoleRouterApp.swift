import SwiftUI

@main
struct BlackHoleRouterApp: App {
    @StateObject private var audioManager = AudioManager()

    var body: some Scene {
        WindowGroup("BlackHole Router") {
            ContentView()
                .environmentObject(audioManager)
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Audio") {
                Button("Refresh Devices") {
                    audioManager.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
