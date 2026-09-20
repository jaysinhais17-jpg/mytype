import AppKit

/// Self-update from GitHub Releases: ask for the latest release, and if it's newer download the DMG, swap the app in place and relaunch.
/// Needs no server or signing keys; the release.sh workflow is the whole publishing process.
enum Updater {
    private static let api = URL(string: "https://api.github.com/repos/jaysinhais17-jpg/mytype/releases/latest")!
    private static let releasePage = URL(string: "https://github.com/jaysinhais17-jpg/mytype/releases/latest")!

    struct Release { let version: String; let dmg: URL; let notes: String }

    private(set) static var available: Release?
    private static var busy = false
    /// Called on the main thread whenever `available` changes (the menu listens to show "Update to vX").
    static var onChange: (() -> Void)?

    /// Numeric compare of dotted versions: "1.10" > "1.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Quietly check at launch and every few hours. `manual` checks always report the result.
    static func startAutoChecks(isBusy: @escaping () -> Bool) {
        func go() { if !isBusy() { check(manual: false) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { go() }
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in go() }
    }

    static func check(manual: Bool) {
        guard !busy else { return }
        busy = true
        var req = URLRequest(url: api, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var found: Release?
            if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = j["tag_name"] as? String,
               let assets = j["assets"] as? [[String: Any]],
               let dmg = assets.first(where: { ($0["name"] as? String) == "MyType.dmg" }),
               let url = (dmg["browser_download_url"] as? String).flatMap(URL.init(string:)) {
                found = Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, dmg: url, notes: (j["body"] as? String) ?? "")
            }
            let reachable = found != nil
            DispatchQueue.main.async {
                busy = false
                let current = InstallCheck.version
                if let f = found, current != "dev", isNewer(f.version, than: current) {
                    available = f; onChange?()
                    let key = "updateOffered"
                    if manual || UserDefaults.standard.string(forKey: key) != f.version {
                        UserDefaults.standard.set(f.version, forKey: key)
                        offer(f)
                    }
                } else {
                    available = nil; onChange?()
                    if manual { info(reachable ? "MyType is up to date" : "Couldn't check for updates",
                                    reachable ? "You have the latest version (\(current))." : "Check your internet connection and try again.") }
                }
            }
        }.resume()
    }

    private static func info(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }

    static func offer(_ r: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "MyType \(r.version) is available"
        let notes = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        a.informativeText = "You have \(InstallCheck.version). MyType will download the update, replace itself and reopen. Your keys, dictionary and history stay as they are."
            + (notes.isEmpty ? "" : "\n\nWhat's new: \(notes.prefix(300))")
        a.addButton(withTitle: "Update and restart")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn { install(r) }
    }

    static func install(_ r: Release) {
        let dest = Bundle.main.bundlePath
        guard FileManager.default.isWritableFile(atPath: (dest as NSString).deletingLastPathComponent) else {
            NSWorkspace.shared.open(releasePage); return
        }
        NSApp.dockTile.badgeLabel = "…"
        URLSession.shared.downloadTask(with: r.dmg) { tmp, _, _ in
            var ok = false
            if let tmp { ok = swap(dmg: tmp, into: dest) }
            DispatchQueue.main.async {
                NSApp.dockTile.badgeLabel = nil
                if ok { NSApp.terminate(nil) }
                else {
                    info("Update failed", "MyType couldn't install the update by itself. Opening the download page instead.")
                    NSWorkspace.shared.open(releasePage)
                }
            }
        }.resume()
    }

    private static func sh(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit(); return p.terminationStatus
    }

    /// Mounts the DMG, stages the new app, then starts a detached script that waits for this process to quit, replaces the app and reopens it.
    private static func swap(dmg: URL, into dest: String) -> Bool {
        let fm = FileManager.default
        let work = NSTemporaryDirectory() + "mytype-update-\(getpid())"
        let mount = work + "/mnt", stage = work + "/MyType.app"
        try? fm.createDirectory(atPath: mount, withIntermediateDirectories: true)
        let img = work + "/MyType.dmg"
        try? fm.moveItem(at: dmg, to: URL(fileURLWithPath: img))
        guard sh("/usr/bin/hdiutil", ["attach", img, "-nobrowse", "-readonly", "-mountpoint", mount]) == 0 else { return false }
        defer { _ = sh("/usr/bin/hdiutil", ["detach", mount, "-force"]) }
        guard sh("/usr/bin/ditto", [mount + "/MyType.app", stage]) == 0,
              fm.fileExists(atPath: stage + "/Contents/MacOS/MyType") else { return false }
        _ = sh("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stage])
        let script = """
        while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
        rm -rf '\(dest)' && /usr/bin/ditto '\(stage)' '\(dest)' && /usr/bin/xattr -dr com.apple.quarantine '\(dest)'
        /usr/bin/open '\(dest)'
        rm -rf '\(work)'
        """
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        return (try? p.run()) != nil
    }
}
