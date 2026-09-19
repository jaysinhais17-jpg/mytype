import AppKit
import AVFoundation
import ApplicationServices

struct HistoryEntry: Codable { let date: Date; let text: String }

enum History {
    static var items: [HistoryEntry] {
        guard let d = UserDefaults.standard.data(forKey: "history"),
              let a = try? JSONDecoder().decode([HistoryEntry].self, from: d) else { return [] }
        return a
    }
    static func add(_ text: String) {
        var a = items
        a.insert(HistoryEntry(date: Date(), text: text), at: 0)
        if let d = try? JSONEncoder().encode(Array(a.prefix(50))) { UserDefaults.standard.set(d, forKey: "history") }
    }
}

/// Button that reports mouse-down and mouse-up, for push-to-talk from the window.
final class HoldButton: NSButton {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onDown?()
        super.mouseDown(with: event)
        onUp?()
    }
}

final class CheckRow: NSObject {
    let dot = NSTextField(labelWithString: "●")
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    let button = NSButton(title: "Grant", target: nil, action: nil)
    let view = NSStackView()
    private let action: (() -> Void)?

    init(title: String, detail: String, action: (() -> Void)?) {
        self.action = action
        super.init()
        self.title.stringValue = title
        self.title.font = .systemFont(ofSize: 13, weight: .semibold)
        self.detail.stringValue = detail
        self.detail.font = .systemFont(ofSize: 11)
        self.detail.textColor = .secondaryLabelColor
        dot.font = .systemFont(ofSize: 14)
        let text = NSStackView(views: [self.title, self.detail])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
        button.target = self; button.action = #selector(tap); button.bezelStyle = .rounded
        button.isHidden = action == nil
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        view.setViews([dot, text, spacer, button], in: .leading)
        view.orientation = .horizontal; view.alignment = .centerY; view.spacing = 10
    }

    @objc private func tap() { action?() }

    func set(ok: Bool, pending: Bool = false) {
        dot.textColor = ok ? .systemGreen : (pending ? .systemOrange : .systemRed)
        button.isHidden = ok || action == nil
    }
}

