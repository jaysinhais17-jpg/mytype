import AppKit

/// The chip that appears when a dictation was left on the clipboard instead of typed into a text box.
enum Recall {
    static let label = "Copy and paste last dictation"
    static let lifetime: TimeInterval = 25

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "recallChip") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "recallChip") }
    }

    static var lastText: String? { History.items.first?.text }

    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

/// Small pill that takes the mic's place after a dictation. Click it to put the text on the clipboard.
/// It never takes focus, so it can't interrupt what you're typing into.
final class RecallChip {
    private let panel: NSPanel
    private let view = ChipView()
    private var hide: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
        view.onClick = { [weak self] text in
            Recall.copy(text)
            self?.view.confirm()
            self?.schedule(after: 1.2)
        }
    }

    func show(_ text: String) {
        guard Recall.enabled else { return }
        view.configure(text: text)
        let size = view.chipSize
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + 26, width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        schedule(after: Recall.lifetime)
    }

    func dismiss() {
        hide?.cancel()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.panel.alphaValue == 0 { self?.panel.orderOut(nil) }
        })
    }

    private func schedule(after t: TimeInterval) {
        hide?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.dismiss() }
        hide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: w)
    }
}

private final class ChipView: NSView {
    var onClick: ((String) -> Void)?
    private var text = ""
    private var done = false
    private var hover = false

    private var lead: String { done ? "Copied ✓" : Recall.label }

    private var leadAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white]
    }
    var chipSize: NSSize {
        let l = NSAttributedString(string: Recall.label, attributes: leadAttrs).size().width
        return NSSize(width: 14 + 18 + 8 + l + 18, height: 36)
    }

    func configure(text: String) {
        self.text = text; done = false
        needsDisplay = true
    }
    func confirm() { done = true; needsDisplay = true }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?(text) }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
        NSColor(srgbRed: 0.10, green: hover ? 0.08 : 0.07, blue: hover ? 0.17 : 0.13, alpha: 0.97).setFill()
        pill.fill()
        Theme.purple.withAlphaComponent(hover ? 0.75 : 0.45).setStroke()
        pill.lineWidth = 1; pill.stroke()

        let name = done ? "checkmark.circle.fill" : "doc.on.doc"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) {
            let tinted = NSImage(size: img.size, flipped: false) { rect in
                img.draw(in: rect); Theme.purple.set(); rect.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: 14, y: (bounds.height - img.size.height) / 2, width: img.size.width, height: img.size.height))
        }
        let l = NSAttributedString(string: lead, attributes: leadAttrs)
        let ly = (bounds.height - l.size().height) / 2
        l.draw(at: NSPoint(x: 14 + 18 + 8, y: ly))
    }
}
