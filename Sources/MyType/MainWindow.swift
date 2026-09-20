import AppKit
import AVFoundation
import ApplicationServices

struct HistoryEntry: Codable {
    let date: Date
    let text: String
    var raw: String? = nil   // transcript before cleanup, for diagnosing mishearings
    var secs: Double? = nil  // audio length, for words-per-minute
}

enum History {
    static var items: [HistoryEntry] {
        guard let d = UserDefaults.standard.data(forKey: "history"),
              let a = try? JSONDecoder().decode([HistoryEntry].self, from: d) else { return [] }
        return a
    }
    static func words(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    /// Lifetime word count; the 50-entry history is only a window, so this keeps its own tally.
    static var totalWords: Int {
        if let n = UserDefaults.standard.object(forKey: "statWords") as? Int { return n }
        return items.reduce(0) { $0 + words($1.text) }
    }
    static func add(_ text: String, raw: String? = nil, secs: Double? = nil) {
        Stats.record(words: words(text), secs: secs)
        UserDefaults.standard.set(totalWords + words(text), forKey: "statWords")
        var a = items
        a.insert(HistoryEntry(date: Date(), text: text, raw: raw, secs: secs), at: 0)
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
    static let bg = dynamic(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 0.115, alpha: 1))
    static let sidebar = dynamic(light: NSColor(white: 0.955, alpha: 1), dark: NSColor(white: 0.085, alpha: 1))
    /// Soft grey behind the selected sidebar item and filter pills.
    static let pill = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.10))
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

/// Headlines and big numbers: medium-weight system display face, like Typeless's geometric headlines.
func serifFont(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
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
        layer?.cornerRadius = 16
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
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        imagePosition = .imageLeading
        alignment = .left
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { restyle() }
    private func restyle() {
        contentTintColor = isSelected ? Theme.purple : .secondaryLabelColor
        attributedTitle = NSAttributedString(string: "  " + caption, attributes: [
            .foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)])
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isSelected ? Theme.pill : .clear).cgColor
        }
    }
}

/// Small rounded filter tab ("All", "Today"…).
final class FilterPill: NSButton {
    private let caption: String
    var isSelected = false { didSet { restyle() } }
    init(title: String) {
        caption = title
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 15
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: super.intrinsicContentSize.width + 24, height: 30) }
    override func viewDidChangeEffectiveAppearance() { restyle() }
    private func restyle() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        attributedTitle = NSAttributedString(string: caption, attributes: [
            .foregroundColor: isSelected ? NSColor.white : NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .paragraphStyle: p])
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (isSelected ? Theme.purple : Theme.pill).cgColor
        }
    }
}

/// Lays subviews out left to right, wrapping to new rows; height follows the width.
final class FlowView: NSView {
    var gap: CGFloat = 8
    private var heightC: NSLayoutConstraint!
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightC = heightAnchor.constraint(equalToConstant: 10)
        heightC.isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func setItems(_ v: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        v.forEach { addSubview($0) }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.fittingSize
            if x > 0 && x + sz.width > bounds.width { x = 0; y += rowH + gap; rowH = 0 }
            v.frame = NSRect(x: x, y: y, width: sz.width, height: sz.height)
            x += sz.width + gap; rowH = max(rowH, sz.height)
        }
        let h = max(y + rowH, 10)
        if abs(heightC.constant - h) > 0.5 { heightC.constant = h }
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
    private let statWords = makeLabel("0", size: 28), statSpeak = makeLabel("–", size: 28), statType = makeLabel("–", size: 28), statSaved = makeLabel("0 min", size: 28)
    private let statTypeCap = makeLabel("Typing WPM", size: 12, color: .secondaryLabelColor)
    private let chart = BarChart()
    private let chartTotal = makeLabel("", size: 12, color: .secondaryLabelColor)
    private let moneyValue = makeLabel("$0", size: 34), moneyNote = makeLabel("", size: 12, color: .secondaryLabelColor, wrap: true)
    private let planField = NSTextField()
    private let typeView = NSTextView(), typePassage = NSTextField(wrappingLabelWithString: "")
    private let typeLive = makeLabel("", size: 12, color: .secondaryLabelColor), typeBest = makeLabel("", size: 12, color: .secondaryLabelColor)
    private var typeStart: Date?, typeDone = false, passageIndex = Int.random(in: 0..<3)
    private static let passages = [
        "The patient presented with acute pain in the right lower quadrant, a mild fever and a raised white cell count. After examination, the surgeon decided to proceed with an appendicectomy that same evening.",
        "Good notes are short, specific and easy to scan. Write the finding, the reason and the next step, then move on. Clear writing saves time for everyone who has to read it after you.",
        "Please review the attached report before Friday and let me know if anything looks wrong. I would like to send the final version to the whole team by the end of the day.",
    ]
    private var shown: [HistoryEntry] = []
    private var historyFilter = 0
    private var filterPills: [FilterPill] = []
    private let wordFlow = FlowView()
    private var newWordField: NSTextField?
    private var words: [String] = []
    private let snipView = NSTextView()
    private let aiSwitch = PurpleSwitch(), langSwitch = PurpleSwitch(), loginSwitch = PurpleSwitch(), chipSwitch = PurpleSwitch()
    private let dgField = NSSecureTextField(), llmKeyField = NSSecureTextField()
    private let llmURLField = NSTextField(), llmModelField = NSTextField()
    private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statusLabel = makeLabel("", size: 11, weight: .medium)
    private let engineLabel = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let statusDot = makeLabel("●", size: 10, color: .systemOrange)
    private var setupBanner: Surface!
    private var nav: [NavButton] = []
    private var pages: [NSView] = []
    private let content = NSView()
    private var timer: Timer?
    private var selectedPage = 0
    var onSetup: (() -> Void)?
    private var usageCells: [[NSTextField]] = []
    private let dgRateField = NSTextField(), inRateField = NSTextField(), outRateField = NSTextField(), creditField = NSTextField()
    private let cleanupFreeSwitch = PurpleSwitch()
    private let rateField = NSTextField()
    /// The three cost tiles shown on both Home and Usage. Each page needs its own labels.
    private struct CostTiles {
        let would = makeLabel("–", size: 26, weight: .bold), pay = makeLabel("–", size: 26, weight: .bold), credit = makeLabel("–", size: 26, weight: .bold)
        let wouldNote = makeLabel("", size: 11, color: .secondaryLabelColor, wrap: true), payNote = makeLabel("", size: 11, color: .secondaryLabelColor, wrap: true), creditNote = makeLabel("", size: 11, color: .secondaryLabelColor, wrap: true)
    }
    private let usageTiles = CostTiles(), homeTiles = CostTiles()
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

