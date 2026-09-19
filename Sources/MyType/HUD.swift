import AppKit

/// Small floating mic at the bottom of the screen: a still purple disc when quiet that swells, glows and spins a white comet as you speak, and a spinning ring while working.
final class HUD {
    enum Mode { case hidden, listening, working }

    private let panel: NSPanel
    private let view = HUDView(frame: NSRect(x: 0, y: 0, width: 150, height: 150))

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
        panel.setFrameOrigin(NSPoint(x: f.midX - view.frame.width / 2, y: f.minY - 18))
    }
}

private final class HUDView: NSView {
    var mode: HUD.Mode = .hidden { didSet { needsDisplay = true; updateTimer() } }
    private var target: CGFloat = 0   // latest voice level (0...1), decays between audio buffers
    private var smooth: CGFloat = 0   // low-passed copy of `target`; everything animated follows this, so nothing steps
    private var comet: CGFloat = 0    // comet visibility, eased
    private var spin: CGFloat = 0     // comet angle in degrees; only advances while there is voice
    private var ripple: CGFloat = 0   // integrated ripple clock (never jumps when the voice level changes)
    private var breath: CGFloat = 0   // integrated breathing phase (radians); faster with louder speech, so the pulse never jerks
    private var floor: CGFloat = 0.004 // running estimate of the room's background noise
    private var lastVoice = CACurrentMediaTime() - 10 // when the gate last heard speech
    private var lastTick = CACurrentMediaTime()
    private var timer: Timer?
    private var introStart = Date()

    private let bright = NSColor(red: 0.55, green: 0.36, blue: 0.98, alpha: 1)
    private let lavender = NSColor(red: 0.86, green: 0.80, blue: 1.0, alpha: 1)
    private let iconScale: CGFloat = 3 // rendered at 3x and drawn smaller so it stays crisp when the disc swells
    private lazy var micIcon: NSImage? = {
        guard let base = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17 * iconScale, weight: .semibold)) else { return nil }
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
        target = 0; smooth = 0; comet = 0; ripple = 0; breath = 0; floor = 0.004
        lastVoice = CACurrentMediaTime() - 10
        lastTick = CACurrentMediaTime()
    }

    func push(level v: Float) {
        // Noise gate: track the background level and ignore anything near it, so a quiet room means zero motion.
        let x = CGFloat(v)
        if x < floor { floor = x } else { floor = min(0.02, floor + (x - floor) * 0.004) }
        let gate = max(0.012, floor * 2.5 + 0.004)
        let act = min(1, max(0, (x - gate) / 0.05)).squareRoot()
        if act > 0.12 { lastVoice = CACurrentMediaTime() }
        target = max(target, act)
    }

    private func updateTimer() {
        timer?.invalidate(); timer = nil
        guard mode != .hidden else { return }
        lastTick = CACurrentMediaTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Frame-rate independent smoothing: fast attack, gentler release.
    private func follow(_ value: inout CGFloat, to goal: CGFloat, attack: CGFloat, release: CGFloat, dt: CGFloat) {
        let tau = goal > value ? attack : release
        value += (goal - value) * (1 - exp(-dt / tau))
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.05, now - lastTick)); lastTick = now
        target *= exp(-dt / 0.25)
        // Stay lit through the small gaps between words; go quiet after about a second of silence.
        if now - lastVoice < 1.1 { target = max(target, 0.45) }
        follow(&smooth, to: target, attack: 0.07, release: 0.20, dt: dt)
        let speaking = mode == .listening
        follow(&comet, to: mode == .working ? 1 : (speaking ? min(1, smooth * 5) : 0), attack: 0.08, release: 0.3, dt: dt)
        spin += (mode == .working ? 300 : 240 + 560 * smooth) * comet * dt
        ripple += dt * (0.35 + 0.9 * smooth)
        breath += dt * 2 * .pi * (1.4 + 2.6 * smooth) // ~1.4 Hz when soft, ~4 Hz when loud
        needsDisplay = true
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
        let e = mode == .listening ? smooth : 0        // voice level
        let glow = working ? 0.35 : e                  // purple illumination: none when quiet
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let r: CGFloat = 19

        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        // A gentle breathing pulse (at most ~12% bigger) whose depth and speed follow your voice; exactly still when you're quiet.
        let grow = pop * (1 + e * (0.04 + 0.08 * (0.5 - 0.5 * cos(breath))))
        ctx.scaleBy(x: grow, y: grow)
        ctx.translateBy(x: -c.x, y: -c.y)

        func circle(_ radius: CGFloat) -> NSBezierPath {
            NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }

        // Ripples exist only while there is voice.
        if e > 0.03 {
            for k in 0..<3 {
                let p = (ripple + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
                let ring = circle(r + 2 + p * (6 + 24 * e))
                ring.lineWidth = 1.2 + 1.6 * e
                bright.withAlphaComponent((1 - p) * (1 - p) * 0.8 * min(1, e * 1.6)).setStroke()
                ring.stroke()
            }
        }

        // Body: black disc with a solid purple outline that lights up with your voice.
        ctx.saveGState()
        if glow > 0.01 {
            ctx.setShadow(offset: .zero, blur: 4 + 22 * glow, color: bright.withAlphaComponent(min(1, 0.85 * glow + 0.1)).cgColor)
        }
        NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1).setFill()
        circle(r).fill()
        ctx.restoreGState()
        let edge = circle(r - 1)
        edge.lineWidth = 2
        bright.blended(withFraction: 0.35 * glow, of: NSColor(red: 0.72, green: 0.58, blue: 1, alpha: 1))?.setStroke()
        edge.stroke()

        // The white comet is hidden and still until you speak, then circles faster the louder you are.
        if comet > 0.01 {
            let steps = 60
            for i in 0..<steps {
                let a = -spin + CGFloat(i) * 2.4
                let arc = NSBezierPath()
                arc.appendArc(withCenter: c, radius: r - 1, startAngle: a, endAngle: a + 3, clockwise: false)
                arc.lineWidth = 3.4
                arc.lineCapStyle = .round
                NSColor.white.blended(withFraction: CGFloat(i) / CGFloat(steps), of: lavender)!
                    .withAlphaComponent(pow(1 - CGFloat(i) / CGFloat(steps), 1.2) * comet).setStroke()
                arc.stroke()
            }
        }

        if let icon = micIcon {
            let w = icon.size.width / iconScale, h = icon.size.height / iconScale
            icon.draw(in: NSRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h),
                      from: .zero, operation: .sourceOver, fraction: working ? 0.55 : 1)
        }
        ctx.restoreGState()
    }
}
