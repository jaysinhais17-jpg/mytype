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

// MARK: theme

enum Theme {
    static let purple = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.98, alpha: 1)
    static let deep = NSColor(srgbRed: 0.34, green: 0.19, blue: 0.72, alpha: 1)
    static let tint = purple.withAlphaComponent(0.16)

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    static let bg = dynamic(light: NSColor(white: 0.975, alpha: 1), dark: NSColor(white: 0.115, alpha: 1))
    static let sidebar = dynamic(light: NSColor(srgbRed: 0.955, green: 0.945, blue: 0.98, alpha: 1),
                                 dark: NSColor(srgbRed: 0.09, green: 0.085, blue: 0.12, alpha: 1))
    static let card = dynamic(light: .white, dark: NSColor(white: 0.16, alpha: 1))
    static let field = dynamic(light: NSColor(white: 0.96, alpha: 1), dark: NSColor(white: 0.12, alpha: 1))
    static let line = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.09))
}

func makeLabel(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, wrap: Bool = false) -> NSTextField {
    let t = wrap ? NSTextField(wrappingLabelWithString: s) : NSTextField(labelWithString: s)
    t.font = .systemFont(ofSize: size, weight: weight)
    t.textColor = color
    return t
}

/// Rounded, dynamically coloured panel.
final class Surface: NSView {
    var fill: NSColor { didSet { needsDisplay = true } }
    var stroke: NSColor? { didSet { needsDisplay = true } }
    init(fill: NSColor, stroke: NSColor? = nil, radius: CGFloat = 12) {
        self.fill = fill; self.stroke = stroke
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fill.cgColor
            layer?.borderColor = stroke?.cgColor
            layer?.borderWidth = stroke == nil ? 0 : 1
        }
    }
}

final class GradientCard: NSView {
    override func makeBackingLayer() -> CALayer {
        let l = CAGradientLayer()
        l.colors = [NSColor(srgbRed: 0.62, green: 0.42, blue: 1.0, alpha: 1).cgColor, Theme.deep.cgColor]
        l.startPoint = CGPoint(x: 0, y: 1); l.endPoint = CGPoint(x: 1, y: 0)
        return l
    }
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class FlippedClip: NSClipView { override var isFlipped: Bool { true } }

/// Flat rounded button. Primary = purple fill.
class PillButton: NSButton {
    private let primary: Bool
    private let caption: String
    init(title: String, primary: Bool = true) {
        self.primary = primary; self.caption = title
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isHighlighted: Bool { didSet { restyle() } }
    override func viewDidChangeEffectiveAppearance() { restyle() }
    override var intrinsicContentSize: NSSize { NSSize(width: super.intrinsicContentSize.width + 26, height: 32) }
    private func restyle() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let color: NSColor = primary ? .white : .labelColor
        attributedTitle = NSAttributedString(string: caption, attributes: [
            .foregroundColor: color, .font: NSFont.systemFont(ofSize: 13, weight: .medium), .paragraphStyle: p])
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base: NSColor = primary ? Theme.purple : Theme.field
            layer?.backgroundColor = (isHighlighted ? base.blended(withFraction: 0.25, of: .black) ?? base : base).cgColor
            layer?.borderColor = Theme.line.cgColor
            layer?.borderWidth = primary ? 0 : 1
        }
    }
}

/// Button that reports mouse-down and mouse-up, for push-to-talk from the window.
final class HoldButton: PillButton {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        onDown?()
        super.mouseDown(with: event)
        onUp?()
    }
}

final class PurpleSwitch: NSControl {
    var isOn = false { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 42, height: 24) }
    override func draw(_ dirtyRect: NSRect) {
        (isOn ? Theme.purple : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let d: CGFloat = 20
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: isOn ? bounds.width - d - 2 : 2, y: 2, width: d, height: d)).fill()
    }
    override func mouseDown(with event: NSEvent) { isOn.toggle(); sendAction(action, to: target) }
}