        pages = [buildHome(), buildUsage(), buildDictionary(), buildHistory(), buildSettings()]
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
        Currency.refresh { [weak self] in self?.rateField.stringValue = String(format: "%.2f", Currency.rate); self?.reloadStats(); self?.reloadUsage() }
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
        let s = Surface(fill: Theme.card, stroke: Theme.line, radius: 16)
        pin(vstack(views, spacing: spacing), in: s, top: 18, leading: 20, trailing: 20, bottom: 18)
        return s
    }

    private func divider() -> Surface {
        let s = Surface(fill: Theme.line, radius: 0)
        s.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return s
    }

    private func sectionTitle(_ s: String, symbol: String? = nil) -> NSView {
        let t = makeLabel(s, size: 14, weight: .semibold)
        guard let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) else { return t }
        let iv = NSImageView(image: img); iv.contentTintColor = Theme.purple
        let r = NSStackView(views: [iv, t]); r.spacing = 7; r.alignment = .centerY
        return r
    }

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
        let st = vstack(views, spacing: 16)
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        pin(st, in: doc, top: 50, leading: 40, trailing: 40, bottom: 40)
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

    /// Big two-tone headline (dark, then grey), as on typeless.com.
    private func pageHeader(_ title: String, _ sub: String, grey: String = "") -> NSStackView {
        let t = NSTextField(labelWithAttributedString: {
            let a = NSMutableAttributedString(string: title, attributes: [.font: serifFont(32), .foregroundColor: NSColor.labelColor, .kern: -0.6])
            if !grey.isEmpty { a.append(NSAttributedString(string: grey, attributes: [.font: serifFont(32), .foregroundColor: NSColor.tertiaryLabelColor, .kern: -0.6])) }
            return a
        }())
        let h = NSStackView(views: [t, makeLabel(sub, size: 13, color: .secondaryLabelColor, wrap: true)])
        h.orientation = .vertical; h.alignment = .leading; h.spacing = 6
        h.setCustomSpacing(8, after: t)
        return h
    }

    /// Setting rows separated by hairlines.
    private func spaced(_ views: [NSView]) -> [NSView] {
        var out: [NSView] = []
        for (i, v) in views.enumerated() { if i > 0 { out.append(divider()) }; out.append(v) }
        return out
    }

    // MARK: sidebar

    private func buildSidebar() -> NSView {
        let side = Surface(fill: Theme.sidebar, radius: 0)
        let edge = Surface(fill: Theme.line, radius: 0)
        side.addSubview(edge)
        NSLayoutConstraint.activate([edge.trailingAnchor.constraint(equalTo: side.trailingAnchor), edge.topAnchor.constraint(equalTo: side.topAnchor),
                                     edge.bottomAnchor.constraint(equalTo: side.bottomAnchor), edge.widthAnchor.constraint(equalToConstant: 1)])

        let logo = Surface(fill: Theme.purple, radius: 9)
        let glyph = NSImageView(image: NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .bold))!)
        glyph.contentTintColor = .white
        logo.addSubview(glyph); glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([logo.widthAnchor.constraint(equalToConstant: 30), logo.heightAnchor.constraint(equalToConstant: 30),
                                     glyph.centerXAnchor.constraint(equalTo: logo.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: logo.centerYAnchor)])
        let brand = NSStackView(views: [logo, makeLabel("MyType", size: 16, weight: .semibold)])
        brand.spacing = 9; brand.alignment = .centerY
        brand.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)

        let items = [("Home", "house"), ("Usage", "chart.bar"), ("Dictionary", "character.book.closed"), ("History", "clock"), ("Settings", "gearshape")]
        nav = items.enumerated().map { i, it in
            let b = NavButton(title: it.0, symbol: it.1)
            b.tag = i; b.target = self; b.action = #selector(navTapped(_:))
            return b
        }
        let menu = vstack(Array(nav.prefix(4)), spacing: 2)

        let statusRow = NSStackView(views: [statusDot, statusLabel]); statusRow.spacing = 6
        let status = NSStackView(views: [statusRow, engineLabel])
        status.orientation = .vertical; status.alignment = .leading; status.spacing = 3
        status.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        let footer = vstack([nav[4], divider(), status], spacing: 10)

        let top = vstack([brand, menu], spacing: 24)
        top.translatesAutoresizingMaskIntoConstraints = false; footer.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(top); side.addSubview(footer)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: side.topAnchor, constant: 52),
            top.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 14), top.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -14),
            footer.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 14), footer.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -18),
        ])
        return side
    }

    @objc private func navTapped(_ b: NavButton) { select(b.tag) }

    private func select(_ i: Int) {
        selectedPage = i
        if i == 0 || i == 1 { reloadUsage() }
        for (n, b) in nav.enumerated() { b.isSelected = n == i }
        content.subviews.forEach { $0.removeFromSuperview() }
        pin(pages[i], in: content)
    }

    // MARK: pages

    private func buildHome() -> NSView {
        // ---- typing speed test
        typePassage.maximumNumberOfLines = 0
        typeView.isEditable = true
        typeView.font = .systemFont(ofSize: 14)
        typeView.drawsBackground = false
        typeView.insertionPointColor = Theme.purple
        typeView.textContainerInset = NSSize(width: 6, height: 8)
        typeView.isVerticallyResizable = true
        typeView.autoresizingMask = [.width]
        typeView.textContainer?.widthTracksTextView = true
        typeView.isAutomaticSpellingCorrectionEnabled = false
        typeView.isAutomaticQuoteSubstitutionEnabled = false
        typeView.isAutomaticTextReplacementEnabled = false
        typeView.isContinuousSpellCheckingEnabled = false
        typeView.delegate = self
        let typeScroll = NSScrollView()
        typeScroll.documentView = typeView
        typeScroll.drawsBackground = false
        typeScroll.hasVerticalScroller = false
        typeScroll.translatesAutoresizingMaskIntoConstraints = false
        typeScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let typeBox = Surface(fill: Theme.field, stroke: Theme.line, radius: 10)
        pin(typeScroll, in: typeBox, top: 2, leading: 2, trailing: 2, bottom: 2)
        let again = PillButton(title: "New passage", primary: false)
        again.target = self; again.action = #selector(newPassage)
        let typeTitle = makeLabel("Typing speed", size: 15, weight: .semibold)
        typeBest.setContentHuggingPriority(.init(200), for: .horizontal)
        let typeHead = NSStackView(views: [typeTitle, typeBest, again]); typeHead.spacing = 12; typeHead.alignment = .centerY
        typeHead.setCustomSpacing(12, after: typeBest)
        let typeCard = card([typeHead, typePassage, typeBox, typeLive], spacing: 12)
        loadPassage()

        // ---- stats
        func stat(_ value: NSTextField, _ caption: NSTextField) -> Surface {
            value.font = serifFont(28)
            let c = Surface(fill: Theme.card, stroke: Theme.line, radius: 16)
            pin(vstack([value, caption], spacing: 2), in: c, top: 16, leading: 20, trailing: 20, bottom: 16)
            return c
        }
        func cap(_ s: String) -> NSTextField { makeLabel(s, size: 12, color: .secondaryLabelColor) }
        let stats = NSStackView(views: [stat(statWords, cap("Words spoken")), stat(statSpeak, cap("Speaking WPM")),
                                        stat(statType, statTypeCap), stat(statSaved, cap("Time saved"))])
        stats.distribution = .fillEqually; stats.spacing = 12

        // ---- time saved chart + money saved
        let chartHead = NSStackView(views: [makeLabel("Time saved", size: 15, weight: .semibold), chartTotal])
        chartHead.distribution = .fill; chartHead.alignment = .firstBaseline
        chartTotal.alignment = .right
        chartTotal.setContentHuggingPriority(.init(200), for: .horizontal)
        let chartCard = card([chartHead, chart], spacing: 12)

        planField.font = .systemFont(ofSize: 12)
        planField.stringValue = String(format: "%g", Stats.planPriceZAR)
        planField.delegate = self
        planField.bezelStyle = .roundedBezel; planField.focusRingType = .none
        planField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        moneyValue.font = serifFont(34); moneyValue.textColor = Theme.purple
        let priceRow = NSStackView(views: [makeLabel("Compared with a subscription at R/month", size: 12, color: .secondaryLabelColor), planField])
        priceRow.spacing = 8; priceRow.alignment = .centerY
        let moneyCard = card([makeLabel("Money saved", size: 15, weight: .semibold), moneyValue, moneyNote, priceRow], spacing: 8)
        let mid = NSStackView(views: [chartCard, moneyCard]); mid.spacing = 12; mid.alignment = .top
        chartCard.widthAnchor.constraint(equalTo: moneyCard.widthAnchor, multiplier: 1.6).isActive = true
        chartCard.heightAnchor.constraint(equalTo: moneyCard.heightAnchor).isActive = true

        // ---- how to dictate + try it
        let keycap = Surface(fill: Theme.card, stroke: Theme.line, radius: 9)
        let fn = makeLabel("fn", size: 15, weight: .semibold, color: Theme.purple)
        keycap.addSubview(fn); fn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([keycap.widthAnchor.constraint(equalToConstant: 48), keycap.heightAnchor.constraint(equalToConstant: 40),
                                     fn.centerXAnchor.constraint(equalTo: keycap.centerXAnchor), fn.centerYAnchor.constraint(equalTo: keycap.centerYAnchor)])
        let big = makeLabel("Hold fn to talk", size: 15, weight: .semibold)
        let small = makeLabel("Release to paste at your cursor. Double-tap fn for hands-free, then tap once more to stop. Right Option works too: hold it to talk, or tap it once to open the mic hands-free and tap again to stop.",
                              size: 12, color: .secondaryLabelColor, wrap: true)
        let text = NSStackView(views: [big, small]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 3
        let hero = Surface(fill: Theme.tint, radius: 16)
        let heroRow = NSStackView(views: [keycap, text]); heroRow.spacing = 16; heroRow.alignment = .centerY
        pin(heroRow, in: hero, top: 16, leading: 18, trailing: 18, bottom: 16)

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
        tryScroll.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let tryBox = Surface(fill: Theme.field, stroke: Theme.line, radius: 10)
        pin(tryScroll, in: tryBox, top: 2, leading: 2, trailing: 2, bottom: 2)

        let talk = HoldButton(title: "Hold to talk")
        talk.onDown = { [weak self] in self?.app.beginManual() }
        talk.onUp = { [weak self] in self?.app.finishManual() }
        let copy = PillButton(title: "Copy last", primary: false)
        copy.target = self; copy.action = #selector(copyLast)
        let buttons = NSStackView(views: [talk, copy]); buttons.spacing = 8
        let tryRow = NSStackView(views: [makeLabel("Try it here without leaving MyType.", size: 12, color: .secondaryLabelColor), buttons])
        tryRow.alignment = .centerY
        let tryCard = card([tryBox, tryRow], spacing: 10)

        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return page([pageHeader(first.isEmpty ? "Welcome back" : "Welcome back, ", "Speak anywhere. Your words appear at the cursor.", grey: first), setupBanner, costSummary(homeTiles), stats, mid, typeCard, hero, tryCard])
    }

    private func buildHistory() -> NSView {
        historyStack.orientation = .vertical; historyStack.alignment = .leading; historyStack.spacing = 8
        filterPills = ["All", "Today", "This week"].enumerated().map { i, t in
            let b = FilterPill(title: t); b.tag = i; b.isSelected = i == 0
            b.target = self; b.action = #selector(pickFilter(_:))
            return b
        }
        let tabs = NSStackView(views: filterPills); tabs.spacing = 8
        return page([pageHeader("History", "Your recent dictations. Copy the text, or the original transcript before cleanup."), tabs, vstack([historyStack], spacing: 0)])
    }

    // MARK: typing test

    private func loadPassage() {
        typeStart = nil; typeDone = false
        typeView.isEditable = true
        typeView.string = ""
        updateTyping()
    }
    @objc private func newPassage() {
        passageIndex = (passageIndex + 1) % MainWindow.passages.count
        loadPassage()
        window.makeFirstResponder(typeView)
    }
    func textDidChange(_ notification: Notification) {
        if (notification.object as? NSTextView) === typeView { updateTyping() }
    }

    private func updateTyping() {
        let target = Array(MainWindow.passages[passageIndex]), typed = Array(typeView.string)
        if typeStart == nil && !typed.isEmpty { typeStart = Date() }
        let out = NSMutableAttributedString()
        var correct = 0
        for (i, ch) in target.enumerated() {
            var attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.tertiaryLabelColor]
            if i < typed.count {
                if typed[i] == ch { correct += 1; attrs[.foregroundColor] = NSColor.labelColor }
                else { attrs[.foregroundColor] = NSColor.systemRed; attrs[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.15) }
            } else if i == typed.count { attrs[.foregroundColor] = NSColor.secondaryLabelColor }
            out.append(NSAttributedString(string: String(ch), attributes: attrs))
        }
        typePassage.attributedStringValue = out
        guard let start = typeStart else {
            typeLive.stringValue = "The timer starts on your first keystroke. Type the passage above."
            return
        }
        let elapsed = max(0.5, Date().timeIntervalSince(start))
        let wpm = Double(correct) / 5 / (elapsed / 60)
        let acc = typed.isEmpty ? 100 : Int((Double(correct) / Double(typed.count) * 100).rounded())
        if !typeDone && typed.count >= target.count {
            typeDone = true
            typeView.isEditable = false
            if acc >= 80 && elapsed > 3 {
                Stats.typingWPM = wpm
                if wpm > (Stats.typingBest ?? 0) { Stats.typingBest = wpm }
                reloadStats()
                typeLive.stringValue = String(format: "Done: %.0f WPM at %d%% accuracy. Saved as your typing speed.", wpm, acc)
            } else {
                typeLive.stringValue = "Done, but accuracy was \(acc)%. Try again for a fair result."
            }
            return
        }
        if !typeDone { typeLive.stringValue = String(format: "%.0f WPM · %d%% accuracy · %.0fs", wpm, acc, elapsed) }
    }

    private func buildDictionary() -> NSView {
        let addField = NSTextField()
        addField.placeholderString = "Add a word or name"
        addField.bezelStyle = .roundedBezel; addField.focusRingType = .none
        addField.target = self; addField.action = #selector(addWord(_:))
        addField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        newWordField = addField
        let add = PillButton(title: "New word")
        add.target = self; add.action = #selector(addWord(_:))
        let addRow = NSStackView(views: [addField, add]); addRow.spacing = 8; addRow.alignment = .centerY
        wordFlow.gap = 8
        let c = card([sectionTitle("Your words", symbol: "textformat.abc"), addRow, wordFlow,
                      makeLabel("Press Return to add a word. Paste several separated by commas.", size: 12, color: .secondaryLabelColor, wrap: true)], spacing: 14)
        reloadWords()

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
        let sc = card([sectionTitle("Snippets", symbol: "text.badge.plus"), sbox, snipHint], spacing: 12)
        return page([pageHeader("Dictionary", "Names, drugs and jargon MyType should always spell right."), c, sc])
    }

    private static let usagePeriods = ["Today", "This month", "All time"]
    private static let usageColumns = ["", "Dictations", "Audio", "Speech", "Cleanup tokens", "Cleanup", "List price", "You pay"]

    /// "This month" cost summary: list price, what you actually pay, and Deepgram credit left.
    private func costSummary(_ t: CostTiles) -> Surface {
        func tile(_ title: String, _ value: NSTextField, _ note: NSTextField, accent: Bool = false) -> Surface {
            let c = Surface(fill: accent ? Theme.purple.withAlphaComponent(0.12) : Theme.field, stroke: accent ? Theme.purple.withAlphaComponent(0.5) : Theme.line, radius: 12)
            pin(vstack([makeLabel(title, size: 12, weight: .medium, color: .secondaryLabelColor), value, note], spacing: 4), in: c, top: 14, leading: 16, trailing: 16, bottom: 14)
            return c
        }
        let cells = [tile("Would cost at list price", t.would, t.wouldNote),
                     tile("You actually pay", t.pay, t.payNote, accent: true),
                     tile("Deepgram credit left", t.credit, t.creditNote)]
        let tiles = NSStackView(views: cells)
        tiles.distribution = .fillEqually; tiles.spacing = 12; tiles.alignment = .top
        for c in cells.dropFirst() { c.heightAnchor.constraint(equalTo: cells[0].heightAnchor).isActive = true }
        let refresh = PillButton(title: "Refresh balance", primary: false)
        refresh.target = self; refresh.action = #selector(refreshBalance)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let refreshRow = NSStackView(views: [refresh, spacer]); refreshRow.spacing = 0
        return card([sectionTitle("This month", symbol: "calendar"), tiles, refreshRow], spacing: 14)
    }

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
        let summary = costSummary(usageTiles)
        let table = card([sectionTitle("Running cost", symbol: "chart.bar"), grid, creditLabel,
                          makeLabel("List price is what these dictations would cost at normal rates. You pay is what actually leaves your pocket: speech is covered by your Deepgram credit until it runs out, and cleanup is covered by the free tier while that switch is on. Estimates from the rates below, not an invoice.",
                                    size: 11, color: .secondaryLabelColor, wrap: true)])
        cleanupFreeSwitch.isOn = Usage.cleanupFree
        cleanupFreeSwitch.target = self; cleanupFreeSwitch.action = #selector(toggleCleanupFree)
        rateField.delegate = self
        let rates = card([
            sectionTitle("Rates and credits", symbol: "percent"),
            settingRow("Exchange rate, rand per US$", "Everything is shown in rand. Provider prices below are in US dollars. Fetched daily; type a number to fix your own.",
                       field(rateField, placeholder: "18", value: String(format: "%.2f", Currency.rate), width: 90)),
            settingRow("Deepgram credit (US$)", "Your sign-up credit. Speech costs you nothing until list-price spend passes this.",
                       field(creditField, placeholder: "200", value: String(Usage.deepgramCredit), width: 90)),
            settingRow("Cleanup is on a free tier", "Groq has a rate-limited free tier for now. Turn this off if you move to a paid plan.", cleanupFreeSwitch),
            settingRow("Speech, US$ per minute", "Deepgram Nova-3 streaming was about US$0.0077/min when I set this up.",
                       field(dgRateField, placeholder: "0.0077", value: String(Usage.deepgramPerMinute), width: 90)),
            settingRow("Cleanup input, US$ per 1M tokens", nil, field(inRateField, placeholder: "0.29", value: String(Usage.llmInPerMillion), width: 90)),
            settingRow("Cleanup output, US$ per 1M tokens", "Defaults are a rough guess for Groq's Qwen models. Check your provider's pricing page and edit.",
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
        func usd(_ v: Double) -> String { Currency.format(usd: v) }
        func k(_ n: Int) -> String { n >= 10_000 ? String(format: "%.1fk", Double(n) / 1000) : String(n) }
        for (i, s) in since.enumerated() {
            let t = Usage.totals(evs, since: s)
            let vals = ["\(t.dictations)", String(format: "%.1f min", t.audioSeconds / 60), usd(t.speechCost),
                        "\(k(t.promptTokens)) in / \(k(t.completionTokens)) out", usd(t.cleanupCost), usd(t.total), usd(t.youPay)]
            for (c, v) in vals.enumerated() { usageCells[i][c].stringValue = v }
        }
        let st = Usage.creditStatus(evs), credit = Usage.deepgramCredit
        let month = Usage.totals(evs, since: since[1])
        for t in [usageTiles, homeTiles] {
            t.would.stringValue = usd(month.total)
            t.wouldNote.stringValue = "Speech \(usd(month.speechCost)) + cleanup \(usd(month.cleanupCost)). What this would cost with no credit and no free tier."
            t.pay.stringValue = usd(month.youPay)
            t.payNote.stringValue = month.youPay < 0.005 ? "Nothing. Your Deepgram credit and the free cleanup tier cover it all."
                : "Speech beyond your credit\(Usage.cleanupFree ? "" : " plus cleanup")."
            if let live = DeepgramBalance.amount, DeepgramBalance.note.isEmpty {
                t.credit.stringValue = usd(live)
                let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
                t.creditNote.stringValue = "Live from Deepgram (\(f.string(from: DeepgramBalance.updated ?? Date()))). \(usd(max(0, credit - live))) of \(usd(credit)) used so far."
            } else {
                t.credit.stringValue = usd(max(0, credit - st.used))
                t.creditNote.stringValue = DeepgramBalance.note.isEmpty ? "Estimated from this Mac's usage." : "Estimated from this Mac's usage. " + DeepgramBalance.note
            }
        }
        var line = "Deepgram credit: \(usd(max(0, credit - st.used))) left of \(usd(credit)). At your current pace the true cost is about \(usd(st.monthly)) a month"
        if st.monthly > 0 { line += String(format: ", so the credit lasts roughly %.0f months.", max(0, credit - st.used) / max(0.0001, evs.isEmpty ? 1 : st.monthly)) } else { line += "." }
        creditLabel.stringValue = line
    }

    private func buildSettings() -> NSView {
        for (sw, sel) in [(aiSwitch, #selector(toggleAI)), (langSwitch, #selector(toggleLang)), (loginSwitch, #selector(toggleLogin)), (chipSwitch, #selector(toggleChip))] {
            sw.target = self; sw.action = sel
        }
        presetPopup.addItems(withTitles: ["Custom"] + MainWindow.presets.map { $0.0 })
        presetPopup.target = self; presetPopup.action = #selector(pickPreset)
        presetPopup.widthAnchor.constraint(equalToConstant: 270).isActive = true
        if let i = MainWindow.presets.firstIndex(where: { $0.1 == Cloud.llmBaseURL }) { presetPopup.selectItem(at: i + 1) }

        let speech = card(
            [sectionTitle("Cloud (optional)", symbol: "cloud")] + spaced([
            settingRow("Deepgram key", "Streams speech to Deepgram: faster and more accurate.",
                       field(dgField, placeholder: "Paste key", value: Cloud.deepgramKey)),
            settingRow("Cleanup provider", nil, presetPopup),
            settingRow("Cleanup key", "Used to fix punctuation and edits.", field(llmKeyField, placeholder: "Paste API key", value: Cloud.llmKey)),
            settingRow("Base URL", nil, field(llmURLField, placeholder: "https://…", value: Cloud.llmBaseURL)),
            settingRow("Model", nil, field(llmModelField, placeholder: "model name", value: Cloud.llmModel)),
            ]) + [makeLabel("With keys set, audio and text leave your Mac. Leave blank to stay fully on-device. Keys are stored on this Mac only.",
                      size: 11, color: .secondaryLabelColor, wrap: true)],
        spacing: 16)
        stylePopup.addItems(withTitles: WritingStyle.allCases.map(\.title))
        stylePopup.selectItem(at: WritingStyle.allCases.firstIndex(of: WritingStyle.current) ?? 0)
        stylePopup.target = self; stylePopup.action = #selector(pickStyle)
        stylePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let general = card([sectionTitle("General", symbol: "slider.horizontal.3")] + spaced([
            settingRow("Writing style", WritingStyle.allCases.map { "\($0.title): \($0.detail)" }.joined(separator: "\n"), stylePopup),
            settingRow("AI cleanup", "Smarter edits. Uses your cloud key if set, otherwise a local model (~2 GB RAM).", aiSwitch),
            settingRow("Auto-detect language", "Restart MyType to apply.", langSwitch),
            settingRow("Copy chip when nothing is focused", "If no text box is focused when you start talking, or you switch apps mid-dictation, the text is kept on the clipboard and a small chip lets you copy it again. Nothing appears when it types into a text box.", chipSwitch),
            settingRow("Launch at login", nil, loginSwitch),
        ]), spacing: 16)
        let setupBtn = PillButton(title: "Open setup guide", primary: false)
        setupBtn.target = self; setupBtn.action = #selector(runSetup)
        let perms = card([sectionTitle("Permissions", symbol: "lock.shield")] + spaced([micRow.view, axRow.view, inputRow.view, keyRow.view]) + [setupBtn], spacing: 14)
        return page([pageHeader("Settings", "Speech, cleanup and permissions."), speech, general, perms])
    }

    // MARK: actions

    /// Re-reads stored keys into the Settings fields (the setup guide changes them behind our back).
    func reloadKeyFields() {
        dgField.stringValue = Cloud.deepgramKey; llmKeyField.stringValue = Cloud.llmKey
        llmURLField.stringValue = Cloud.llmBaseURL; llmModelField.stringValue = Cloud.llmModel
        presetPopup.selectItem(at: (MainWindow.presets.firstIndex(where: { $0.1 == Cloud.llmBaseURL }) ?? -1) + 1)
        refresh()
    }

    @objc private func pickStyle() {
        WritingStyle.current = WritingStyle.allCases[max(0, stylePopup.indexOfSelectedItem)]
    }

    @objc private func runSetup() { onSetup?() }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func insertTry(_ text: String) {
        select(0)
        window.makeFirstResponder(tryView)
        tryView.insertText(text + " ", replacementRange: tryView.selectedRange())
    }

    @objc private func pickFilter(_ b: FilterPill) {
        historyFilter = b.tag
        for (i, p) in filterPills.enumerated() { p.isSelected = i == b.tag }
        reloadHistory()
    }

    func reloadHistory() {
        reloadStats()
        historyStack.arrangedSubviews.forEach { historyStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let cutoff: Date? = historyFilter == 1 ? Calendar.current.startOfDay(for: Date())
            : historyFilter == 2 ? Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) : nil
        shown = Array(History.items.filter { cutoff == nil || $0.date >= cutoff! }.prefix(30))
        if shown.isEmpty {
            historyStack.addArrangedSubview(makeLabel(historyFilter == 0 ? "Your dictations will show up here." : "Nothing in this period yet.", size: 13, color: .secondaryLabelColor))
            return
        }
        let cal = Calendar.current
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        let dayFmt = DateFormatter(); dayFmt.dateFormat = "EEEE, d MMMM"
        var i = 0
        while i < shown.count {
            let day = cal.startOfDay(for: shown[i].date)
            var j = i
            while j < shown.count, cal.startOfDay(for: shown[j].date) == day { j += 1 }
            let name = cal.isDateInToday(day) ? "Today" : cal.isDateInYesterday(day) ? "Yesterday" : dayFmt.string(from: day)
            let head = makeLabel(name, size: 12, weight: .medium, color: .secondaryLabelColor)
            var rows: [NSView] = []
            for k in i..<j {
                if k > i { rows.append(divider()) }
                rows.append(historyRow(shown[k], index: k, time: clock.string(from: shown[k].date)))
            }
            let group = Surface(fill: Theme.card, stroke: Theme.line, radius: 16)
            pin(vstack(rows, spacing: 0), in: group, top: 2, leading: 0, trailing: 0, bottom: 2)
            historyStack.addArrangedSubview(head)
            historyStack.setCustomSpacing(6, after: head)
            historyStack.addArrangedSubview(group)
            historyStack.setCustomSpacing(20, after: group)
            group.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
            i = j
        }
    }

    private func historyRow(_ e: HistoryEntry, index: Int, time: String) -> NSView {
        let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
        let when = makeLabel(time, size: 12, color: .tertiaryLabelColor)
        when.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let body = makeLabel(e.text, size: 13, wrap: true)
        body.isSelectable = true
        body.setContentCompressionResistancePriority(.init(250), for: .horizontal)

        func icon(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton()
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            b.isBordered = false; b.contentTintColor = .secondaryLabelColor; b.toolTip = tip
            b.tag = index; b.target = self; b.action = action
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true; b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return b
        }
        var actions = [icon("doc.on.doc", "Copy", #selector(copyEntry(_:)))]
        if let r = e.raw, !r.isEmpty, r != e.text { actions.insert(icon("arrow.uturn.backward", "Copy original transcript", #selector(copyRaw(_:))), at: 0) }
        let tools = NSStackView(views: actions); tools.spacing = 0
        tools.translatesAutoresizingMaskIntoConstraints = false
        for v in [when, body, tools] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(v) }
        NSLayoutConstraint.activate([
            when.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 18), when.topAnchor.constraint(equalTo: row.topAnchor, constant: 13),
            when.widthAnchor.constraint(equalToConstant: 40),
            body.leadingAnchor.constraint(equalTo: when.trailingAnchor, constant: 12),
            body.topAnchor.constraint(equalTo: row.topAnchor, constant: 12), body.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            body.trailingAnchor.constraint(equalTo: tools.leadingAnchor, constant: -12),
            tools.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12), tools.topAnchor.constraint(equalTo: row.topAnchor, constant: 9),
        ])
        return row
    }

    private func copyToPasteboard(_ s: String, from sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        let old = sender.image, tint = sender.contentTintColor
        sender.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        sender.contentTintColor = Theme.purple
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { sender.image = old; sender.contentTintColor = tint }
    }
    @objc private func copyEntry(_ b: NSButton) { if shown.indices.contains(b.tag) { copyToPasteboard(shown[b.tag].text, from: b) } }
    @objc private func copyRaw(_ b: NSButton) { if shown.indices.contains(b.tag), let r = shown[b.tag].raw { copyToPasteboard(r, from: b) } }

    private func reloadStats() {
        let nf = NumberFormatter(); nf.numberStyle = .decimal
        statWords.stringValue = nf.string(from: NSNumber(value: Stats.totalWords)) ?? "0"
        statSpeak.stringValue = Stats.speakingWPM.map { String(Int($0.rounded())) } ?? "–"
        statType.stringValue = Stats.typingWPM.map { String(Int($0.rounded())) } ?? "–"
        statTypeCap.stringValue = Stats.typingWPM == nil ? "Typing WPM (take the test)" : "Typing WPM"
        statSaved.stringValue = Stats.duration(Stats.totalSavedSeconds)
        typeBest.stringValue = Stats.typingBest.map { "Best: \(Int($0.rounded())) WPM" } ?? ""

        let daily = Stats.dailySaved(14)
        let f = DateFormatter(); f.dateFormat = "d MMM"
        chart.values = daily.map { (f.string(from: $0.date), $0.minutes) }
        let week = daily.suffix(7).reduce(0) { $0 + $1.minutes }
        chartTotal.stringValue = "\(Stats.duration(week * 60)) this week · streak \(Stats.streak()) day\(Stats.streak() == 1 ? "" : "s")"

        func rand(_ v: Double) -> String { Currency.format(rand: v) }
        moneyValue.stringValue = rand(Stats.moneySaved)
        let m = Stats.monthsUsed
        let listPrice = Currency.zar(Usage.totals(Usage.events(), since: nil).total)
        moneyNote.stringValue = "A subscription would have cost \(rand(Stats.subscriptionCost)) over \(m) month\(m == 1 ? "" : "s"). MyType has cost you \(rand(Stats.myTypeCost)) (\(rand(listPrice)) at list price)."
    }

    func refresh() {
        if typeStart != nil && !typeDone { updateTyping() }
        if selectedPage == 0 || selectedPage == 1 { reloadUsage() }
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
        if chipSwitch.isOn != Recall.enabled { chipSwitch.isOn = Recall.enabled }
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
        if let v = Double(rateField.stringValue.replacingOccurrences(of: ",", with: ".")), v > 1, abs(v - Currency.rate) > 0.0001 {
            Currency.rate = v; Currency.manual = true; reloadStats()
        }
        if let v = Double(planField.stringValue), v >= 0 { Stats.planPriceZAR = v; reloadStats() }
        app.refreshAI()
        refresh()
        if selectedPage == 1 { reloadUsage() }
    }
    func textDidEndEditing(_ notification: Notification) { saveDict() }

    @objc private func openSettings() { select(4) }
    @objc private func pickPreset() {
        let i = presetPopup.indexOfSelectedItem - 1
        guard i >= 0 else { return }
        llmURLField.stringValue = MainWindow.presets[i].1
        llmModelField.stringValue = MainWindow.presets[i].2
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification))
    }
    @objc private func saveDict() { Config.snippets = snipView.string }

    private func reloadWords() {
        words = Config.dictionary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        wordFlow.setItems(words.isEmpty ? [makeLabel("No words yet. Add names or terms MyType keeps mishearing.", size: 12, color: .tertiaryLabelColor)]
                                        : words.enumerated().map { chip($0.element, index: $0.offset) })
    }

    private func chip(_ word: String, index: Int) -> NSView {
        let c = Surface(fill: Theme.field, stroke: Theme.line, radius: 15)
        let x = NSButton()
        x.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")?.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        x.isBordered = false; x.contentTintColor = .tertiaryLabelColor; x.tag = index
        x.target = self; x.action = #selector(removeWord(_:))
        x.translatesAutoresizingMaskIntoConstraints = false
        x.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let row = NSStackView(views: [makeLabel(word, size: 13), x]); row.spacing = 4; row.alignment = .centerY
        pin(row, in: c, top: 6, leading: 13, trailing: 8, bottom: 6)
        return c
    }

    @objc private func addWord(_ sender: Any?) {
        guard let f = newWordField else { return }
        let new = f.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !new.isEmpty else { return }
        for w in new where !words.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { words.append(w) }
        Config.dictionary = words.joined(separator: ", ")
        f.stringValue = ""
        reloadWords()
    }

    @objc private func removeWord(_ b: NSButton) {
        guard words.indices.contains(b.tag) else { return }
        words.remove(at: b.tag)
        Config.dictionary = words.joined(separator: ", ")
        reloadWords()
    }
    @objc private func toggleCleanupFree() { Usage.cleanupFree = cleanupFreeSwitch.isOn; reloadUsage() }
    @objc private func toggleAI() { app.aiEnabled = aiSwitch.isOn }
    @objc private func toggleChip() { Recall.enabled = chipSwitch.isOn }
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
