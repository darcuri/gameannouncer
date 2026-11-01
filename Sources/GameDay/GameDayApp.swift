import AppKit
import SwiftUI

@main
struct GameDayApp: App {
    @State private var session = LiveSession()

    init() {
        // Built with SwiftPM rather than as an .app bundle, so ask for a normal Dock app.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("GameDay") {
            RootView()
                .environment(session)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear { NSApplication.shared.activate() }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh Now") { session.refreshNow() }
                    .keyboardShortcut("r")
                Toggle("Mute Announcements", isOn: $session.muted)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(session)
        }
    }
}
