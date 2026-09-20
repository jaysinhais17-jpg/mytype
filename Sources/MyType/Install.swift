import AppKit

/// First-run housekeeping for a downloaded copy: macOS ties privacy permissions to where the app lives, and runs
/// apps opened straight from a disk image or Downloads from a temporary translocated path, so the permissions
/// you grant would not stick. Offer to move the app into Applications and open it from there.
enum InstallCheck {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    private static var inApplications: Bool {
        let p = Bundle.main.bundlePath
        return p.hasPrefix("/Applications/") || p.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// Returns true if the app is relaunching from Applications and this process should stop starting up.
    static func offerMove() -> Bool {
        guard !inApplications, ProcessInfo.processInfo.environment["MYTYPE_SETUP"] == nil else { return false }
        let path = Bundle.main.bundlePath
        guard path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/") || path.contains("/Downloads/") else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Move MyType to Applications?"
        a.informativeText = "MyType needs to live in your Applications folder so macOS remembers the permissions you give it. It takes a second, then MyType opens from there."
        a.addButton(withTitle: "Move to Applications")
        a.addButton(withTitle: "Not now")
        guard a.runModal() == .alertFirstButtonReturn else { return false }

        let fm = FileManager.default
        let candidates = ["/Applications", NSHomeDirectory() + "/Applications"]
        for dir in candidates {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let dest = dir + "/MyType.app"
            try? fm.removeItem(atPath: dest)
            guard (try? fm.copyItem(atPath: path, toPath: dest)) != nil else { continue }
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest])
            run("/usr/bin/open", ["-n", dest])
            NSApp.terminate(nil)
            return true
        }
        let f = NSAlert()
        f.messageText = "Couldn't move MyType"
        f.informativeText = "Drag MyType into your Applications folder yourself, then open it from there."
        f.runModal()
        return false
    }

    private static func run(_ tool: String, _ args: [String]) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        try? p.run(); p.waitUntilExit()
    }
}
