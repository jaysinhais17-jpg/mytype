import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement

final class App: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = Recorder()
    let transcriber = Transcriber()
    private let polisher = Polisher()
    private let cloudPolisher = CloudPolisher()
    private var deepgram: DeepgramSession?
    private lazy var streamer = Streamer(recorder: recorder, transcriber: transcriber)
    private let hotkey = Hotkey()
    private let hud = HUD()
    private let chip = RecallChip()
    private var startApp: pid_t?   // app that was in front when this dictation began
    private var startFocus = Focus.Kind.unknown   // whether a text box had the cursor when it began
    private var window: MainWindow!
    private var onboarding: Onboarding!
    private var recording = false
    private var locked = false // hands-free mode after a quick tap
    private var pressStart = Date()
    private var lastTapUp = Date.distantPast
    private var hudWork: DispatchWorkItem?
    /// Cloud cleanup started at the last pause, while the key was still down. Used if the final transcript matches its input.
    private var headStart: (input: String, task: Task<String, Never>)?
    private let statusLine = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
    private let llmLine = NSMenuItem(title: "AI cleanup: loading…", action: nil, keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
    private let aiItem = NSMenuItem(title: "AI cleanup", action: #selector(toggleAIMenu), keyEquivalent: "")
    private let recentItem = NSMenuItem(title: "Recent dictations", action: nil, keyEquivalent: "")
    private let recentMenu = NSMenu()
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
        if InstallCheck.offerMove() { return }
        setIcon("mic.slash")
        buildMenu()
        rebuildRecent()
        buildMainMenu()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        _ = Net.online // start watching the connection
        recorder.onLevel = { [weak self] v in self?.hud.level(v) }
        hotkey.onDown = { [weak self] code in self?.keyDown(code) }
        hotkey.onUp = { [weak self] code, chorded in self?.keyUp(code, chorded: chorded) }
        hotkey.onEvent = { [weak self] _, _ in self?.keySeen = true }
        // Keep trying until Input Monitoring is granted — no relaunch needed.
        _ = hotkey.install()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, !self.hotkey.installed, CGPreflightListenEventAccess() else { return }
            _ = self.hotkey.install()
        }

        AppearanceMode.current.apply()
        window = MainWindow(app: self)
        onboarding = Onboarding(app: self, main: window)
        window.onSetup = { [weak self] in self?.onboarding.show() }
        // Test hook: MYTYPE_APPEARANCE=light|dark previews the UI without touching the system setting.
        switch ProcessInfo.processInfo.environment["MYTYPE_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let forced = ProcessInfo.processInfo.environment["MYTYPE_SETUP"] { onboarding.show(step: Int(forced) ?? 0) }
        else if !UserDefaults.standard.bool(forKey: "onboarded") && !Cloud.useDeepgram { onboarding.show() } else { window.show() }

        transcriber.killStrays()
        refreshAI()

        Updater.onChange = { [weak self] in
            guard let self else { return }
            self.updateItem.title = Updater.available.map { "Update to \($0.version)…" } ?? "Check for Updates…"
        }
        Updater.startAutoChecks { [weak self] in self?.recording ?? false }
    }

    private var localFailed = false
    /// True while a dictation is being transcribed on-device, so the idle timer doesn't pull the model away.
    private var localBusy = false
    private var streamingLocal = false
    /// Ready if either the on-device model is loaded or a Deepgram key lets us stream (so the local model is optional).
    private func updateStatus() {
        if transcriber.ready || Cloud.useDeepgram || (Transcriber.available && !localFailed) { statusLine.title = "Ready" }
        else if localFailed { statusLine.title = "Add a Deepgram key in Settings (or install whisper-cpp for on-device speech)" }
    }

    /// The on-device model costs ~640 MB while loaded. Without a Deepgram key it's the engine, so keep it warm;
    /// with one it's only the offline fallback, so it's loaded on demand and dropped again once idle.
    private func refreshSpeech() {
        if Cloud.useDeepgram { releaseLocalLater(); return }
        localIdle?.cancel(); localIdle = nil
        guard !transcriber.ready else { return }
        transcriber.startServer { [weak self] ok in
            guard let self else { return }
            if !self.recording { self.setIcon(ok || Cloud.useDeepgram ? "mic" : "exclamationmark.triangle") }
            self.localFailed = !ok
            self.updateStatus()
        }
    }

    private var localIdle: DispatchWorkItem?
    private func releaseLocalLater() {
        localIdle?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, Cloud.useDeepgram else { return }
            if self.recording || self.localBusy { self.releaseLocalLater() } else { self.transcriber.stopServer() }
        }
        localIdle = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: w)
    }

    var engineText: String { Cloud.useDeepgram ? "Speech: Deepgram" : "Speech: on-device" }

    /// Called at launch and whenever the toggle or cloud keys change.
    func refreshAI() {
        refreshSpeech()
        updateStatus()
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
        window?.show()
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
        let copyLast = NSMenuItem(title: "Copy last dictation", action: #selector(copyLastDictation), keyEquivalent: "")
        copyLast.target = self
        m.addItem(copyLast)
        recentItem.submenu = recentMenu
        m.addItem(recentItem)
        m.addItem(.separator())
        m.addItem(statusLine)
        m.addItem(llmLine)
        m.addItem(.separator())
        aiItem.target = self; aiItem.state = aiEnabled ? .on : .off
        m.addItem(aiItem)
        loginItem.target = self; loginItem.state = loginEnabled ? .on : .off
        m.addItem(loginItem)
        m.addItem(.separator())
        updateItem.target = self
        m.addItem(updateItem)
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

    @objc private func checkUpdates() {
        if let r = Updater.available { Updater.offer(r) } else { Updater.check(manual: true) }
    }
    @objc private func openWindow() { window?.show() }
    @objc private func copyLastDictation() { if let t = Recall.lastText { Recall.copy(t) } }
    @objc private func copyRecent(_ item: NSMenuItem) { if let t = item.representedObject as? String { Recall.copy(t) } }

    /// The menu-bar "Recent dictations" list: the last few, click one to copy it.
    private func rebuildRecent() {
        recentMenu.removeAllItems()
        let items = History.items.prefix(8)
        recentItem.isEnabled = !items.isEmpty
        for e in items {
            let one = e.text.split(whereSeparator: \.isNewline).joined(separator: " ")
            let it = NSMenuItem(title: one.count > 60 ? String(one.prefix(60)) + "…" : one, action: #selector(copyRecent(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = e.text
            recentMenu.addItem(it)
        }
    }
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

    private static let rightOption: Int64 = 61

    private func mode(_ code: Int64) -> KeyMode { code == Self.rightOption ? Shortcuts.option : Shortcuts.fn }

    /// Each key follows its Shortcuts mode (Settings): hold = push-to-talk; hands-free opens with a single tap or a double-tap,
    /// then one more tap stops it. Defaults: Fn double-tap, Right Option single tap (macOS grabs a double-tap of Option).
    private func keyDown(_ code: Int64) {
        if recording && locked { locked = false; finish(); return }
        guard !recording else { return }
        let m = mode(code)
        if m == .off { return }
        pressStart = Date()
        if m == .holdDoubleTap {
            let isDouble = Date().timeIntervalSince(lastTapUp) < Config.doubleTapSeconds
            begin(showAfter: isDouble ? 0 : Config.tapSeconds)
            if isDouble && recording { locked = true }
        } else { begin(showAfter: Config.tapSeconds) }
    }

    private func keyUp(_ code: Int64, chorded: Bool) {
        guard recording, !locked else { return }
        let m = mode(code)
        if m == .off { return }
        if code == Self.rightOption && chorded { cancelRecording(); return }   // Option+key shortcut, not dictation
        if Date().timeIntervalSince(pressStart) < Config.tapSeconds {
            switch m {
            case .holdTap: lockHandsFree()
            case .holdDoubleTap: cancelRecording(); lastTapUp = Date()
            default: cancelRecording()
            }
        } else { finish() }
    }

    /// A quick tap of Right Option: show the mic now and keep listening until the next tap.
    private func lockHandsFree() {
        locked = true
        hudWork?.cancel(); hudWork = nil
        hud.set(.listening)
        NSSound(named: "Tink")?.play()
    }

    func beginManual() { if !recording { begin(showAfter: 0) } }
    func finishManual() { locked = false; finish() }

    /// Dictation couldn't start: say so (sound + warning icon that resets itself) instead of failing silently.
    private func startFailed(showWindow: Bool) {
        NSSound(named: "Basso")?.play()
        setIcon("exclamationmark.triangle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !self.recording else { return }
            self.setIcon("mic")
        }
        if showWindow { window?.show() }
    }

    private func begin(showAfter delay: TimeInterval) {
        guard !recording else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted: startFailed(showWindow: true); return
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { _ in }; return
        default: break
        }
        guard transcriber.ready || (Cloud.useDeepgram && Net.online) || Transcriber.available else { startFailed(showWindow: !Cloud.useDeepgram); return }
        do {
            try recorder.start()
            recording = true
            chip.dismiss()
            startApp = NSWorkspace.shared.frontmostApplication?.processIdentifier
            Focus.prime(NSWorkspace.shared.frontmostApplication)
            startFocus = Focus.current()
            CloudPolisher.appStyle = CloudPolisher.style(for: NSWorkspace.shared.frontmostApplication)
            if Cloud.aiReady { CloudPolisher.warm() }
            if Cloud.useDeepgram && Net.online {
                let d = DeepgramSession(recorder: recorder)
                if aiEnabled && Cloud.useLLM { d.onPause = { [weak self] raw in self?.polishAhead(raw) } }
                d.start(language: transcriber.language == "auto" ? "multi" : "en")
                deepgram = d
            } else if transcriber.ready {
                streamingLocal = true
                streamer.start()
            } else { transcriber.startServer { _ in } } // model loads while you talk; finish() waits for it
            setIcon("waveform.circle.fill")
            let show = DispatchWorkItem { [weak self] in
                self?.hud.set(.listening)
                NSSound(named: "Tink")?.play()
            }
            hudWork = show
            if delay == 0 { show.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: show) }
        } catch { startFailed(showWindow: false) }
    }

    /// People usually stop talking a beat before they let go of the key, so cleanup of the text so far starts at
    /// every pause. If nothing more was said by key-up, the answer is already on its way (or back).
    private func polishAhead(_ raw: String) {
        guard recording, Net.online, !TextCleaner.isUndoCommand(raw) else { return }
        let cleaned = TextCleaner.clean(raw)
        guard !cleaned.isEmpty, headStart?.input != cleaned else { return }
        headStart?.task.cancel()
        let p = cloudPolisher
        headStart = (cleaned, Task { await p.polish(cleaned) })
    }

    private func dropHeadStart() { headStart?.task.cancel(); headStart = nil }

    private func cancelRecording() {
        dropHeadStart()
        hudWork?.cancel(); hudWork = nil
        recording = false; locked = false; streamingLocal = false
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
            dropHeadStart(); streamer.cancel(); streamingLocal = false; deepgram?.cancel(); deepgram = nil; setIcon("mic"); hud.set(.hidden); return
        }
        setIcon("ellipsis.circle")
        hud.set(.working)
        let useAI = aiEnabled
        let began = startApp
        let beganFocus = startFocus
        let dg = deepgram; deepgram = nil
        dg?.onPause = nil
        let ahead = headStart; headStart = nil
        let streamed = streamingLocal; streamingLocal = false
        let t0 = Date()
        Task {
            defer { DispatchQueue.main.async { self.setIcon("mic"); self.hud.set(.hidden) } }
            var usedAhead = false
            defer { if !usedAhead { ahead?.task.cancel() } }
            let raw: String
            var engine = "local"
            if let dg, let t = await dg.finish(allSamples: samples) { raw = t; engine = "deepgram" }
            else {
                if dg != nil { engine = "local (deepgram failed)" }
                await MainActor.run { self.localBusy = true }
                if streamed { raw = await streamer.finish(allSamples: samples) }
                else { raw = await transcriber.ensureReady() ? await streamer.transcribeAll(samples) : "" }
                await MainActor.run { self.localBusy = false; if Cloud.useDeepgram { self.releaseLocalLater() } }
            }
            let t1 = Date()
            if engine == "deepgram" { Usage.add(UsageEvent(date: Date(), audioSeconds: secs)) }
            if TextCleaner.isUndoCommand(raw) {
                await MainActor.run { if !(self.onboarding.isFrontmost || (NSApp.isActive && self.window.window.isKeyWindow)) { Paster.undo() } }
                return
            }
            var cleaned = TextCleaner.clean(raw)
            guard !cleaned.isEmpty else { return }
            if useAI {
                if Cloud.useLLM {
                    if let ahead, ahead.input == cleaned { usedAhead = true; cleaned = await ahead.task.value }
                    else if Net.online { cleaned = await cloudPolisher.polish(cleaned) }
                }
                else { cleaned = await polisher.polish(cleaned) }
            }
            let text = TextCleaner.expandSnippets(cleaned)
            let t2 = Date()
            Log.write(String(format: "speech %.2fs (%@) · cleanup %.2fs (%@) · total %.2fs · %.1fs audio",
                             t1.timeIntervalSince(t0), engine,
                             t2.timeIntervalSince(t1), useAI ? (Cloud.useLLM ? (usedAhead ? "cloud, head start" : Net.online ? "cloud" : "skipped, offline") : "local") : "off",
                             t2.timeIntervalSince(t0), secs))
            await MainActor.run {
                // Inside our own window, type straight into the "Try it" box. Otherwise the text goes to the cursor only
                // if a text box had it when you started talking and it's still there. If you started with nothing
                // focused, or wandered off to another app or box while dictating (say, to read System Settings),
                // pasting would land in the wrong place, so the text stays on the clipboard and the chip offers it.
                let sameApp = began == nil || NSWorkspace.shared.frontmostApplication?.processIdentifier == began
                let movedOn = !sameApp || beganFocus == .noBox || (beganFocus == .textBox && Focus.current() == .noBox)
                var copied = false
                if self.onboarding.isFrontmost { self.onboarding.insertTry(text) }
                else if movedOn { Recall.copy(text); copied = true }
                else if NSApp.isActive && self.window.window.isKeyWindow { self.window.insertTry(text) }
                else { Paster.paste(text) }
                History.add(text, raw: raw, secs: secs)
                if copied { self.chip.show(text) }
                self.rebuildRecent()
                self.window.reloadHistory()
                if engine == "deepgram" { DeepgramBalance.refresh { self.window.reloadUsage() } }
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
