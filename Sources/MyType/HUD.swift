import AppKit

/// Small floating pill at the bottom of the screen: live waveform while listening, dots while working.
final class HUD {
    enum Mode { case hidden, listening, working }

    private let panel: NSPanel
    private let view = HUDView(frame: NSRect(x: 0, y: 0, width: 168, height: 48))

    init() {
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
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
        panel.setFrameOrigin(NSPoint(x: f.midX - view.frame.width / 2, y: f.minY + 28))
    }
}

private final class HUDView: NSView {
    var mode: HUD.Mode = .hidden { didSet { needsDisplay = true; updateTimer() } }
    private var levels = [CGFloat](repeating: 0, count: 17)
    private var timer: Timer?
    private var phase: CGFloat = 0
    private var introStart = Date()

    private let deep = NSColor(red: 0.29, green: 0.16, blue: 0.62, alpha: 1)
    private let bright = NSColor(red: 0.55, green: 0.36, blue: 0.98, alpha: 1)
    private let lavender = NSColor(red: 0.86, green: 0.80, blue: 1.0, alpha: 1)
    private lazy var micIcon: NSImage? = {
        guard let base = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold)) else { return nil }
        let img = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.white.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return img
    }()

    override var isFlipped: Bool { false }

    func restartIntro() {
        introStart = Date()
        levels = [CGFloat](repeating: 0, count: levels.count)
    }

    func push(level v: Float) {
        // Speech RMS is small; boost and compress so quiet talkers still move the bars.
        let x = min(1, CGFloat(v) * 14)
        levels.removeFirst()
        levels.append(x.squareRoot())
    }

    private func updateTimer() {
        timer?.invalidate(); timer = nil
        guard mode != .hidden else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.09
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158, c3 = c1 + 1, x = min(max(t, 0), 1) - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }
    private func easeInOut(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = CGFloat(Date().timeIntervalSince(introStart))
        let pop = easeOutBack(t / 0.28)              // circle springs in
        let morph = easeInOut((t - 0.30) / 0.35)     // then stretches into the bar pill
        let h: CGFloat = 40
        let w = h + (bounds.width - 8 - h) * morph
        let breathe = mode == .listening ? 1 + 0.02 * sin(phase * 2) : 1
        let scale = max(0.01, pop) * breathe

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.midX, y: -bounds.midY)

        let rect = NSRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        let pill = NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2)
        NSGradient(starting: bright, ending: deep)?.draw(in: pill, angle: -60)
        NSColor(white: 1, alpha: 0.22).setStroke(); pill.lineWidth = 1; pill.stroke()

        // Mic icon fades out as the bars take over.
        let micAlpha = max(0, 1 - morph * 1.6)
        if micAlpha > 0, let icon = micIcon {
            let r = NSRect(x: bounds.midX - icon.size.width / 2, y: bounds.midY - icon.size.height / 2,
                           width: icon.size.width, height: icon.size.height)
            icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: micAlpha)
        }

        if morph > 0.4 {
            let fade = min(1, (morph - 0.4) / 0.6)
            switch mode {
            case .listening:
                let n = levels.count, barW: CGFloat = 3, gap: CGFloat = 3.5
                let total = CGFloat(n) * barW + CGFloat(n - 1) * gap
                var x = bounds.midX - total / 2
                for (i, l) in levels.enumerated() {
                    // Gentle idle shimmer so the bars are alive even in silence.
                    let idle = 0.10 + 0.06 * sin(phase * 1.5 + CGFloat(i) * 0.7)
                    let v = max(idle, l)
                    let bh = max(4, v * (h - 12))
                    let r = NSRect(x: x, y: bounds.midY - bh / 2, width: barW, height: bh)
                    lavender.withAlphaComponent((0.6 + 0.4 * v) * fade).setFill()
                    NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
                    x += barW + gap
                }
            case .working:
                for i in 0..<3 {
                    let a = 0.35 + 0.65 * max(0, sin(phase * 2 - CGFloat(i) * 0.9))
                    lavender.withAlphaComponent(a * fade).setFill()
                    let cx = bounds.midX + CGFloat(i - 1) * 14
                    NSBezierPath(ovalIn: NSRect(x: cx - 3.5, y: bounds.midY - 3.5, width: 7, height: 7)).fill()
                }
            case .hidden: break
            }
        }
        ctx.restoreGState()
    }
}
