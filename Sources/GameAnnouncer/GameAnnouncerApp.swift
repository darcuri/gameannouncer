import AppKit
import SwiftUI

@main
struct GameAnnouncerApp: App {
    @State private var session: LiveSession

    init() {
        // scripts/make-app.sh renders the icon through the app itself.
        if let flag = CommandLine.arguments.firstIndex(of: "--render-icon"),
           CommandLine.arguments.indices.contains(flag + 1) {
            do {
                try AppIcon.writePNG(to: URL(filePath: CommandLine.arguments[flag + 1]))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("couldn't render icon: \(error)\n".utf8))
                exit(1)
            }
        }

        let bundled = Bundle.main.bundleURL.pathExtension == "app"
        if bundled {
            Self.adoptUnbundledSettings()
        } else {
            // `swift run` has no bundle: ask for a normal Dock app and supply the icon.
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.applicationIconImage = AppIcon.image()
        }
        _session = State(initialValue: LiveSession())
    }

    /// GameAnnouncer.app keeps its settings under its bundle ID, while `swift run` builds use the
    /// "GameAnnouncer" domain. On the bundled app's first launch, copy the league setup across.
    private static func adoptUnbundledSettings() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "leagueID") == nil,
              let unbundled = UserDefaults(suiteName: "GameAnnouncer"),
              unbundled.string(forKey: "leagueID") != nil
        else { return }
        for key in ["leagueID", "franchiseID", "scope", "muted", "mutedCategories", "voice"] {
            if let value = unbundled.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    var body: some Scene {
        WindowGroup("GameAnnouncer") {
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
