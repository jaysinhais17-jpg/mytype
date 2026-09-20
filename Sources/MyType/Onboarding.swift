import AppKit
import AVFoundation
import ApplicationServices

/// Small looping illustration above each setup step: a stand-in for the "how to" clips other apps ship.
final class StepArt: NSView {
    enum Kind { case welcome, key, permissions, fn, tryIt }
    var kind: Kind = .welcome { didSet { start = CACurrentMediaTime(); needsDisplay = true } }
    private var start = CACurrentMediaTime()
    private var timer: Timer?

    override func viewDidMoveToWindow() {
        timer?.invalidate(); timer = nil
        guard window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, self.window?.isVisible == true else { return }
            self.needsDisplay = true
        }
    }

    // MARK: drawing helpers

    private func rr(_ r: NSRect, _ radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1) {
        let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        fill.setFill(); p.fill()
        if let stroke { stroke.setStroke(); p.lineWidth = width; p.stroke() }
    }

    private func text(_ s: String, _ p: CGPoint, size: CGFloat, weight: NSFont.Weight = .medium, color: NSColor = .labelColor, center: Bool = true) {
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
        let sz = s.size(withAttributes: a)
        s.draw(at: CGPoint(x: center ? p.x - sz.width / 2 : p.x, y: p.y - sz.height / 2), withAttributes: a)
    }

    private func symbol(_ name: String, _ r: NSRect, _ color: NSColor) {
        let cfg = NSImage.SymbolConfiguration(pointSize: r.height, weight: .medium).applying(.init(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        let s = img.size, k = min(r.width / s.width, r.height / s.height)
        let d = NSSize(width: s.width * k, height: s.height * k)
        img.draw(in: NSRect(x: r.midX - d.width / 2, y: r.midY - d.height / 2, width: d.width, height: d.height))
    }

    private func ease(_ x: Double) -> CGFloat { let c = max(0, min(1, x)); return CGFloat(c * c * (3 - 2 * c)) }

    private func bars(around c: CGPoint, count: Int, t: Double, spread: CGFloat, height: CGFloat, alpha: CGFloat) {
        for i in 0..<count {
            let h = 6 + height * CGFloat(abs(sin(t * 6 + Double(i) * 0.9)) * (1 - Double(i) / Double(count + 2)))
            let x = c.x + (CGFloat(i) - CGFloat(count - 1) / 2) * spread
            rr(NSRect(x: x - 2.5, y: c.y - h / 2, width: 5, height: h), 2.5, fill: Theme.purple.withAlphaComponent(alpha))
        }
    }

    // MARK: scenes

    override func draw(_ dirty: NSRect) {
        let t = CACurrentMediaTime() - start
        rr(bounds, 16, fill: Theme.purple.withAlphaComponent(0.07), stroke: Theme.line)
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        switch kind {
        case .welcome:
            let r: CGFloat = 34
            for i in 0..<3 {
                let p = CGFloat((t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r - 8 - p * 60, y: c.y - r - 8 - p * 60, width: (r + 8 + p * 60) * 2, height: (r + 8 + p * 60) * 2))
                Theme.purple.withAlphaComponent((1 - p) * 0.45).setStroke(); ring.lineWidth = 2; ring.stroke()
            }
            NSColor(white: 0.12, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Theme.purple.withAlphaComponent(0.6 + 0.4 * CGFloat(sin(t * 3))).setStroke(); ring.lineWidth = 2; ring.stroke()
            symbol("mic.fill", NSRect(x: c.x - 13, y: c.y - 15, width: 26, height: 30), .white)

        case .key:
            let f = NSRect(x: c.x - 150, y: c.y - 20, width: 300, height: 40)
            text("Paste your key", CGPoint(x: f.minX, y: f.maxY + 16), size: 11, color: .secondaryLabelColor, center: false)
            rr(f, 10, fill: Theme.card, stroke: Theme.line)
            let cyc = t.truncatingRemainder(dividingBy: 4.5)
            let n = cyc < 3 ? min(28, Int(cyc * 10)) : 28
            text(String(repeating: "•", count: n), CGPoint(x: f.minX + 14, y: f.midY), size: 15, color: .labelColor, center: false)
            if cyc < 3, Int(t * 2) % 2 == 0 {
                rr(NSRect(x: f.minX + 16 + CGFloat(n) * 6, y: f.midY - 9, width: 1.5, height: 18), 0.5, fill: Theme.purple)
            }
            if cyc > 3.0 {
                let s = 0.6 + 0.4 * ease((cyc - 3.0) / 0.25)
                symbol("checkmark.circle.fill", NSRect(x: f.maxX - 34, y: f.midY - 11 * s, width: 22 * s, height: 22 * s), .systemGreen)
            }

        case .permissions:
            let p = NSRect(x: c.x - 170, y: c.y - 36, width: 340, height: 72)
            text("System Settings  ›  Privacy & Security", CGPoint(x: p.minX, y: p.maxY + 18), size: 11, color: .secondaryLabelColor, center: false)
            rr(p, 12, fill: Theme.card, stroke: Theme.line)
            rr(NSRect(x: p.minX + 16, y: p.midY - 19, width: 38, height: 38), 9, fill: Theme.purple)
            symbol("mic.fill", NSRect(x: p.minX + 25, y: p.midY - 11, width: 20, height: 22), .white)
            text("MyType", CGPoint(x: p.minX + 66, y: p.midY), size: 14, weight: .semibold, center: false)
            let cyc = t.truncatingRemainder(dividingBy: 4.6)
            let on: CGFloat = cyc < 4.2 ? ease((cyc - 1.7) / 0.25) : 0
            let tg = NSRect(x: p.maxX - 62, y: p.midY - 13, width: 46, height: 26)
            rr(tg, 13, fill: NSColor.secondaryLabelColor.withAlphaComponent(0.3).blended(withFraction: on, of: .systemGreen) ?? .systemGreen)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: tg.minX + 2 + on * 20, y: tg.minY + 2, width: 22, height: 22)).fill()
            // pointer travels to the switch and clicks
            let k = ease((cyc - 0.4) / 1.2)
            let from = CGPoint(x: p.maxX + 30, y: p.minY - 30), to = CGPoint(x: tg.midX + 6, y: tg.midY - 6)
            let pos = CGPoint(x: from.x + (to.x - from.x) * k, y: from.y + (to.y - from.y) * k)
            if cyc > 1.7 && cyc < 2.2 {
                let q = CGFloat((cyc - 1.7) / 0.5)
                let ring = NSBezierPath(ovalIn: NSRect(x: tg.midX - 8 - q * 16, y: tg.midY - 8 - q * 16, width: 16 + q * 32, height: 16 + q * 32))
                Theme.purple.withAlphaComponent(1 - q).setStroke(); ring.lineWidth = 2; ring.stroke()
            }
            if cyc < 4.2 { symbol("cursorarrow", NSRect(x: pos.x - 3, y: pos.y - 18, width: 20, height: 22), .labelColor) }

        case .fn:
            let cyc = t.truncatingRemainder(dividingBy: 3.8)
            let held = cyc > 0.5 && cyc < 2.8
            let press: CGFloat = held ? ease((cyc - 0.5) / 0.12) : 0
            let key = NSRect(x: c.x - 46, y: c.y - 36 - press * 4, width: 92, height: 76)
            rr(NSRect(x: key.minX, y: key.minY - 5 + press * 4, width: key.width, height: key.height), 14, fill: NSColor.secondaryLabelColor.withAlphaComponent(0.25))
            if held { rr(key.insetBy(dx: -6, dy: -6), 18, fill: Theme.purple.withAlphaComponent(0.16)) }
            rr(key, 14, fill: Theme.card, stroke: held ? Theme.purple : Theme.line, width: held ? 2 : 1)
            symbol("globe", NSRect(x: key.minX + 12, y: key.maxY - 26, width: 14, height: 14), .secondaryLabelColor)
            text("fn", CGPoint(x: key.midX, y: key.midY - 8), size: 24, weight: .bold, color: held ? Theme.purple : .labelColor)
            if held {
                bars(around: CGPoint(x: key.minX - 84, y: c.y), count: 7, t: t, spread: 12, height: 34, alpha: press)
                bars(around: CGPoint(x: key.maxX + 84, y: c.y), count: 7, t: t + 1, spread: 12, height: 34, alpha: press)
            }
            text(held ? "Hold and talk" : (cyc >= 2.8 ? "Let go: your words appear" : "Press and hold Fn"),
                 CGPoint(x: c.x, y: key.minY - 22), size: 12, color: .secondaryLabelColor)

        case .tryIt:
            let cyc = t.truncatingRemainder(dividingBy: 6.5)
            let b = NSRect(x: c.x - 170, y: c.y - 32, width: 340, height: 64)
            rr(b, 12, fill: Theme.card, stroke: Theme.line)
            if cyc < 1.6 {
                bars(around: CGPoint(x: b.midX, y: b.midY), count: 9, t: t, spread: 12, height: 30, alpha: 1)
            } else {
                let full = "Hey Sam, can you send me the notes from today?"
                let n = min(full.count, Int((cyc - 1.6) * 16))
                text(String(full.prefix(n)), CGPoint(x: b.minX + 16, y: b.midY), size: 14, center: false)
                if Int(t * 2) % 2 == 0, n < full.count {
                    let w = String(full.prefix(n)).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)]).width
                    rr(NSRect(x: b.minX + 17 + w, y: b.midY - 9, width: 1.5, height: 18), 0.5, fill: Theme.purple)
                }
            }
        }
    }
}

