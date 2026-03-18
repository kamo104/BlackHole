import SwiftUI

@main
struct BlackHoleRouterApp: App {
    @StateObject private var audioManager   = AudioManager()
    @StateObject private var processManager = ProcessAudioManager()
    @StateObject private var routingEngine  = RoutingEngine()

    var body: some Scene {
        WindowGroup("BlackHole Router") {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(processManager)
                .environmentObject(routingEngine)
                .frame(minWidth: 980, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Audio") {
                Button("Refresh Devices & Apps") {
                    audioManager.refresh()
                    processManager.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