final class NavButton: NSButton {
    private let caption: String
    var isSelected = false { didSet { restyle() } }
    init(title: String, symbol: String) {
        caption = title
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        imagePosition = .imageLeading
        alignment = .left
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func restyle() {
        let c: NSColor = isSelected ? Theme.purple : .labelColor
        contentTintColor = c
        attributedTitle = NSAttributedString(string: "  " + caption, attributes: [
            .foregroundColor: c, .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)])
        layer?.backgroundColor = (isSelected ? Theme.tint : .clear).cgColor
    }
}

final class CheckRow: NSObject {
    let dot = NSTextField(labelWithString: "●")
    let button = PillButton(title: "Grant")
    let view = NSStackView()
    private let action: (() -> Void)?

    init(title: String, detail: String, action: (() -> Void)?) {
        self.action = action
        super.init()
        let t = makeLabel(title, size: 13, weight: .medium)
        let d = makeLabel(detail, size: 11, color: .secondaryLabelColor, wrap: true)
        dot.font = .systemFont(ofSize: 13)
        let text = NSStackView(views: [t, d])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
        button.target = self; button.action = #selector(tap)
        button.isHidden = action == nil
        button.setContentHuggingPriority(.required, for: .horizontal)
        text.setContentHuggingPriority(.init(250), for: .horizontal)
        view.setViews([dot, text, button], in: .leading)
        view.orientation = .horizontal; view.alignment = .centerY; view.spacing = 10
    }

    @objc private func tap() { action?() }

    func set(ok: Bool, pending: Bool = false) {
        dot.textColor = ok ? .systemGreen : (pending ? .systemOrange : .systemRed)
        button.isHidden = ok || action == nil
    }
}

// MARK: window

