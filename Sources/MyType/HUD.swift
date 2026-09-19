import AppKit

/// Small floating mic at the bottom of the screen: ripples that swell with your voice while listening, a spinning ring while working.
final class HUD {
    enum Mode { case hidden, listening, working }

    private let panel: NSPanel
    private let view = HUDView(frame: NSRect(x: 0, y: 0, width: 88, height: 88))

    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the purple glow is drawn in the view
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
    }

    func set(_ mode: Mode) {
        if mode == .listening && view.mode == .hidden { view.restartIntro() }
        view.mode = mode
        if mode == .hidden {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                if self?.view.mode == .hidden { self?.panel.orderOut(nil) }
            })
            return
        }
        position()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func level(_ v: Float) { view.push(level: v) }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.midX - view.frame.width / 2, y: f.minY + 10))
    }
}

private final class HUDView: NSView {
    var mode: HUD.Mode = .hidden { didSet { needsDisplay = true; updateTimer() } }
    private var energy: CGFloat = 0   // smoothed voice level, 0...1
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var introStart = Date()

    private let bright = NSColor(red: 0.55, green: 0.36, blue: 0.98, alpha: 1)
    private let lavender = NSColor(red: 0.86, green: 0.80, blue: 1.0, alpha: 1)
    private lazy var micIcon: NSImage? = {
        guard let base = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .semibold)) else { return nil }
        return NSImage(size: base.size, flipped: false) { [lavender] rect in
            base.draw(in: rect)
            lavender.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }()

    override var isFlipped: Bool { false }

    func restartIntro() {
        introStart = Date()
        energy = 0
    }

    func push(level v: Float) {
        // Speech RMS is small; boost and compress so quiet talkers still move the ripples.
        energy = max(energy, min(1, CGFloat(v) * 14).squareRoot())
    }

    private func updateTimer() {
        timer?.invalidate(); timer = nil
        guard mode != .hidden else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.09
            self.energy *= 0.93
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158, c3 = c1 + 1, x = min(max(t, 0), 1) - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let t = CGFloat(Date().timeIntervalSince(introStart))
        let pop = max(0.01, easeOutBack(t / 0.30))
        let working = mode == .working
        let e = working ? 0 : energy
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r: CGFloat = 19

        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: pop, y: pop)
        ctx.translateBy(x: -c.x, y: -c.y)

        func circle(_ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }

        // Ripples drift outward and swell with your voice.
        if !working {
            for k in 0..<2 {
                let p = (phase * 0.16 + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let ring = circle(r + 3 + p * (10 + 8 * e))
                ring.lineWidth = 1.6
                bright.withAlphaComponent((1 - p) * (0.18 + 0.55 * e)).setStroke()
                ring.stroke()
            }
        }

        // Body: black disc with a glowing purple outline.
        let pulse = 0.5 + 0.5 * sin(phase * 0.9)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6 + 8 * pulse + 10 * e, color: bright.withAlphaComponent(0.4 + 0.3 * pulse + 0.3 * e).cgColor)
        NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1).setFill()
        circle(r).fill()
        ctx.restoreGState()
        let edge = circle(r - 1)
        edge.lineWidth = 2
        bright.withAlphaComponent(0.6 + 0.4 * pulse).setStroke()
        edge.stroke()

        // A comet of light circling the outline; it spins faster while the text is being prepared.
        let head = -phase * (working ? 90 : 42)
        let steps = 16
        for i in 0..<steps {
            let a = head + CGFloat(i) * 5
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: r - 1, startAngle: a, endAngle: a + 6.5, clockwise: false)
            arc.lineWidth = 2.6
            arc.lineCapStyle = .round
            lavender.withAlphaComponent(pow(1 - CGFloat(i) / CGFloat(steps), 1.6)).setStroke()
            arc.stroke()
        }

        if let icon = micIcon {
            let k = 1 + 0.14 * e
            let w = icon.size.width * k, h = icon.size.height * k
            icon.draw(in: NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                      from: .zero, operation: .sourceOver, fraction: working ? 0.55 : 1)
        }
        ctx.restoreGState()
    }
}
