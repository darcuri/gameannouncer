import AppKit

/// Development aid for README screenshots and visual checks:
///
///     GameAnnouncer -demo YES -snapshotDir <folder> [-snapshotAppearance light|dark]
///
/// Once the first update has loaded, it sizes the window, captures each tab to
/// `<folder>/<tab>-<appearance>.png` with `screencapture`, and quits. Capturing the real
/// window needs Screen Recording permission for whatever launched the app (e.g. Terminal).
@MainActor
enum Snapshots {
    /// Applied at launch, before any window appears, so every tab renders in it.
    static func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "snapshotAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    static func runIfRequested(_ session: LiveSession) async {
        guard let dir = UserDefaults.standard.string(forKey: "snapshotDir") else { return }
        let folder = URL(filePath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let appearance = UserDefaults.standard.string(forKey: "snapshotAppearance")
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light")

        while session.lastUpdate == nil {
            try? await Task.sleep(for: .seconds(1))
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title.hasPrefix("GameAnnouncer") }) else {
            print("no GameAnnouncer window to capture")
            NSApp.terminate(nil)
            return
        }
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()

        for tab in RootTab.allCases {
            session.selectedTab = tab
            try? await Task.sleep(for: .seconds(1.5))
            let path = folder.appending(path: "\(tab.rawValue)-\(appearance).png").path(percentEncoded: false)
            let capture = Process()
            capture.executableURL = URL(filePath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? capture.run()
            capture.waitUntilExit()
            print(capture.terminationStatus == 0 ? "captured \(path)" : "screencapture failed for \(path)")
        }
        NSApp.terminate(nil)
    }
}
