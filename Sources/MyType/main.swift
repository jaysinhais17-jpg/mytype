import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement

final class App: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let polisher = Polisher()
    private let cloudPolisher = CloudPolisher()
    private var deepgram: DeepgramSession?
    private lazy var streamer = Streamer(recorder: recorder, transcriber: transcriber)
    private let hotkey = Hotkey()
    private let hud = HUD()
    private var window: MainWindow!
    private var recording = false
    private var locked = false // hands-free mode after a quick tap
    private var pressStart = Date()
    private var lastTapUp = Date.distantPast
    private var hudWork: DispatchWorkItem?
    private let statusLine = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
    private let llmLine = NSMenuItem(title: "AI cleanup: loading…", action: nil, keyEquivalent: "")
    private let aiItem = NSMenuItem(title: "AI cleanup", action: #selector(toggleAIMenu), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLoginMenu), keyEquivalent: "")

    private(set) var keySeen = false
    var hotkeyInstalled: Bool { hotkey.installed }
    var statusText: String { statusLine.title }
    var llmText: String { llmLine.title }

    var aiEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "aiCleanup") as? Bool ?? Cloud.useLLM }
        set {
            UserDefaults.standard.set(newValue, forKey: "aiCleanup")
            aiItem.state = newValue ? .on : .off
            refreshAI()
        }
    }
    var autoLanguage: Bool {
        get { transcriber.language == "auto" }
        set { UserDefaults.standard.set(newValue ? "auto" : "en", forKey: "language") }
    }
    var loginEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func applicationDidFinishLaunching(_ n: Notification) {
        setIcon("mic.slash")
        buildMenu()
        buildMainMenu()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        recorder.onLevel = { [weak self] v in self?.hud.level(v) }
        hotkey.onDown = { [weak self] in self?.keyDown() }
        hotkey.onUp = { [weak self] in self?.keyUp() }
        hotkey.onEvent = { [weak self] _, _ in self?.keySeen = true }
        // Keep trying until Input Monitoring is granted — no relaunch needed.
        _ = hotkey.install()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.hotkey.installed, CGPreflightListenEventAccess() else { return }
            _ = self.hotkey.install()
        }

        window = MainWindow(app: self)
        window.show()

        transcriber.startServer { [weak self] ok in
            guard let self else { return }
            self.setIcon(ok ? "mic" : "exclamationmark.triangle")
            self.statusLine.title = ok ? "Ready" : "Speech server failed (whisper-cpp + model installed?)"
        }

        refreshAI()
    }

    var engineText: String { Cloud.useDeepgram ? "Speech: Deepgram" : "Speech: on-device" }

    /// Called at launch and whenever the toggle or cloud keys change.
    func refreshAI() {
        if !aiEnabled { stopPolisher() }
        else if Cloud.useLLM { polisher.stop(); llmLine.title = "AI cleanup ready (cloud)" }
        else if !polisher.ready { startPolisher() }
    }

    private func startPolisher() {
        guard Polisher.available else { llmLine.title = "AI cleanup not installed"; return }
        llmLine.title = "AI cleanup loading…"
        polisher.start { [weak self] ok in
            self?.llmLine.title = ok ? "AI cleanup ready" : "AI cleanup failed to start"
        }
    }

    private func stopPolisher() {
        polisher.stop()
        llmLine.title = "AI cleanup off"
    }

    func applicationWillTerminate(_ n: Notification) {
        transcriber.stopServer()
        polisher.stop()
    }

    /// Dock icon click / re-opening from Spotlight.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.show()
        return false
    }

    private func setIcon(_ name: String) {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "MyType")
        statusItem.button?.image = img
        statusItem.button?.title = img == nil ? "🎙" : ""
    }

    private func buildMenu() {
        let m = NSMenu()
        let open = NSMenuItem(title: "Open MyType", action: #selector(openWindow), keyEquivalent: "")
        open.target = self
        m.addItem(open)
        m.addItem(.separator())
        m.addItem(statusLine)
        m.addItem(llmLine)
        m.addItem(.separator())
        aiItem.target = self; aiItem.state = aiEnabled ? .on : .off
        m.addItem(aiItem)
        loginItem.target = self; loginItem.state = loginEnabled ? .on : .off
        m.addItem(loginItem)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit MyType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = m
    }

    private func buildMainMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [(String, Selector, String)]) {
            let host = NSMenuItem(); main.addItem(host)
            let sub = NSMenu(title: title)
            for (t, sel, key) in items {
                if t == "-" { sub.addItem(.separator()) } else { sub.addItem(withTitle: t, action: sel, keyEquivalent: key) }
            }
            host.submenu = sub
        }
        add("MyType", [("Hide MyType", #selector(NSApplication.hide(_:)), "h"), ("-", #selector(NSApplication.hide(_:)), ""),
                       ("Quit MyType", #selector(NSApplication.terminate(_:)), "q")])
        add("Edit", [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])
        add("Window", [("Close", #selector(NSWindow.performClose(_:)), "w"), ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.mainMenu = main
    }

    @objc private func openWindow() { window.show() }
    @objc private func toggleAIMenu() { aiEnabled.toggle() }
    @objc private func toggleLoginMenu() {
        _ = setLogin(!loginEnabled)
        loginItem.state = loginEnabled ? .on : .off
    }

    /// Returns an error description on failure.
    func setLogin(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch { return error.localizedDescription }
    }

    // MARK: recording

    /// Hold Fn = push-to-talk. Double-tap Fn = hands-free (tap once more to stop).
    private func keyDown() {
        if recording && locked { locked = false; finish(); return }
        guard !recording else { return }
        pressStart = Date()
        let isDouble = Date().timeIntervalSince(lastTapUp) < Config.doubleTapSeconds
        begin(showAfter: isDouble ? 0 : Config.tapSeconds)
        if isDouble && recording { locked = true }
    }

    private func keyUp() {
        guard recording, !locked else { return }
        if Date().timeIntervalSince(pressStart) < Config.tapSeconds {
            cancelRecording()
            lastTapUp = Date()
        } else { finish() }
    }

    func beginManual() { if !recording { begin(showAfter: 0) } }
    func finishManual() { locked = false; finish() }

    private func begin(showAfter delay: TimeInterval) {
        guard transcriber.ready, !recording else { return }
        do {
            try recorder.start()
            recording = true
            if Cloud.aiReady { CloudPolisher.warm() }
            if Cloud.useDeepgram {
                let d = DeepgramSession(recorder: recorder)
                d.start(language: transcriber.language == "auto" ? "multi" : "en")
                deepgram = d
            } else { streamer.start() }
            setIcon("waveform.circle.fill")
            let show = DispatchWorkItem { [weak self] in
                self?.hud.set(.listening)
                NSSound(named: "Tink")?.play()
            }
            hudWork = show
            if delay == 0 { show.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: show) }
        } catch { setIcon("exclamationmark.triangle") }
    }

    private func cancelRecording() {
        hudWork?.cancel(); hudWork = nil
        recording = false; locked = false
        _ = recorder.stop()
        streamer.cancel()
        deepgram?.cancel(); deepgram = nil
        setIcon("mic"); hud.set(.hidden)
    }

    private func finish() {
        guard recording else { return }
        hudWork?.cancel(); hudWork = nil
        recording = false
        locked = false
        let samples = recorder.stop()
        let secs = Double(samples.count) / Config.sampleRate
        guard secs >= Config.minSeconds, Audio.rms(samples) > Config.silenceRMS else {
            streamer.cancel(); deepgram?.cancel(); deepgram = nil; setIcon("mic"); hud.set(.hidden); return
        }
        setIcon("ellipsis.circle")
        hud.set(.working)
        let useAI = aiEnabled
        let dg = deepgram; deepgram = nil
        let t0 = Date()
        Task {
            defer { DispatchQueue.main.async { self.setIcon("mic"); self.hud.set(.hidden) } }
            let raw: String
            if let dg {
                if let t = await dg.finish(allSamples: samples) { raw = t } else { raw = await streamer.transcribeAll(samples) }
            } else { raw = await streamer.finish(allSamples: samples) }
            let t1 = Date()
            var cleaned = TextCleaner.clean(raw)
            guard !cleaned.isEmpty else { return }
            if useAI { cleaned = Cloud.useLLM ? await cloudPolisher.polish(cleaned) : await polisher.polish(cleaned) }
            let text = cleaned
            let t2 = Date()
            Log.write(String(format: "speech %.2fs (%@) · cleanup %.2fs (%@) · total %.2fs · %.1fs audio",
                             t1.timeIntervalSince(t0), dg != nil ? "deepgram" : "local",
                             t2.timeIntervalSince(t1), useAI ? (Cloud.useLLM ? "cloud" : "local") : "off",
                             t2.timeIntervalSince(t0), secs))
            await MainActor.run {
                // Inside our own window, type straight into the "Try it" box.
                if NSApp.isActive && self.window.window.isKeyWindow { self.window.insertTry(text) } else { Paster.paste(text) }
                History.add(text)
                self.window.reloadHistory()
            }
        }
    }
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MyType.log")
    static func write(_ line: String) {
        let s = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(s.utf8)); try? h.close() }
        else { try? s.write(to: url, atomically: true, encoding: .utf8) }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
