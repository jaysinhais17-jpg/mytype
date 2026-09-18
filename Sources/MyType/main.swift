import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement

final class App: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let polisher = Polisher()
    private let hotkey = Hotkey()
    private let hud = HUD()
    private var recording = false
    private var locked = false // hands-free mode after a quick tap
    private var pressStart = Date()
    private var statusLine = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
    private var llmLine = NSMenuItem(title: "AI cleanup: loading…", action: nil, keyEquivalent: "")
    private let aiItem = NSMenuItem(title: "AI cleanup", action: #selector(toggleAI(_:)), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")

    private var aiEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "aiCleanup") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "aiCleanup") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        setIcon("mic.slash")
        buildMenu()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        // Accessibility is required to send Cmd+V into other apps.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)

        recorder.onLevel = { [weak self] v in self?.hud.level(v) }
        hotkey.onDown = { [weak self] in self?.keyDown() }
        hotkey.onUp = { [weak self] in self?.keyUp() }
        if !hotkey.install() {
            statusLine.title = "Grant Input Monitoring, then relaunch"
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        }

        if !UserDefaults.standard.bool(forKey: "welcomed") {
            UserDefaults.standard.set(true, forKey: "welcomed")
            DispatchQueue.main.async { self.showWelcome() }
        }

        transcriber.startServer { [weak self] ok in
            guard let self else { return }
            self.setIcon(ok ? "mic" : "exclamationmark.triangle")
            self.statusLine.title = ok ? "Ready — tap or hold Fn to talk" : "Server failed (brew install whisper-cpp? model present?)"
        }

        if Polisher.available {
            polisher.start { [weak self] ok in
                self?.llmLine.title = ok ? "AI cleanup: ready" : "AI cleanup: failed to start"
            }
        } else {
            llmLine.title = "AI cleanup: not installed"
        }
    }

    func applicationWillTerminate(_ n: Notification) {
        transcriber.stopServer()
        polisher.stop()
    }

    private func setIcon(_ name: String) {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "MyType")
        statusItem.button?.image = img
        // Fall back to text so the item is never invisible.
        statusItem.button?.title = img == nil ? "🎙" : ""
    }

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "MyType is running"
        a.informativeText = "It lives in the menu bar (top right of your screen) — there's no Dock icon or window.\n\nTap Fn to start/stop dictating, or hold Fn to talk. If you don't see the icon, your menu bar may be full: quit a few menu-bar apps or hold ⌘ and drag icons to make room."
        a.addButton(withTitle: "Got it")
        a.runModal()
        statusItem.button?.performClick(nil)
    }

    /// Double-clicking the app (Finder/Spotlight) while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWelcome()
        return false
    }

    private func buildMenu() {
        let m = NSMenu()
        m.addItem(statusLine)
        m.addItem(llmLine)
        m.addItem(.separator())
        aiItem.target = self; aiItem.state = aiEnabled ? .on : .off
        m.addItem(aiItem)
        let lang = NSMenuItem(title: "Auto-detect language (restart to apply)", action: #selector(toggleLang(_:)), keyEquivalent: "")
        lang.target = self
        lang.state = transcriber.language == "auto" ? .on : .off
        m.addItem(lang)
        loginItem.target = self; loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(loginItem)
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit MyType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = m
    }

    @objc private func toggleAI(_ item: NSMenuItem) {
        aiEnabled.toggle()
        item.state = aiEnabled ? .on : .off
    }

    @objc private func toggleLang(_ item: NSMenuItem) {
        let auto = transcriber.language != "auto"
        UserDefaults.standard.set(auto ? "auto" : "en", forKey: "language")
        item.state = auto ? .on : .off
    }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't change launch-at-login"
            a.informativeText = "\(error.localizedDescription)\n\nMove MyType.app to ~/Applications or /Applications and try again."
            a.runModal()
        }
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    /// Tap Fn = start/stop hands-free. Hold Fn = push-to-talk.
    private func keyDown() {
        if recording && locked { locked = false; finish(); return }
        guard !recording else { return }
        pressStart = Date()
        begin()
    }

    private func keyUp() {
        guard recording, !locked else { return }
        if Date().timeIntervalSince(pressStart) < Config.tapSeconds { locked = true } else { finish() }
    }

    private func begin() {
        guard transcriber.ready, !recording else { return }
        do {
            try recorder.start()
            recording = true
            setIcon("waveform.circle.fill")
            hud.set(.listening)
            NSSound(named: "Tink")?.play()
        } catch { setIcon("exclamationmark.triangle") }
    }

    private func finish() {
        guard recording else { return }
        recording = false
        locked = false
        let samples = recorder.stop()
        let secs = Double(samples.count) / Config.sampleRate
        guard secs >= Config.minSeconds, Audio.rms(samples) > Config.silenceRMS else {
            setIcon("mic"); hud.set(.hidden); return
        }
        setIcon("ellipsis.circle")
        hud.set(.working)
        let trimmed = Audio.trimSilence(samples)
        let useAI = aiEnabled
        Task {
            defer { DispatchQueue.main.async { self.setIcon("mic"); self.hud.set(.hidden) } }
            guard let raw = try? await transcriber.transcribe(trimmed) else { return }
            var text = TextCleaner.clean(raw)
            guard !text.isEmpty else { return }
            if useAI { text = await polisher.polish(text) }
            await MainActor.run { Paster.paste(text) }
        }
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
