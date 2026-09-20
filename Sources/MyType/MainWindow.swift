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
    t.font = wrap ? .systemFont(ofSize: size, weight: weight) : uiFont(size, weight)
    t.textColor = color
    return t
}

/// The Usage page is mostly numbers and short notes, so its wrapped description text is monospaced too.
func monoizeText(in view: NSView) {
    if let t = view as? NSTextField, !t.isEditable, let f = t.font, !f.isFixedPitch {
        t.font = uiFont(f.pointSize)
    }
    view.subviews.forEach(monoizeText)
}

/// Centre a label's text (labels inside a `vstack` are as wide as the stack, so this centres them).
@discardableResult func centered(_ t: NSTextField) -> NSTextField { t.alignment = .center; return t }

/// Interface text (titles, labels, buttons, numbers) is monospaced, like the input fields; paragraphs stay in the system face.
func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

/// Headlines and big numbers.
func serifFont(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
    uiFont(size, weight)
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


/// Text fields that tell their InputBox when they gain or lose focus.
class InputField: NSTextField {
    var onFocus: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); if ok { onFocus?(true) }; return ok }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); onFocus?(false) }
}
final class SecureInputField: NSSecureTextField {
    var onFocus: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool { let ok = super.becomeFirstResponder(); if ok { onFocus?(true) }; return ok }
    override func textDidEndEditing(_ notification: Notification) { super.textDidEndEditing(notification); onFocus?(false) }
}

/// Flat, rounded text input in a fixed monospaced face. The whole box is the click target: it lifts and shows a text cursor on
/// hover, and takes a purple ring while you type.
final class InputBox: NSView {
    let field: NSTextField
    private var hover = false { didSet { needsDisplay = true } }
    private var focused = false { didSet { needsDisplay = true } }

    init(_ f: NSTextField, width: CGFloat, align: NSTextAlignment = .left) {
        field = f
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        f.isBordered = false; f.drawsBackground = false; f.focusRingType = .none
        f.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        f.alignment = align
        f.usesSingleLineMode = true
        f.cell?.isScrollable = true; f.lineBreakMode = .byClipping
        f.translatesAutoresizingMaskIntoConstraints = false
        addSubview(f)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: 34),
            f.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), f.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            f.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let focus: (Bool) -> Void = { [weak self] on in self?.focused = on }
        (f as? InputField)?.onFocus = focus
        (f as? SecureInputField)?.onFocus = focus
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(field) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .iBeam) }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (hover || focused ? Theme.purple.withAlphaComponent(0.07).blended(withFraction: 0.5, of: Theme.field) ?? Theme.field : Theme.field).cgColor
            layer?.borderColor = (focused ? Theme.purple : hover ? Theme.purple.withAlphaComponent(0.45) : Theme.line).cgColor
            layer?.borderWidth = focused ? 1.5 : 1
        }
    }
}

final class FlippedClip: NSClipView { override var isFlipped: Bool { true } }