final class MainWindow: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    let window: NSWindow
    private unowned let app: App
    private let micRow: CheckRow, axRow: CheckRow, inputRow: CheckRow, keyRow: CheckRow
    private let tryView = NSTextView()
    private let historyStack = NSStackView()
    private let dictView = NSTextView()
    private let snipView = NSTextView()
    private let aiSwitch = PurpleSwitch(), langSwitch = PurpleSwitch(), loginSwitch = PurpleSwitch()
    private let dgField = NSSecureTextField(), llmKeyField = NSSecureTextField()
    private let llmURLField = NSTextField(), llmModelField = NSTextField()
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = makeLabel("", size: 11, weight: .medium)
    private let engineLabel = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let statusDot = makeLabel("●", size: 10, color: .systemOrange)
    private var setupBanner: Surface!
    private var nav: [NavButton] = []
    private var pages: [NSView] = []
    private let content = NSView()
    private var timer: Timer?
    private var selectedPage = 0
    private var usageCells: [[NSTextField]] = []
    private let dgRateField = NSTextField(), inRateField = NSTextField(), outRateField = NSTextField(), creditField = NSTextField()
    private let cleanupFreeSwitch = PurpleSwitch()
    private let sumWould = makeLabel("–", size: 26, weight: .bold), sumPay = makeLabel("–", size: 26, weight: .bold), sumCredit = makeLabel("–", size: 26, weight: .bold)
    private let sumWouldNote = makeLabel("", size: 11, color: .secondaryLabelColor, wrap: true), sumPayNote = makeLabel("", size: 11, color: .secondaryLabelColor, wrap: true), sumCreditNote = makeLabel("", size: 11, color: .secondaryLabelColor, wrap: true)
    private let creditLabel = makeLabel("", size: 12, color: .secondaryLabelColor, wrap: true)

    private static let presets: [(String, String, String)] = [
        ("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-flash-lite-latest"),
        ("Groq (fastest)", "https://api.groq.com/openai/v1", "qwen/qwen3.8-27b"),
        ("DeepSeek", "https://api.deepseek.com", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
    ]

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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "MyType"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 780, height: 520)
        window.isReleasedWhenClosed = false
        super.init()

        pages = [buildHome(), buildDictionary(), buildUsage(), buildSettings()]
        let root = Surface(fill: Theme.bg, radius: 0)
        window.contentView = root
        let side = buildSidebar()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(side); root.addSubview(content)
        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo: root.leadingAnchor), side.topAnchor.constraint(equalTo: root.topAnchor),
            side.bottomAnchor.constraint(equalTo: root.bottomAnchor), side.widthAnchor.constraint(equalToConstant: 210),
            content.leadingAnchor.constraint(equalTo: side.trailingAnchor), content.topAnchor.constraint(equalTo: root.topAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor), content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        select(0)
        window.center()
        refresh()
        reloadHistory()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // MARK: building blocks

    private func pin(_ v: NSView, in p: NSView, top: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0, bottom: CGFloat = 0) {
        v.translatesAutoresizingMaskIntoConstraints = false
        p.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: p.topAnchor, constant: top), v.leadingAnchor.constraint(equalTo: p.leadingAnchor, constant: leading),
            v.trailingAnchor.constraint(equalTo: p.trailingAnchor, constant: -trailing), v.bottomAnchor.constraint(equalTo: p.bottomAnchor, constant: -bottom),
        ])
    }

    /// Vertical stack whose children each fill its width (NSStackView's `.width` alignment only equalises them).
    private func vstack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical; s.alignment = .leading; s.spacing = spacing
        for v in views { v.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true }
        return s
    }

    private func card(_ views: [NSView], spacing: CGFloat = 14) -> Surface {
        let s = Surface(fill: Theme.card, stroke: Theme.line, radius: 14)
        pin(vstack(views, spacing: spacing), in: s, top: 16, leading: 18, trailing: 18, bottom: 16)
        return s
    }

    private func divider() -> Surface {
        let s = Surface(fill: Theme.line, radius: 0)
        s.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return s
    }

    private func sectionTitle(_ s: String) -> NSTextField { makeLabel(s.uppercased(), size: 11, weight: .semibold, color: Theme.purple) }

    private func settingRow(_ title: String, _ sub: String?, _ control: NSView) -> NSStackView {
        var lv: [NSView] = [makeLabel(title, size: 13, weight: .medium)]
        if let sub { lv.append(makeLabel(sub, size: 11, color: .secondaryLabelColor, wrap: true)) }
        let left = NSStackView(views: lv)
        left.orientation = .vertical; left.alignment = .leading; left.spacing = 2
        left.setContentHuggingPriority(.init(250), for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        let r = NSStackView(views: [left, control])
        r.orientation = .horizontal; r.alignment = .centerY; r.spacing = 16
        return r
    }

    private func field(_ f: NSTextField, placeholder: String, value: String, width: CGFloat = 270) -> NSTextField {
        f.stringValue = value; f.placeholderString = placeholder; f.delegate = self
        f.bezelStyle = .roundedBezel; f.focusRingType = .none
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    private func page(_ views: [NSView]) -> NSScrollView {
        let st = vstack(views, spacing: 18)
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        pin(st, in: doc, top: 46, leading: 34, trailing: 34, bottom: 34)
        let sv = NSScrollView()
        sv.contentView = FlippedClip()
        sv.documentView = doc
        sv.drawsBackground = false
        sv.contentView.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: sv.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: sv.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: sv.contentView.trailingAnchor),
        ])
        return sv
    }

    private func pageHeader(_ title: String, _ sub: String) -> NSStackView {
        let h = NSStackView(views: [makeLabel(title, size: 26, weight: .bold), makeLabel(sub, size: 13, color: .secondaryLabelColor, wrap: true)])
        h.orientation = .vertical; h.alignment = .leading; h.spacing = 4
        return h
    }

    // MARK: sidebar

    private func buildSidebar() -> NSView {
        let side = Surface(fill: Theme.sidebar, radius: 0)
        let edge = Surface(fill: Theme.line, radius: 0)
        side.addSubview(edge)
        NSLayoutConstraint.activate([edge.trailingAnchor.constraint(equalTo: side.trailingAnchor), edge.topAnchor.constraint(equalTo: side.topAnchor),
                                     edge.bottomAnchor.constraint(equalTo: side.bottomAnchor), edge.widthAnchor.constraint(equalToConstant: 1)])

        let logo = Surface(fill: Theme.purple, radius: 8)
        let glyph = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .bold))!)
        glyph.contentTintColor = .white
        logo.addSubview(glyph); glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([logo.widthAnchor.constraint(equalToConstant: 30), logo.heightAnchor.constraint(equalToConstant: 30),
                                     glyph.centerXAnchor.constraint(equalTo: logo.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: logo.centerYAnchor)])
        let brand = NSStackView(views: [logo, makeLabel("MyType", size: 17, weight: .bold)])
        brand.spacing = 9; brand.alignment = .centerY

        let items = [("Home", "house"), ("Dictionary", "character.book.closed"), ("Usage", "dollarsign.circle"), ("Settings", "gearshape")]
        nav = items.enumerated().map { i, it in
            let b = NavButton(title: it.0, symbol: it.1)
            b.tag = i; b.target = self; b.action = #selector(navTapped(_:))
            return b
        }
        let menu = vstack(nav, spacing: 4)

        let statusRow = NSStackView(views: [statusDot, statusLabel]); statusRow.spacing = 6
        let footer = NSStackView(views: [statusRow, engineLabel])
        footer.orientation = .vertical; footer.alignment = .leading; footer.spacing = 3

        let top = vstack([brand, menu], spacing: 26)
        top.translatesAutoresizingMaskIntoConstraints = false; footer.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(top); side.addSubview(footer)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: side.topAnchor, constant: 52),
            top.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 16), top.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -20),
        ])
        return side
    }

    @objc private func navTapped(_ b: NavButton) { select(b.tag) }

    private func select(_ i: Int) {
        selectedPage = i
        if i == 2 { reloadUsage() }
        for (n, b) in nav.enumerated() { b.isSelected = n == i }
        content.subviews.forEach { $0.removeFromSuperview() }
        pin(pages[i], in: content)
    }

    // MARK: pages

    private func buildHome() -> NSView {
        let hero = GradientCard()
        let big = makeLabel("Hold Fn to talk", size: 24, weight: .bold, color: .white)
        let small = makeLabel("Double-tap Fn to go hands-free, then tap once more to stop. Right Option works too.", size: 13,
                              color: NSColor.white.withAlphaComponent(0.85), wrap: true)
        let text = NSStackView(views: [big, small]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 6
        let mic = NSImageView(image: NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 34, weight: .semibold))!)
        mic.contentTintColor = NSColor.white.withAlphaComponent(0.92)
        mic.setContentHuggingPriority(.required, for: .horizontal)
        let heroRow = NSStackView(views: [text, mic]); heroRow.spacing = 20; heroRow.alignment = .centerY
        pin(heroRow, in: hero, top: 22, leading: 26, trailing: 26, bottom: 22)

        let goSettings = PillButton(title: "Open Settings", primary: false)
        goSettings.target = self; goSettings.action = #selector(openSettings)
        let warn = makeLabel("Finish setup: MyType is missing a permission.", size: 13, weight: .medium)
        let bannerRow = NSStackView(views: [warn, goSettings]); bannerRow.spacing = 12; bannerRow.alignment = .centerY
        setupBanner = Surface(fill: NSColor.systemOrange.withAlphaComponent(0.13), stroke: NSColor.systemOrange.withAlphaComponent(0.4), radius: 12)
        pin(bannerRow, in: setupBanner, top: 10, leading: 16, trailing: 12, bottom: 10)

        tryView.isEditable = true
        tryView.font = .systemFont(ofSize: 13)
        tryView.drawsBackground = false
        tryView.insertionPointColor = Theme.purple
        tryView.textContainerInset = NSSize(width: 6, height: 8)
        tryView.isVerticallyResizable = true
        tryView.autoresizingMask = [.width]
        tryView.textContainer?.widthTracksTextView = true
        let tryScroll = NSScrollView()
        tryScroll.documentView = tryView
        tryScroll.drawsBackground = false
        tryScroll.hasVerticalScroller = true
        tryScroll.translatesAutoresizingMaskIntoConstraints = false
        tryScroll.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let tryBox = Surface(fill: Theme.field, stroke: Theme.line, radius: 10)
        pin(tryScroll, in: tryBox, top: 2, leading: 2, trailing: 2, bottom: 2)

        let talk = HoldButton(title: "Hold to talk")
        talk.onDown = { [weak self] in self?.app.beginManual() }
        talk.onUp = { [weak self] in self?.app.finishManual() }
        let copy = PillButton(title: "Copy last", primary: false)
        copy.target = self; copy.action = #selector(copyLast)
        let buttons = NSStackView(views: [talk, copy]); buttons.spacing = 8
        let tryRow = NSStackView(views: [makeLabel("Test it here without leaving MyType.", size: 12, color: .secondaryLabelColor), buttons])
        tryRow.alignment = .centerY
        let tryCard = card([sectionTitle("Try it"), tryBox, tryRow], spacing: 12)

        historyStack.orientation = .vertical; historyStack.alignment = .leading; historyStack.spacing = 12
        let recentCard = card([sectionTitle("Recent"), historyStack], spacing: 12)

        return page([pageHeader("Welcome back", "Speak anywhere. Your words appear at the cursor."), setupBanner, hero, tryCard, recentCard])
    }

    private func buildDictionary() -> NSView {
        dictView.string = Config.dictionary
        dictView.font = .systemFont(ofSize: 14)
        dictView.drawsBackground = false
        dictView.insertionPointColor = Theme.purple
        dictView.textContainerInset = NSSize(width: 8, height: 10)
        dictView.isVerticallyResizable = true
        dictView.autoresizingMask = [.width]
        dictView.textContainer?.widthTracksTextView = true
        dictView.delegate = self
        let sv = NSScrollView()
        sv.documentView = dictView
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.heightAnchor.constraint(equalToConstant: 190).isActive = true
        let box = Surface(fill: Theme.field, stroke: Theme.line, radius: 10)
        pin(sv, in: box, top: 2, leading: 2, trailing: 2, bottom: 2)
        let save = PillButton(title: "Save")
        save.target = self; save.action = #selector(saveDict)
        let saveRow = NSStackView(views: [makeLabel("Separate words with commas. Saved automatically when you click away.", size: 12, color: .secondaryLabelColor), save])
        saveRow.alignment = .centerY
        let c = card([sectionTitle("Your words"), box, saveRow], spacing: 12)

        snipView.string = Config.snippets
        snipView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        snipView.drawsBackground = false
        snipView.insertionPointColor = Theme.purple
        snipView.textContainerInset = NSSize(width: 8, height: 10)
        snipView.isAutomaticQuoteSubstitutionEnabled = false
        snipView.isAutomaticDashSubstitutionEnabled = false
        snipView.isVerticallyResizable = true
        snipView.autoresizingMask = [.width]
        snipView.textContainer?.widthTracksTextView = true
        snipView.delegate = self
        let ssv = NSScrollView()
        ssv.documentView = snipView
        ssv.drawsBackground = false
        ssv.hasVerticalScroller = true
        ssv.translatesAutoresizingMaskIntoConstraints = false
        ssv.heightAnchor.constraint(equalToConstant: 120).isActive = true
        let sbox = Surface(fill: Theme.field, stroke: Theme.line, radius: 10)
        pin(ssv, in: sbox, top: 2, leading: 2, trailing: 2, bottom: 2)
        let snipHint = makeLabel("One per line, like:  my email = jay@example.com. Say the words on the left and the text on the right is typed instead.", size: 12, color: .secondaryLabelColor, wrap: true)
        let sc = card([sectionTitle("Snippets"), sbox, snipHint], spacing: 12)
        return page([pageHeader("Dictionary", "Names, drugs and jargon MyType should always spell right."), c, sc])
    }

    private static let usagePeriods = ["Today", "This month", "All time"]
    private static let usageColumns = ["", "Dictations", "Audio", "Speech", "Cleanup tokens", "Cleanup", "List price", "You pay"]

    private func buildUsage() -> NSView {
        var rows: [[NSView]] = [MainWindow.usageColumns.map { makeLabel($0, size: 11, weight: .semibold, color: .secondaryLabelColor) }]
        usageCells = []
        for p in MainWindow.usagePeriods {
            let cells = (0..<7).map { i in makeLabel("–", size: 13, weight: i >= 5 ? .bold : .regular) }
            usageCells.append(cells)
            rows.append([makeLabel(p, size: 13, weight: .medium)] + cells)
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12; grid.columnSpacing = 22
        func tile(_ title: String, _ value: NSTextField, _ note: NSTextField, accent: Bool = false) -> Surface {
            let t = Surface(fill: accent ? Theme.purple.withAlphaComponent(0.12) : Theme.field, stroke: accent ? Theme.purple.withAlphaComponent(0.5) : Theme.line, radius: 12)
            pin(vstack([makeLabel(title, size: 12, weight: .medium, color: .secondaryLabelColor), value, note], spacing: 4), in: t, top: 14, leading: 16, trailing: 16, bottom: 14)
            return t
        }
        let tiles = NSStackView(views: [tile("Would cost at list price", sumWould, sumWouldNote),
                                        tile("You actually pay", sumPay, sumPayNote, accent: true),
                                        tile("Deepgram credit left", sumCredit, sumCreditNote)])
        tiles.distribution = .fillEqually; tiles.spacing = 12
        let refresh = PillButton(title: "Refresh balance", primary: false)
        refresh.target = self; refresh.action = #selector(refreshBalance)
        let summary = card([sectionTitle("This month"), tiles, refresh], spacing: 14)
        let table = card([sectionTitle("Running cost"), grid, creditLabel,
                          makeLabel("List price is what these dictations would cost at normal rates. You pay is what actually leaves your pocket: speech is covered by your Deepgram credit until it runs out, and cleanup is covered by the free tier while that switch is on. Estimates from the rates below, not an invoice.",
                                    size: 11, color: .secondaryLabelColor, wrap: true)])
        cleanupFreeSwitch.isOn = Usage.cleanupFree
        cleanupFreeSwitch.target = self; cleanupFreeSwitch.action = #selector(toggleCleanupFree)
        let rates = card([
            sectionTitle("Rates and credits (USD)"),
            settingRow("Deepgram credit", "Your sign-up credit. Speech costs you nothing until list-price spend passes this.",
                       field(creditField, placeholder: "200", value: String(Usage.deepgramCredit), width: 90)),
            settingRow("Cleanup is on a free tier", "Groq has a rate-limited free tier for now. Turn this off if you move to a paid plan.", cleanupFreeSwitch),
            settingRow("Speech, per minute", "Deepgram Nova-3 streaming was about $0.0077/min when I set this up.",
                       field(dgRateField, placeholder: "0.0077", value: String(Usage.deepgramPerMinute), width: 90)),
            settingRow("Cleanup input, per 1M tokens", nil, field(inRateField, placeholder: "0.29", value: String(Usage.llmInPerMillion), width: 90)),
            settingRow("Cleanup output, per 1M tokens", "Defaults are a rough guess for Groq's Qwen models. Check your provider's pricing page and edit.",
                       field(outRateField, placeholder: "0.59", value: String(Usage.llmOutPerMillion), width: 90)),
        ])
        return page([pageHeader("Usage", "What your API keys are costing, tracked on this Mac."), summary, table, rates])
    }

    @objc private func refreshBalance() { DeepgramBalance.refresh(force: true) { [weak self] in self?.reloadUsage() } }

    func reloadUsage() {
        DeepgramBalance.refresh { [weak self] in self?.reloadUsage() }
        let evs = Usage.events()
        let cal = Calendar.current, now = Date()
        let since: [Date?] = [cal.startOfDay(for: now), cal.dateInterval(of: .month, for: now)?.start, nil]
        func usd(_ v: Double) -> String { v < 0.1 ? String(format: "$%.4f", v) : String(format: "$%.2f", v) }
        func k(_ n: Int) -> String { n >= 10_000 ? String(format: "%.1fk", Double(n) / 1000) : String(n) }
        for (i, s) in since.enumerated() {
            let t = Usage.totals(evs, since: s)
            let vals = ["\(t.dictations)", String(format: "%.1f min", t.audioSeconds / 60), usd(t.speechCost),
                        "\(k(t.promptTokens)) in / \(k(t.completionTokens)) out", usd(t.cleanupCost), usd(t.total), usd(t.youPay)]
            for (c, v) in vals.enumerated() { usageCells[i][c].stringValue = v }
        }
        let st = Usage.creditStatus(evs), credit = Usage.deepgramCredit
        let month = Usage.totals(evs, since: since[1])
        sumWould.stringValue = usd(month.total)
        sumWouldNote.stringValue = "Speech \(usd(month.speechCost)) + cleanup \(usd(month.cleanupCost)). What this would cost with no credit and no free tier."
        sumPay.stringValue = usd(month.youPay)
        sumPayNote.stringValue = month.youPay < 0.005 ? "Nothing. Your Deepgram credit and the free cleanup tier cover it all."
            : "Speech beyond your credit\(Usage.cleanupFree ? "" : " plus cleanup")."
        if let live = DeepgramBalance.amount, DeepgramBalance.note.isEmpty {
            sumCredit.stringValue = usd(live)
            let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
            sumCreditNote.stringValue = "Live from Deepgram (\(f.string(from: DeepgramBalance.updated ?? Date()))). \(usd(max(0, credit - live))) of \(usd(credit)) used so far."
        } else {
            sumCredit.stringValue = usd(max(0, credit - st.used))
            sumCreditNote.stringValue = DeepgramBalance.note.isEmpty ? "Estimated from this Mac's usage." : "Estimated from this Mac's usage. " + DeepgramBalance.note
        }
        var line = "Deepgram credit: \(usd(max(0, credit - st.used))) left of \(usd(credit)). At your current pace the true cost is about \(usd(st.monthly)) a month"
        if st.monthly > 0 { line += String(format: ", so the credit lasts roughly %.0f months.", max(0, credit - st.used) / max(0.0001, evs.isEmpty ? 1 : st.monthly)) } else { line += "." }
        creditLabel.stringValue = line
    }

    private func buildSettings() -> NSView {
        for (sw, sel) in [(aiSwitch, #selector(toggleAI)), (langSwitch, #selector(toggleLang)), (loginSwitch, #selector(toggleLogin))] {
            sw.target = self; sw.action = sel
        }
        presetPopup.addItems(withTitles: ["Custom"] + MainWindow.presets.map { $0.0 })
        presetPopup.target = self; presetPopup.action = #selector(pickPreset)
        presetPopup.widthAnchor.constraint(equalToConstant: 270).isActive = true
        if let i = MainWindow.presets.firstIndex(where: { $0.1 == Cloud.llmBaseURL }) { presetPopup.selectItem(at: i + 1) }

        let speech = card([
            sectionTitle("Cloud (optional)"),
            settingRow("Deepgram key", "Streams speech to Deepgram: faster and more accurate.",
                       field(dgField, placeholder: "Paste key", value: Cloud.deepgramKey)),
            divider(),
            settingRow("Cleanup provider", nil, presetPopup),
            settingRow("Cleanup key", "Used to fix punctuation and edits.", field(llmKeyField, placeholder: "Paste API key", value: Cloud.llmKey)),
            settingRow("Base URL", nil, field(llmURLField, placeholder: "https://…", value: Cloud.llmBaseURL)),
            settingRow("Model", nil, field(llmModelField, placeholder: "model name", value: Cloud.llmModel)),
            makeLabel("With keys set, audio and text leave your Mac. Leave blank to stay fully on-device. Keys are stored on this Mac only.",
                      size: 11, color: .secondaryLabelColor, wrap: true),
        ])
        let general = card([
            sectionTitle("General"),
            settingRow("AI cleanup", "Smarter edits. Uses your cloud key if set, otherwise a local model (~2 GB RAM).", aiSwitch),
            divider(),
            settingRow("Auto-detect language", "Restart MyType to apply.", langSwitch),
            divider(),
            settingRow("Launch at login", nil, loginSwitch),
        ])
        let perms = card([sectionTitle("Permissions"), micRow.view, axRow.view, inputRow.view, keyRow.view])
        return page([pageHeader("Settings", "Speech, cleanup and permissions."), speech, general, perms])
    }

    // MARK: actions

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func insertTry(_ text: String) {
        select(0)
        window.makeFirstResponder(tryView)
        tryView.insertText(text + " ", replacementRange: tryView.selectedRange())
    }

    func reloadHistory() {
        historyStack.arrangedSubviews.forEach { historyStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let items = History.items.prefix(20)
        if items.isEmpty {
            historyStack.addArrangedSubview(makeLabel("Your dictations will show up here.", size: 13, color: .secondaryLabelColor))
            return
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let g = DateFormatter(); g.dateFormat = "d MMM HH:mm"
        for (i, e) in items.enumerated() {
            if i > 0 {
                let d = divider()
                historyStack.addArrangedSubview(d)
                d.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
            }
            let when = makeLabel(Calendar.current.isDateInToday(e.date) ? f.string(from: e.date) : g.string(from: e.date),
                                 size: 11, weight: .medium, color: Theme.purple)
            let body = makeLabel(e.text, size: 13, wrap: true)
            body.isSelectable = true
            let row = NSStackView(views: [when, body])
            row.orientation = .vertical; row.alignment = .leading; row.spacing = 3
            historyStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
        }
    }

    func refresh() {
        if selectedPage == 2 { reloadUsage() }
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        micRow.set(ok: mic); axRow.set(ok: ax); inputRow.set(ok: input)
        keyRow.set(ok: app.keySeen, pending: app.hotkeyInstalled)
        setupBanner.isHidden = mic && ax && input
        let ready = app.statusText == "Ready"
        statusDot.textColor = ready ? .systemGreen : .systemOrange
        statusLabel.stringValue = app.statusText
        engineLabel.stringValue = "\(app.engineText)\n\(app.llmText)"
        if aiSwitch.isOn != app.aiEnabled { aiSwitch.isOn = app.aiEnabled }
        if langSwitch.isOn != app.autoLanguage { langSwitch.isOn = app.autoLanguage }
        if loginSwitch.isOn != app.loginEnabled { loginSwitch.isOn = app.loginEnabled }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        Cloud.deepgramKey = dgField.stringValue
        Cloud.llmKey = llmKeyField.stringValue
        Cloud.llmBaseURL = llmURLField.stringValue
        Cloud.llmModel = llmModelField.stringValue
        if let v = Double(dgRateField.stringValue) { Usage.deepgramPerMinute = v }
        if let v = Double(inRateField.stringValue) { Usage.llmInPerMillion = v }
        if let v = Double(outRateField.stringValue) { Usage.llmOutPerMillion = v }
        if let v = Double(creditField.stringValue) { Usage.deepgramCredit = v }
        app.refreshAI()
        refresh()
        if selectedPage == 2 { reloadUsage() }
    }
    func textDidEndEditing(_ notification: Notification) { saveDict() }

    @objc private func openSettings() { select(3) }
    @objc private func pickPreset() {
        let i = presetPopup.indexOfSelectedItem - 1
        guard i >= 0 else { return }
        llmURLField.stringValue = MainWindow.presets[i].1
        llmModelField.stringValue = MainWindow.presets[i].2
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }
    @objc private func saveDict() { Config.dictionary = dictView.string; Config.snippets = snipView.string }
    @objc private func toggleCleanupFree() { Usage.cleanupFree = cleanupFreeSwitch.isOn; reloadUsage() }
    @objc private func toggleAI() { app.aiEnabled = aiSwitch.isOn }
    @objc private func toggleLang() { app.autoLanguage = langSwitch.isOn }
    @objc private func toggleLogin() {
        if let err = app.setLogin(loginSwitch.isOn) {
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
