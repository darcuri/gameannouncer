import AppKit

/// Development aid: `GameDay -snapshotDir <folder>` saves a PNG of the window for each tab
/// once the first update has loaded. It draws the app's own view hierarchy, so it needs no
/// Screen Recording permission.
@MainActor
enum Snapshots {
    static func runIfRequested(_ session: LiveSession) async {
        guard let dir = UserDefaults.standard.string(forKey: "snapshotDir") else { return }
        let folder = URL(filePath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        while session.lastUpdate == nil {
            try? await Task.sleep(for: .seconds(1))
        }
        for tab in RootTab.allCases {
            session.selectedTab = tab
            try? await Task.sleep(for: .seconds(2))
            capture(to: folder.appending(path: "\(tab.rawValue).png"))
        }
        print("snapshots written to \(folder.path(percentEncoded: false))")
    }

    private static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.title.hasPrefix("GameDay") }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