/// Flat rounded button. Primary = purple fill.
class PillButton: NSButton {
    private let primary: Bool
    private var caption: String
    /// Retitling must keep the styled (contrast-correct) title, not fall back to the plain label colour.
    override var title: String {
        get { caption }
        set { caption = newValue; restyle() }
    }
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
    private var hovering = false { didSet { restyle() } }
    override func viewDidChangeEffectiveAppearance() { restyle() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override var intrinsicContentSize: NSSize { NSSize(width: super.intrinsicContentSize.width + 26, height: 32) }
    private func restyle() {
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let color: NSColor = primary ? .white : .labelColor
        attributedTitle = NSAttributedString(string: caption, attributes: [
            .foregroundColor: color, .font: uiFont(12, .medium), .paragraphStyle: p])
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base: NSColor = primary ? Theme.purple : Theme.field
            var fill = base
            if hovering && !isHighlighted { fill = primary ? (base.blended(withFraction: 0.12, of: .white) ?? base) : (base.blended(withFraction: 0.14, of: Theme.purple) ?? base) }
            layer?.backgroundColor = (isHighlighted ? base.blended(withFraction: 0.25, of: .black) ?? base : fill).cgColor
            layer?.borderColor = (hovering && !primary ? Theme.purple : Theme.line).cgColor
            layer?.borderWidth = primary ? 0 : (hovering ? 1.5 : 1)
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

/// Slim pill toggle: purple when on, an outlined field when off, with a knob that slides.
final class PurpleSwitch: NSControl {
    var isOn = false { didSet { if oldValue != isOn { update(animated: true) } } }
    private let track = CALayer(), knob = CALayer(), label = CATextLayer()
    private var hover = false { didSet { update(animated: true) } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(track); layer?.addSublayer(label); layer?.addSublayer(knob)
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold); label.fontSize = 10
        label.alignmentMode = .center; label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        knob.shadowColor = NSColor.black.cgColor; knob.shadowOpacity = 0.28; knob.shadowRadius = 2; knob.shadowOffset = CGSize(width: 0, height: -1)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        update(animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 64, height: 28) }
    override func layout() { super.layout(); update(animated: false) }
    override func viewDidChangeEffectiveAppearance() { update(animated: false) }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) { isOn.toggle(); sendAction(action, to: target) }

    private func update(animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut))
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        let d = bounds.height - 6
        knob.frame = NSRect(x: isOn ? bounds.width - d - 3 : 3, y: 3, width: d, height: d)
        knob.cornerRadius = d / 2
        let textW = bounds.width - d - 12
        label.frame = NSRect(x: isOn ? 6 : d + 6, y: (bounds.height - 13) / 2, width: textW, height: 13)
        label.string = isOn ? "ON" : "OFF"
        effectiveAppearance.performAsCurrentDrawingAppearance {
            if isOn {
                track.backgroundColor = (hover ? Theme.purple.blended(withFraction: 0.15, of: .white) ?? Theme.purple : Theme.purple).cgColor
                track.borderColor = NSColor.clear.cgColor
                knob.backgroundColor = NSColor.white.cgColor
                label.foregroundColor = NSColor.white.cgColor
            } else {
                track.backgroundColor = Theme.field.cgColor
                track.borderColor = (hover ? Theme.purple.withAlphaComponent(0.55) : Theme.line).cgColor
                knob.backgroundColor = (hover ? NSColor.labelColor.withAlphaComponent(0.75) : NSColor.secondaryLabelColor).cgColor
                label.foregroundColor = NSColor.secondaryLabelColor.cgColor
            }
            track.borderWidth = 1
        }
        CATransaction.commit()
    }
}

/// Option list shown by PillPopup: mono text, purple highlight instead of the system blue.
final class PillList: NSView {
    private var rows: [PillRow] = []
    init(titles: [String], selected: Int, width: CGFloat, pick: @escaping (Int) -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: CGFloat(titles.count) * 32 + 12))
        for (i, t) in titles.enumerated() {
            let r = PillRow(title: t, selected: i == selected) { pick(i) }
            r.frame = NSRect(x: 6, y: bounds.height - 6 - CGFloat(i + 1) * 32, width: bounds.width - 12, height: 32)
            r.autoresizingMask = [.width]
            addSubview(r); rows.append(r)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class PillRow: NSView {
    private let title: String, selected: Bool, onPick: () -> Void
    private var hover = false { didSet { needsDisplay = true } }
    init(title: String, selected: Bool, onPick: @escaping () -> Void) {
        self.title = title; self.selected = selected; self.onPick = onPick
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseDown(with e: NSEvent) { onPick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func draw(_ dirtyRect: NSRect) {
        if hover || selected {
            Theme.purple.withAlphaComponent(hover ? 0.22 : 0.10).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor]
        let h = title.size(withAttributes: a).height
        title.draw(at: CGPoint(x: 10, y: bounds.midY - h / 2), withAttributes: a)
        if selected, let img = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .bold).applying(.init(paletteColors: [Theme.purple]))) {
            img.draw(in: NSRect(x: bounds.maxX - 12 - img.size.width, y: bounds.midY - img.size.height / 2, width: img.size.width, height: img.size.height))
        }
    }
}

/// Dropdown drawn to match the input boxes: flat rounded field, purple chevron, tint on hover. The menu itself is still the system one.
final class PillPopup: NSPopUpButton {
    private var hover = false { didSet { needsDisplay = true } }

    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        isBordered = false
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        translatesAutoresizingMaskIntoConstraints = false
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 34) }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private var popover: NSPopover?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        if let p = popover, p.isShown { p.close(); return }
        let list = PillList(titles: itemTitles, selected: indexOfSelectedItem, width: bounds.width) { [weak self] i in
            guard let self else { return }
            self.popover?.close()
            self.selectItem(at: i)
            self.sendAction(self.action, to: self.target)
        }
        let pop = NSPopover()
        pop.behavior = .transient; pop.animates = false
        pop.contentViewController = { let c = NSViewController(); c.view = list; return c }()
        pop.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        popover = pop
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        (hover ? Theme.purple.withAlphaComponent(0.07).blended(withFraction: 0.5, of: Theme.field) ?? Theme.field : Theme.field).setFill()
        path.fill()
        (hover ? Theme.purple.withAlphaComponent(0.45) : Theme.line).setStroke()
        path.lineWidth = 1; path.stroke()

        let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold).applying(.init(paletteColors: [Theme.purple]))
        var textRight = bounds.maxX - 12
        if let img = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let s = img.size
            img.draw(in: NSRect(x: bounds.maxX - 12 - s.width, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
            textRight -= s.width + 8
        }
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor, .paragraphStyle: p]
        let t = titleOfSelectedItem ?? ""
        let h = t.size(withAttributes: a).height
        t.draw(in: NSRect(x: 12, y: bounds.midY - h / 2, width: max(0, textRight - 12), height: h), withAttributes: a)
    }
}