/// Button that runs a closure.
final class LinkButton: PillButton {
    var handler: (() -> Void)?
    @objc func fire() { handler?() }
}

/// First-run walkthrough: keys, permissions, Fn key, then a live test.
final class Onboarding: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    let window: NSWindow
    private unowned let app: App
    private unowned let main: MainWindow

    private static let groqBase = "https://api.groq.com/openai/v1"
    private static let groqModel = "qwen/qwen3.8-27b"
    private static let stepCount = 6

    private var step = 0
    private let art = StepArt()
    private let titleLabel = makeLabel("", size: 24, weight: .bold)
    private let bodyLabel = makeLabel("", size: 13, color: .secondaryLabelColor, wrap: true)
    private let extra = NSStackView()
    private let backButton = PillButton(title: "Back", primary: false)
    private let nextButton = PillButton(title: "Continue")
    private var dots: [Surface] = []
    private var timer: Timer?

    private let dgField = NSSecureTextField(), llmField = NSSecureTextField()
    private let status = makeLabel("", size: 12, color: .secondaryLabelColor, wrap: true)
    private let tryView = NSTextView()
    private let micRow: CheckRow, axRow: CheckRow, inputRow: CheckRow, fnRow: CheckRow
    private var checking = false

    init(app: App, main: MainWindow) {
        self.app = app; self.main = main
        func openPane(_ id: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(id)")!) }
        micRow = CheckRow(title: "Microphone", detail: "So MyType can hear you.") {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            openPane("Privacy_Microphone")
        }
        axRow = CheckRow(title: "Accessibility", detail: "So MyType can type into other apps.") {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
            openPane("Privacy_Accessibility")
        }
        inputRow = CheckRow(title: "Input Monitoring", detail: "So MyType can see the Fn key.") {
            CGRequestListenEventAccess()
            openPane("Privacy_ListenEvent")
        }
        fnRow = CheckRow(title: "Fn key detected", detail: "Press and release Fn. This turns green when MyType sees it.", action: nil)

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self

        let root = Surface(fill: Theme.bg, radius: 0)
        window.contentView = root

        art.translatesAutoresizingMaskIntoConstraints = false
        extra.orientation = .vertical; extra.alignment = .leading; extra.spacing = 12
        let column = NSStackView(views: [art, titleLabel, bodyLabel, extra])
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 14
        column.setCustomSpacing(20, after: art)
        root.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        for v in [art, bodyLabel, extra] as [NSView] { v.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        art.heightAnchor.constraint(equalToConstant: 170).isActive = true

        let dotRow = NSStackView()
        dotRow.orientation = .horizontal; dotRow.spacing = 7
        for _ in 0..<Onboarding.stepCount {
            let d = Surface(fill: Theme.line, radius: 4)
            d.widthAnchor.constraint(equalToConstant: 8).isActive = true
            d.heightAnchor.constraint(equalToConstant: 8).isActive = true
            dots.append(d); dotRow.addArrangedSubview(d)
        }
        backButton.target = self; backButton.action = #selector(back)
        nextButton.target = self; nextButton.action = #selector(next)
        nextButton.keyEquivalent = "\r"
        for v in [dotRow, backButton, nextButton] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 40),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48),
            backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48),
            backButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            nextButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48),
            nextButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            dotRow.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            dotRow.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
        ])

        for f in [dgField, llmField] {
            f.delegate = self; f.bezelStyle = .roundedBezel; f.focusRingType = .none
        }
        dgField.placeholderString = "Paste your Deepgram key"
        llmField.placeholderString = "Paste your Groq key"

        tryView.isRichText = false
        tryView.font = .systemFont(ofSize: 14)
        tryView.drawsBackground = false
        tryView.textColor = .labelColor
        tryView.textContainerInset = NSSize(width: 8, height: 8)
        tryView.isVerticallyResizable = true; tryView.isHorizontallyResizable = false
        tryView.autoresizingMask = [.width]
        tryView.textContainer?.widthTracksTextView = true

        window.center()
    }

    func show(step n: Int = 0) {
        dgField.stringValue = Cloud.deepgramKey
        llmField.stringValue = Cloud.llmBaseURL == Onboarding.groqBase ? Cloud.llmKey : ""
        go(n)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The "Try it" box gets dictated text directly while this window is frontmost.
    func insertTry(_ text: String) {
        window.makeFirstResponder(tryView)
        tryView.insertText(text + " ", replacementRange: tryView.selectedRange())
    }

    var isFrontmost: Bool { window.isVisible && window.isKeyWindow && NSApp.isActive }

    // MARK: steps

    private func btn(_ title: String, primary: Bool = false, _ h: @escaping () -> Void) -> LinkButton {
        let b = LinkButton(title: title, primary: primary)
        b.handler = h; b.target = b; b.action = #selector(LinkButton.fire)
        return b
    }
    private func open(_ url: String) { NSWorkspace.shared.open(URL(string: url)!) }

    private func steps(_ lines: [String]) -> NSTextField {
        makeLabel(lines.enumerated().map { "\($0.offset + 1)   \($0.element)" }.joined(separator: "\n"), size: 13, wrap: true)
    }

    private func go(_ n: Int) {
        step = max(0, min(Onboarding.stepCount - 1, n))
        status.stringValue = ""; status.textColor = .secondaryLabelColor
        extra.arrangedSubviews.forEach { extra.removeArrangedSubview($0); $0.removeFromSuperview() }
        var views: [NSView] = []
        switch step {
        case 0:
            art.kind = .welcome
            titleLabel.stringValue = "Welcome to MyType"
            bodyLabel.stringValue = "Hold the Fn key, say what you want to write, and let go. Your words are typed wherever your cursor is, in any app. Setup takes about three minutes."
            views = [steps(["Add your Deepgram key (turns speech into text)", "Add your Groq key (tidies the text, optional)",
                            "Allow three macOS permissions", "Set up the Fn key and try it"]),
                     makeLabel("Privacy: audio goes to Deepgram and text to Groq, using your own keys. Nothing passes through anyone else, and MyType keeps no copy of your voice.",
                               size: 11, color: .secondaryLabelColor, wrap: true)]
        case 1:
            art.kind = .key
            titleLabel.stringValue = "Add your speech key"
            bodyLabel.stringValue = "MyType uses Deepgram to turn your voice into text. New accounts get $200 of free credit, which is many months of normal use."
            views = [steps(["Sign up at console.deepgram.com", "Open API Keys and click Create a New API Key", "Copy the key and paste it below"]),
                     btn("Open Deepgram") { [weak self] in self?.open("https://console.deepgram.com/signup") }, dgField, status]
        case 2:
            art.kind = .key
            titleLabel.stringValue = "Add your cleanup key (optional)"
            bodyLabel.stringValue = "Groq's free tier fixes punctuation, removes “um”s and honours self-corrections. Skip it and you still get accurate text, just less polished."
            views = [steps(["Sign up at console.groq.com", "Open API Keys and click Create API Key", "Copy the key and paste it below"]),
                     btn("Open Groq") { [weak self] in self?.open("https://console.groq.com/keys") }, llmField, status]
        case 3:
            art.kind = .permissions
            titleLabel.stringValue = "Allow three permissions"
            bodyLabel.stringValue = "macOS asks for these so MyType can hear you, see the Fn key and type for you. Click Grant, then switch MyType on in the list that opens."
            views = [micRow.view, axRow.view, inputRow.view,
                     makeLabel("A switch already on but still red? Turn it off and on again.", size: 11, color: .secondaryLabelColor)]
        case 4:
            art.kind = .fn
            titleLabel.stringValue = "Set up the Fn key"
            bodyLabel.stringValue = "By default the 🌐 key opens the emoji picker. Tell macOS to leave it alone so MyType can use it."
            views = [steps(["Open Keyboard settings below", "Find “Press 🌐 key to”", "Choose Do Nothing"]),
                     btn("Open Keyboard settings") { [weak self] in self?.open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") },
                     fnRow.view]
        default:
            art.kind = .tryIt
            titleLabel.stringValue = "Try it"
            bodyLabel.stringValue = "Click the box, hold Fn, say something, and let go. Double-tap Fn for hands-free; tap once to stop."
            let box = Surface(fill: Theme.field, stroke: Theme.line, radius: 10)
            let sv = NSScrollView()
            sv.documentView = tryView; sv.drawsBackground = false; sv.hasVerticalScroller = true; sv.borderType = .noBorder
            sv.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(sv)
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: box.topAnchor), sv.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                sv.leadingAnchor.constraint(equalTo: box.leadingAnchor), sv.trailingAnchor.constraint(equalTo: box.trailingAnchor),
                box.heightAnchor.constraint(equalToConstant: 100),
            ])
            views = [box, makeLabel("You can reopen this guide any time from Settings.", size: 11, color: .secondaryLabelColor)]
        }
        for v in views { extra.addArrangedSubview(v); if !(v is LinkButton) { v.widthAnchor.constraint(equalTo: extra.widthAnchor).isActive = true } }
        backButton.isHidden = step == 0
        for (i, d) in dots.enumerated() { d.fill = i == step ? Theme.purple : Theme.line }
        tick()
    }

    private func tick() {
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        micRow.set(ok: mic); axRow.set(ok: AXIsProcessTrusted()); inputRow.set(ok: CGPreflightListenEventAccess())
        fnRow.set(ok: app.keySeen, pending: app.hotkeyInstalled)
        if !checking { refreshNextTitle() }
    }

    private var permissionsGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized && AXIsProcessTrusted() && CGPreflightListenEventAccess()
    }

    private func refreshNextTitle() {
        switch step {
        case 0: nextButton.title = "Get started"
        case 1: nextButton.title = dgField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty && app.transcriber.ready ? "Skip" : "Continue"
        case 2: nextButton.title = llmField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "Continue"
        case 3: nextButton.title = permissionsGranted ? "Continue" : "Continue anyway"
        case 4: nextButton.title = app.keySeen ? "Continue" : "Continue anyway"
        case 5: nextButton.title = "Finish"
        default: nextButton.title = "Continue"
        }
        nextButton.isEnabled = true
    }

    func controlTextDidChange(_ obj: Notification) { if !checking { status.stringValue = ""; refreshNextTitle() } }

    // MARK: key checks

    private func check(deepgram: Bool, key: String, done: @escaping (Bool?, String) -> Void) {
        let base = Onboarding.groqBase
        var r = URLRequest(url: URL(string: deepgram ? "https://api.deepgram.com/v1/projects" : base + "/models")!)
        r.timeoutInterval = 8
        r.setValue(deepgram ? "Token \(key)" : "Bearer \(key)", forHTTPHeaderField: "Authorization")
        let name = deepgram ? "Deepgram" : "Groq"
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                switch code {
                case 200?: done(true, "\(name) accepted the key.")
                case nil: done(nil, "Couldn't reach \(name). Check your internet; continuing anyway.")
                default: done(false, "\(name) rejected that key. Check you copied all of it, or clear the box to skip.")
                }
            }
        }.resume()
    }

    private func saveAndAdvance(deepgram: Bool) {
        let key = (deepgram ? dgField : llmField).stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        func store() {
            if deepgram { Cloud.deepgramKey = key }
            else { Cloud.llmKey = key; if !key.isEmpty { Cloud.llmBaseURL = Onboarding.groqBase; Cloud.llmModel = Onboarding.groqModel } }
            app.refreshAI(); main.reloadKeyFields()
        }
        if key.isEmpty && deepgram && !app.transcriber.ready {
            status.stringValue = "MyType needs this key to turn your voice into text. It's free to get."
            status.textColor = .systemOrange
            return
        }
        guard !key.isEmpty else { store(); go(step + 1); return }
        checking = true
        nextButton.title = "Checking…"; nextButton.isEnabled = false
        status.stringValue = "Checking your key…"; status.textColor = .secondaryLabelColor
        check(deepgram: deepgram, key: key) { [weak self] ok, msg in
            guard let self else { return }
            self.checking = false
            self.status.stringValue = msg
            self.status.textColor = ok == true ? .systemGreen : (ok == nil ? .systemOrange : .systemRed)
            self.refreshNextTitle()
            if ok == false { return }
            store()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if self.step == (deepgram ? 1 : 2) { self.go(self.step + 1) } }
        }
    }

    // MARK: navigation

    @objc private func back() { go(step - 1) }
    @objc private func next() {
        switch step {
        case 1: saveAndAdvance(deepgram: true)
        case 2: saveAndAdvance(deepgram: false)
        case 5: window.close()
        default: go(step + 1)
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate(); timer = nil
        UserDefaults.standard.set(true, forKey: "onboarded")
        app.refreshAI()
        main.reloadKeyFields()
        main.show()
    }
}