final class MainWindow: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    private unowned let app: App
    private let status = NSTextField(labelWithString: "")
    private let micRow: CheckRow, axRow: CheckRow, inputRow: CheckRow, keyRow: CheckRow
    private let tryView: NSTextView
    private let historyView: NSTextView
    private let aiBox = NSButton(checkboxWithTitle: "AI cleanup — smarter edits, but needs ~2 GB RAM and adds delay", target: nil, action: nil)
    private let langBox = NSButton(checkboxWithTitle: "Auto-detect language (restart to apply)", target: nil, action: nil)
    private let loginBox = NSButton(checkboxWithTitle: "Launch MyType at login", target: nil, action: nil)
    private let dictField = NSTextField()
    private let dgField = NSSecureTextField()
    private let llmKeyField = NSSecureTextField()
    private let llmURLField = NSTextField()
    private let llmModelField = NSTextField()
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private static let presets: [(String, String, String)] = [
        ("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-flash-lite-latest"),
        ("DeepSeek", "https://api.deepseek.com", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
    ]
    private var timer: Timer?

    init(app: App) {
        self.app = app
        func openPane(_ id: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(id)")!) }
        micRow = CheckRow(title: "Microphone", detail: "Lets MyType hear you.") {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            openPane("Privacy_Microphone")
        }
        axRow = CheckRow(title: "Accessibility", detail: "Lets MyType paste text into other apps.") {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            openPane("Privacy_Accessibility")
        }
        inputRow = CheckRow(title: "Input Monitoring", detail: "Lets MyType see the Fn key.") {
            CGRequestListenEventAccess()
            openPane("Privacy_ListenEvent")
        }
        keyRow = CheckRow(title: "Fn key detected", detail: "Press Fn once. Set System Settings → Keyboard → “Press 🌐 key to” → Do Nothing.", action: nil)

        let (tryScroll, tv) = MainWindow.textArea(height: 84, editable: true)
        let (histScroll, hv) = MainWindow.textArea(height: 110, editable: false)
        tryView = tv; historyView = hv

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 900),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MyType"
        window.isReleasedWhenClosed = false
        super.init()

        let title = NSTextField(labelWithString: "MyType")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.textColor = .secondaryLabelColor
        let hint = NSTextField(wrappingLabelWithString: "Hold Fn to talk, or double-tap Fn to go hands-free (tap once more to stop). Right Option works too.")
        hint.font = .systemFont(ofSize: 13)

        let talk = HoldButton(title: "Hold to talk", target: nil, action: nil)
        talk.bezelStyle = .rounded; talk.controlSize = .large
        talk.onDown = { [weak app] in app?.beginManual() }
        talk.onUp = { [weak app] in app?.finishManual() }
        let copy = NSButton(title: "Copy last", target: self, action: #selector(copyLast))
        copy.bezelStyle = .rounded
        let tryRow = NSStackView(views: [talk, copy]); tryRow.spacing = 8

        for (box, sel) in [(aiBox, #selector(toggleAI)), (langBox, #selector(toggleLang)), (loginBox, #selector(toggleLogin))] {
            box.target = self; box.action = sel
        }

        dictField.stringValue = Config.dictionary
        dictField.placeholderString = "Names and terms MyType should spell right, comma separated"
        dictField.target = self; dictField.action = #selector(saveDict)
        let dictHint = NSTextField(wrappingLabelWithString: "Custom words: helps with names, drugs, jargon. Press Return to save.")
        dictHint.font = .systemFont(ofSize: 11); dictHint.textColor = .secondaryLabelColor

        func row(_ label: String, _ f: NSTextField, _ ph: String, _ v: String) -> NSStackView {
            f.stringValue = v; f.placeholderString = ph; f.delegate = self
            let l = NSTextField(labelWithString: label); l.font = .systemFont(ofSize: 12)
            l.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let r = NSStackView(views: [l, f]); r.spacing = 8; return r
        }
        presetPopup.addItems(withTitles: ["Custom"] + MainWindow.presets.map { $0.0 })
        presetPopup.target = self; presetPopup.action = #selector(pickPreset)
        if let i = MainWindow.presets.firstIndex(where: { $0.1 == Cloud.llmBaseURL }) { presetPopup.selectItem(at: i + 1) }
        let presetLabel = NSTextField(labelWithString: "Cleanup provider"); presetLabel.font = .systemFont(ofSize: 12)
        presetLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let presetRow = NSStackView(views: [presetLabel, presetPopup]); presetRow.spacing = 8
        let cloudHint = NSTextField(wrappingLabelWithString: "Optional. With a Deepgram key, speech goes to Deepgram (faster, more accurate); with a cleanup key, text goes to that model for punctuation and edits. Leave blank to stay fully on-device. Audio and text leave your Mac when these are set. Keys are stored on this Mac only.")
        cloudHint.font = .systemFont(ofSize: 11); cloudHint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [
            title, status, hint,
            MainWindow.header("SETUP"), micRow.view, axRow.view, inputRow.view, keyRow.view,
            MainWindow.header("TRY IT"), tryScroll, tryRow,
            MainWindow.header("RECENT"), histScroll,
            MainWindow.header("SETTINGS"), aiBox, langBox, loginBox,
            MainWindow.header("CUSTOM WORDS"), dictField, dictHint,
            MainWindow.header("CLOUD (OPTIONAL)"),
            row("Deepgram key", dgField, "Paste key to use Deepgram for speech", Cloud.deepgramKey),
            presetRow,
            row("Cleanup key", llmKeyField, "Paste API key for the cleanup model", Cloud.llmKey),
            row("Base URL", llmURLField, "https://…", Cloud.llmBaseURL),
            row("Model", llmModelField, "model name", Cloud.llmModel),
            cloudHint,
        ])
        stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 24, right: 24)
        stack.setCustomSpacing(4, after: title)
        for h in [3, 8, 11, 13, 17, 20] { stack.setCustomSpacing(6, after: stack.arrangedSubviews[h]) }
        for h in [2, 7, 10, 12, 16, 19] { stack.setCustomSpacing(22, after: stack.arrangedSubviews[h]) }
        stack.widthAnchor.constraint(equalToConstant: 580).isActive = true
        window.contentView = stack
        window.setContentSize(NSSize(width: 580, height: stack.fittingSize.height))
        window.center()
        refresh()
        reloadHistory()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private static func header(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .systemFont(ofSize: 11, weight: .semibold)
        t.textColor = .tertiaryLabelColor
        return t
    }

    private static func textArea(height: CGFloat, editable: Bool) -> (NSScrollView, NSTextView) {
        let sv = NSTextView.scrollableTextView()
        let tv = sv.documentView as! NSTextView
        tv.isEditable = editable
        tv.font = .systemFont(ofSize: 13)
        tv.textContainerInset = NSSize(width: 6, height: 6)
        sv.borderType = .bezelBorder
        sv.heightAnchor.constraint(equalToConstant: height).isActive = true
        return (sv, tv)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func insertTry(_ text: String) {
        window.makeFirstResponder(tryView)
        tryView.insertText(text + " ", replacementRange: tryView.selectedRange())
    }

    func reloadHistory() {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let items = History.items.prefix(20)
        historyView.string = items.isEmpty
            ? "Your dictations will show up here."
            : items.map { "\(f.string(from: $0.date))  \($0.text)" }.joined(separator: "\n\n")
    }

    func refresh() {
        micRow.set(ok: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        axRow.set(ok: AXIsProcessTrusted())
        inputRow.set(ok: CGPreflightListenEventAccess())
        keyRow.set(ok: app.keySeen, pending: app.hotkeyInstalled)
        status.stringValue = "\(app.statusText)   ·   \(app.engineText)   ·   \(app.llmText)"
        aiBox.state = app.aiEnabled ? .on : .off
        langBox.state = app.autoLanguage ? .on : .off
        loginBox.state = app.loginEnabled ? .on : .off
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        Cloud.deepgramKey = dgField.stringValue
        Cloud.llmKey = llmKeyField.stringValue
        Cloud.llmBaseURL = llmURLField.stringValue
        Cloud.llmModel = llmModelField.stringValue
        app.refreshAI()
    }
    @objc private func pickPreset() {
        let i = presetPopup.indexOfSelectedItem - 1
        guard i >= 0 else { return }
        llmURLField.stringValue = MainWindow.presets[i].1
        llmModelField.stringValue = MainWindow.presets[i].2
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }
    @objc private func saveDict() { Config.dictionary = dictField.stringValue }
    @objc private func toggleAI() { app.aiEnabled = aiBox.state == .on }
    @objc private func toggleLang() { app.autoLanguage = langBox.state == .on }
    @objc private func toggleLogin() {
        if let err = app.setLogin(loginBox.state == .on) {
            let a = NSAlert()
            a.messageText = "Couldn't change launch-at-login"
            a.informativeText = "\(err)\n\nMove MyType.app to ~/Applications or /Applications and try again."
            a.runModal()
        }
        refresh()
    }
    @objc private func copyLast() {
        guard let last = History.items.first else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last.text, forType: .string)
    }
}