final class NavButton: NSButton {
    private let caption: String
    var isSelected = false { didSet { restyle() } }
    init(title: String, symbol: String) {
        caption = title
        super.init(frame: .zero)
        // Symbols differ in width; centring each in a fixed slot keeps the labels on one left edge.
        if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular)) {
            let slot = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { r in
                sym.draw(in: NSRect(x: (r.width - sym.size.width) / 2, y: (r.height - sym.size.height) / 2,
                                    width: sym.size.width, height: sym.size.height)); return true
            }
            slot.isTemplate = true
            image = slot
        }
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
            .foregroundColor: NSColor.labelColor, .font: uiFont(12.5, isSelected ? .semibold : .medium)])
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
            .font: uiFont(12, .medium), .paragraphStyle: p])
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
        var row: [NSView] = []
        func flush() {
            let used = row.last?.frame.maxX ?? 0
            let shift = max(0, (bounds.width - used) / 2).rounded()
            for v in row { v.frame.origin.x += shift }
            row = []
        }
        for v in subviews {
            let sz = v.fittingSize
            if x > 0 && x + sz.width > bounds.width { flush(); x = 0; y += rowH + gap; rowH = 0 }
            v.frame = NSRect(x: x, y: y, width: sz.width, height: sz.height)
            row.append(v)
            x += sz.width + gap; rowH = max(rowH, sz.height)
        }
        flush()
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
    private let planField = InputField()
    private let heroTitle = makeLabel("", size: 15, weight: .semibold), heroBody = makeLabel("", size: 12, color: .secondaryLabelColor, wrap: true)
    private let fnPopup = PillPopup(frame: .zero, pullsDown: false), optionPopup = PillPopup(frame: .zero, pullsDown: false)
    private let nameField = InputField()
    private var greetingTitle: NSTextField?
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
    private let aiSwitch = PurpleSwitch(frame: .zero), langSwitch = PurpleSwitch(frame: .zero), loginSwitch = PurpleSwitch(frame: .zero), chipSwitch = PurpleSwitch(frame: .zero)
    private let dgField = SecureInputField(), llmKeyField = SecureInputField()
    private let llmURLField = InputField(), llmModelField = InputField()
    private let presetPopup = PillPopup(frame: .zero, pullsDown: false)
    private let stylePopup = PillPopup(frame: .zero, pullsDown: false)
    private let appearancePopup = PillPopup(frame: .zero, pullsDown: false)
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
    private let dgRateField = InputField(), inRateField = InputField(), outRateField = InputField(), creditField = InputField()
    private let cleanupFreeSwitch = PurpleSwitch(frame: .zero)
    private let rateField = InputField()
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
        keyRow = CheckRow(title: "Fn key detected", detail: "Press Fn once. Set System Settings → Keyboard → “Press fn key to” → Do Nothing.", action: nil)

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
        t.alignment = .center
        guard let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) else { return t }
        let iv = NSImageView(image: img); iv.contentTintColor = Theme.purple
        let r = NSStackView(); r.spacing = 7; r.alignment = .centerY
        r.setViews([iv, t], in: .center)
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
        r.distribution = .fill
        left.setContentHuggingPriority(.init(1), for: .horizontal)
        return r
    }

    private func field(_ f: NSTextField, placeholder: String, value: String, width: CGFloat = 270) -> NSView {
        f.stringValue = value; f.placeholderString = placeholder; f.delegate = self
        return InputBox(f, width: width, align: width <= 100 ? .center : .left)
    }

    private func page(_ views: [NSView]) -> NSScrollView {
        let st = vstack(views, spacing: 16)
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        pin(st, in: doc, top: 22, leading: 40, trailing: 40, bottom: 40)
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
            let a = NSMutableAttributedString(string: title, attributes: [.font: serifFont(36, weight: .semibold), .foregroundColor: NSColor.labelColor, .kern: -1.6])
            if !grey.isEmpty { a.append(NSAttributedString(string: grey, attributes: [.font: serifFont(36, weight: .semibold), .foregroundColor: Theme.purple, .kern: -1.6])) }
            return a
        }())
        t.alignment = .center
        let accent = Surface(fill: Theme.purple, radius: 2)
        accent.heightAnchor.constraint(equalToConstant: 4).isActive = true
        let subtitle = makeLabel(sub, size: 14, color: .secondaryLabelColor, wrap: true)
        subtitle.alignment = .center
        let h = NSStackView(views: [t, accent, subtitle])
        h.orientation = .vertical; h.alignment = .centerX; h.spacing = 12
        h.setCustomSpacing(10, after: t)
        h.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        subtitle.widthAnchor.constraint(equalTo: h.widthAnchor).isActive = true
        accent.widthAnchor.constraint(equalTo: t.widthAnchor).isActive = true
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

        let logo = NSImageView(image: NSApp.applicationIconImage)
        logo.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([logo.widthAnchor.constraint(equalToConstant: 34), logo.heightAnchor.constraint(equalToConstant: 34)])
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
        let credit = NSStackView(views: [makeLabel("Created by Jay Sinha", size: 10, color: .tertiaryLabelColor)])
        credit.alignment = .leading
        credit.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        let footer = vstack([nav[4], divider(), status, credit], spacing: 10)
        footer.setCustomSpacing(14, after: status)

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
        centered(typeTitle); centered(typeBest); centered(typePassage); centered(typeLive)
        let againRow = NSStackView(); againRow.setViews([again], in: .center)
        let typeCard = card([typeTitle, typeBest, typePassage, typeBox, typeLive, againRow], spacing: 12)
        loadPassage()

        // ---- stats
        func stat(_ value: NSTextField, _ caption: NSTextField) -> Surface {
            value.font = serifFont(28); centered(value); centered(caption)
            let c = Surface(fill: Theme.card, stroke: Theme.line, radius: 16)
            pin(vstack([value, caption], spacing: 2), in: c, top: 16, leading: 20, trailing: 20, bottom: 16)
            return c
        }
        func cap(_ s: String) -> NSTextField { makeLabel(s, size: 12, color: .secondaryLabelColor) }
        let stats = NSStackView(views: [stat(statWords, cap("Words spoken")), stat(statSpeak, cap("Speaking WPM")),
                                        stat(statType, statTypeCap), stat(statSaved, cap("Time saved"))])
        stats.distribution = .fillEqually; stats.spacing = 12

        // ---- time saved chart + money saved
        centered(chartTotal)
        let chartCard = card([centered(makeLabel("Time saved", size: 15, weight: .semibold)), chartTotal, chart], spacing: 8)

        planField.stringValue = String(format: "%g", Stats.planPriceUSD)
        planField.delegate = self
        let planBox = InputBox(planField, width: 72, align: .center)
        moneyValue.font = serifFont(34); moneyValue.textColor = Theme.purple
        let priceRow = NSStackView(); priceRow.spacing = 8; priceRow.alignment = .centerY
        priceRow.setViews([makeLabel("Compared with a subscription at US$ per month", size: 12, color: .secondaryLabelColor), planBox], in: .center)
        centered(moneyValue); centered(moneyNote)
        let moneyCard = card([centered(makeLabel("Money saved", size: 15, weight: .semibold)), moneyValue, moneyNote, priceRow], spacing: 8)
        let mid = NSStackView(views: [chartCard, moneyCard]); mid.spacing = 12; mid.alignment = .top; mid.distribution = .fill
        chartCard.widthAnchor.constraint(equalTo: moneyCard.widthAnchor, multiplier: 1.6).isActive = true
        chartCard.heightAnchor.constraint(equalTo: moneyCard.heightAnchor).isActive = true

        // ---- how to dictate + try it
        // Our own generic key, not tied to any one keyboard: a centred "fn" in the app's mono face.
        let keycap = Surface(fill: Theme.card, stroke: Theme.line, radius: 9)
        let fn = makeLabel("fn", size: 15, weight: .semibold)
        fn.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold)
        keycap.addSubview(fn); fn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([keycap.widthAnchor.constraint(equalToConstant: 56), keycap.heightAnchor.constraint(equalToConstant: 46),
                                     fn.centerXAnchor.constraint(equalTo: keycap.centerXAnchor), fn.centerYAnchor.constraint(equalTo: keycap.centerYAnchor)])
        let big = heroTitle, small = heroBody
        updateHero()
        centered(big); centered(small)
        let hero = Surface(fill: Theme.tint, radius: 16)
        let heroRow = NSStackView(views: [keycap, big, small]); heroRow.orientation = .vertical; heroRow.alignment = .centerX; heroRow.spacing = 8
        heroRow.setCustomSpacing(12, after: keycap)
        small.widthAnchor.constraint(equalTo: heroRow.widthAnchor).isActive = true
        pin(heroRow, in: hero, top: 18, leading: 24, trailing: 24, bottom: 18)

        let goSettings = PillButton(title: "Open Settings", primary: false)
        goSettings.target = self; goSettings.action = #selector(openSettings)
        let warn = makeLabel("Finish setup: MyType is missing a permission.", size: 13, weight: .medium)
        let bannerRow = NSStackView(); bannerRow.spacing = 12; bannerRow.alignment = .centerY
        bannerRow.setViews([warn, goSettings], in: .center)
        setupBanner = Surface(fill: NSColor.systemOrange.withAlphaComponent(0.13), stroke: NSColor.systemOrange.withAlphaComponent(0.4), radius: 12)
        pin(bannerRow, in: setupBanner, top: 10, leading: 16, trailing: 16, bottom: 10)

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
        let buttons = NSStackView(); buttons.spacing = 8
        buttons.setViews([talk, copy], in: .center)
        let tryCard = card([centered(makeLabel("Try it here without leaving MyType.", size: 12, color: .secondaryLabelColor)), tryBox, buttons], spacing: 10)

        let first = Profile.name
        let header = pageHeader(first.isEmpty ? "Welcome back" : "Welcome back, ", "Speak anywhere. Your words appear at the cursor.", grey: first)
        greetingTitle = header.arrangedSubviews.first as? NSTextField
        return page([header, setupBanner, costSummary(homeTiles), stats, mid, typeCard, hero, tryCard])
    }

    private func buildHistory() -> NSView {
        historyStack.orientation = .vertical; historyStack.alignment = .leading; historyStack.spacing = 8
        filterPills = ["All", "Today", "This week"].enumerated().map { i, t in
            let b = FilterPill(title: t); b.tag = i; b.isSelected = i == 0
            b.target = self; b.action = #selector(pickFilter(_:))
            return b
        }
        let tabs = NSStackView(); tabs.spacing = 8
        tabs.setViews(filterPills, in: .center)
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
        let addField = InputField()
        addField.placeholderString = "Add a word or name"
        addField.target = self; addField.action = #selector(addWord(_:))
        let addBox = InputBox(addField, width: 260)
        newWordField = addField
        let add = PillButton(title: "New word")
        add.target = self; add.action = #selector(addWord(_:))
        let addRow = NSStackView(); addRow.spacing = 8; addRow.alignment = .centerY
        addRow.setViews([addBox, add], in: .center)
        wordFlow.gap = 8
        let c = card([sectionTitle("Your words", symbol: "textformat.abc"), addRow, wordFlow,
                      centered(makeLabel("Press Return to add a word. Paste several separated by commas.", size: 12, color: .secondaryLabelColor, wrap: true))], spacing: 14)
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
        let snipHint = centered(makeLabel("One per line, like:  my email = jay@example.com. Say the words on the left and the text on the right is typed instead.", size: 12, color: .secondaryLabelColor, wrap: true))
        let sc = card([sectionTitle("Snippets", symbol: "text.badge.plus"), sbox, snipHint], spacing: 12)
        return page([pageHeader("Dictionary", "Names, drugs and jargon MyType should always spell right."), c, sc])
    }

    private static let usagePeriods = ["Today", "This month", "All time"]
    private static let usageColumns = ["Time period", "Dictations", "Audio", "Speech", "Cleanup tokens", "Cleanup", "List price", "You pay"]

    /// "This month" cost summary: list price, what you actually pay, and Deepgram credit left.
    private func costSummary(_ t: CostTiles) -> Surface {
        func tile(_ title: String, _ value: NSTextField, _ note: NSTextField, accent: Bool = false) -> Surface {
            let c = Surface(fill: accent ? Theme.purple.withAlphaComponent(0.12) : Theme.field, stroke: accent ? Theme.purple.withAlphaComponent(0.5) : Theme.line, radius: 12)
            pin(vstack([centered(makeLabel(title, size: 12, weight: .medium, color: .secondaryLabelColor)), centered(value), centered(note)], spacing: 4), in: c, top: 14, leading: 16, trailing: 16, bottom: 14)
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
        let refreshRow = NSStackView(); refreshRow.setViews([refresh], in: .center)
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
        for r in rows { for case let l as NSTextField in r { l.alignment = .center } }
        grid.xPlacement = .center
        for r in rows { (r[0] as? NSTextField)?.alignment = .left }
        grid.column(at: 0).xPlacement = .leading
        let gridRow = NSStackView(); gridRow.setViews([grid], in: .center)
        let summary = costSummary(usageTiles)
        let table = card([sectionTitle("Running cost", symbol: "chart.bar"), gridRow, centered(creditLabel),
                          centered(makeLabel("List price is what these dictations would cost at normal rates. You pay is what actually leaves your pocket: speech is covered by your Deepgram credit until it runs out, and cleanup is covered by the free tier while that switch is on. Estimates from the rates below, not an invoice.",
                                    size: 11, color: .secondaryLabelColor, wrap: true))])
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
        let usagePage = page([pageHeader("Usage", "What your API keys are costing, tracked on this Mac."), summary, table, rates])
        monoizeText(in: usagePage)
        return usagePage
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
            ]) + [centered(makeLabel("With keys set, audio and text leave your Mac. Leave blank to stay fully on-device. Keys are stored on this Mac only.",
                      size: 11, color: .secondaryLabelColor, wrap: true))],
        spacing: 16)
        stylePopup.addItems(withTitles: WritingStyle.allCases.map(\.title))
        stylePopup.selectItem(at: WritingStyle.allCases.firstIndex(of: WritingStyle.current) ?? 0)
        stylePopup.target = self; stylePopup.action = #selector(pickStyle)
        appearancePopup.addItems(withTitles: AppearanceMode.allCases.map(\.title))
        appearancePopup.selectItem(at: AppearanceMode.current.rawValue)
        appearancePopup.target = self; appearancePopup.action = #selector(pickAppearance)
        appearancePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        stylePopup.widthAnchor.constraint(equalToConstant: 150).isActive = true
        let general = card([sectionTitle("General", symbol: "slider.horizontal.3")] + spaced([
            settingRow("Appearance", "Match my Mac follows your system setting, including automatic light and dark by time of day.", appearancePopup),
            settingRow("Your name", "What MyType calls you on the Home page. Any name or nickname works.", field(nameField, placeholder: Profile.systemFirstName, value: Profile.name, width: 200)),
            settingRow("Writing style", WritingStyle.allCases.map { "\($0.title): \($0.detail)" }.joined(separator: "\n"), stylePopup),
            settingRow("AI cleanup", "Smarter edits. Uses your cloud key if set, otherwise a local model (~2 GB RAM).", aiSwitch),
            settingRow("Auto-detect language", "Restart MyType to apply.", langSwitch),
            settingRow("Copy chip when nothing is focused", "If no text box is focused when you start talking, or you switch apps mid-dictation, the text is kept on the clipboard and a small chip lets you copy it again. Nothing appears when it types into a text box.", chipSwitch),
            settingRow("Launch at login", nil, loginSwitch),
        ]), spacing: 16)
        for (pop, mode) in [(fnPopup, Shortcuts.fn), (optionPopup, Shortcuts.option)] {
            pop.addItems(withTitles: KeyMode.allCases.map(\.title))
            pop.selectItem(at: mode.rawValue)
            pop.target = self; pop.action = #selector(pickShortcut(_:))
            pop.widthAnchor.constraint(equalToConstant: 380).isActive = true
        }
        let shortcuts = card([sectionTitle("Shortcuts", symbol: "keyboard")] + spaced([
            settingRow("Fn key", "Set “Press fn key to” to Do Nothing in System Settings › Keyboard so macOS leaves it alone.", fnPopup),
            settingRow("Right Option key", "A single tap avoids the double-tap that macOS and other apps often claim. Pressing Option with another key never dictates.", optionPopup),
        ]) + [centered(makeLabel("Hands-free keeps listening until you tap the key once more.", size: 11, color: .secondaryLabelColor, wrap: true))], spacing: 16)
        let setupBtn = PillButton(title: "Open setup guide", primary: false)
        setupBtn.target = self; setupBtn.action = #selector(runSetup)
        let setupRow = NSStackView(); setupRow.setViews([setupBtn], in: .center)
        let perms = card([sectionTitle("Permissions", symbol: "lock.shield")] + spaced([micRow.view, axRow.view, inputRow.view, keyRow.view]) + [setupRow], spacing: 14)
        let ver = centered(makeLabel("MyType \(InstallCheck.version)  ·  Created by Jay Sinha, built with Claude Code", size: 12, color: .tertiaryLabelColor))
        return page([pageHeader("Settings", "Speech, cleanup and permissions."), speech, general, shortcuts, perms, ver])
    }

    // MARK: actions

    /// Re-reads stored keys into the Settings fields (the setup guide changes them behind our back).
    func reloadKeyFields() {
        dgField.stringValue = Cloud.deepgramKey; llmKeyField.stringValue = Cloud.llmKey
        llmURLField.stringValue = Cloud.llmBaseURL; llmModelField.stringValue = Cloud.llmModel
        presetPopup.selectItem(at: (MainWindow.presets.firstIndex(where: { $0.1 == Cloud.llmBaseURL }) ?? -1) + 1)
        refresh()
    }

    @objc private func pickAppearance() {
        AppearanceMode.current = AppearanceMode.allCases[max(0, appearancePopup.indexOfSelectedItem)]
    }
    @objc private func pickShortcut(_ sender: NSPopUpButton) {
        let m = KeyMode(rawValue: max(0, sender.indexOfSelectedItem)) ?? .holdTap
        if sender === fnPopup { Shortcuts.fn = m } else { Shortcuts.option = m }
        updateHero()
    }
    private func updateHero() {
        let t = Shortcuts.homeText
        heroTitle.stringValue = t.title; heroBody.stringValue = t.body
    }
    @objc private func pickStyle() {
        WritingStyle.current = WritingStyle.allCases[max(0, stylePopup.indexOfSelectedItem)]
    }

    @objc private func runSetup() { onSetup?() }

    /// Re-renders "Welcome back, <name>" after the name changes in setup or Settings.
    func updateGreeting() {
        guard let t = greetingTitle else { return }
        let name = Profile.name
        let a = NSMutableAttributedString(string: name.isEmpty ? "Welcome back" : "Welcome back, ", attributes: [.font: serifFont(36, weight: .semibold), .foregroundColor: NSColor.labelColor, .kern: -1.6])
        if !name.isEmpty { a.append(NSAttributedString(string: name, attributes: [.font: serifFont(36, weight: .semibold), .foregroundColor: Theme.purple, .kern: -1.6])) }
        t.attributedStringValue = a
    }

    func show() {
        updateGreeting()
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
            let empty = centered(makeLabel(historyFilter == 0 ? "Your dictations will show up here." : "Nothing in this period yet.", size: 13, color: .secondaryLabelColor))
            historyStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
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
            let head = centered(makeLabel(name, size: 12, weight: .medium, color: .secondaryLabelColor))
            var rows: [NSView] = []
            for k in i..<j {
                if k > i { rows.append(divider()) }
                rows.append(historyRow(shown[k], index: k, time: clock.string(from: shown[k].date)))
            }
            let group = Surface(fill: Theme.card, stroke: Theme.line, radius: 16)
            pin(vstack(rows, spacing: 0), in: group, top: 2, leading: 0, trailing: 0, bottom: 2)
            historyStack.addArrangedSubview(head)
            head.widthAnchor.constraint(equalTo: historyStack.widthAnchor).isActive = true
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
        typeBest.isHidden = typeBest.stringValue.isEmpty

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
        if Profile.name != nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) { Profile.name = nameField.stringValue; updateGreeting() }
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
        if let v = Double(planField.stringValue.replacingOccurrences(of: ",", with: ".")), v >= 0 { Stats.planPriceUSD = v; reloadStats() }
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
