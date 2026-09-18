import AppKit

/// Small floating pill at the bottom of the screen: live waveform while listening, dots while working.
final class HUD {
    enum Mode { case hidden, listening, working }

    private let panel: NSPanel
    private let view = HUDView(frame: NSRect(x: 0, y: 0, width: 132, height: 40))

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
    private var levels = [CGFloat](repeating: 0, count: 15)
    private var timer: Timer?
    private var phase: CGFloat = 0

    override var isFlipped: Bool { false }

    func push(level v: Float) {
        // Speech RMS is small; boost and compress so quiet talkers still move the bars.
        let x = min(1, CGFloat(v) * 14)
        levels.removeFirst()
        levels.append(x.squareRoot())
    }

    private func updateTimer() {
        timer?.invalidate(); timer = nil
        guard mode != .hidden else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phase += 0.18
            self.needsDisplay = true
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor(white: 0.08, alpha: 0.92).setFill(); pill.fill()
        NSColor(white: 1, alpha: 0.12).setStroke(); pill.lineWidth = 1; pill.stroke()

        switch mode {
        case .listening:
            let n = levels.count, barW: CGFloat = 3, gap: CGFloat = 3.5
            let total = CGFloat(n) * barW + CGFloat(n - 1) * gap
            var x = (bounds.width - total) / 2
            for l in levels {
                let h = max(4, l * (bounds.height - 14))
                let r = NSRect(x: x, y: (bounds.height - h) / 2, width: barW, height: h)
                NSColor.white.withAlphaComponent(0.55 + 0.45 * l).setFill()
                NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
                x += barW + gap
            }
        case .working:
            for i in 0..<3 {
                let a = 0.35 + 0.65 * max(0, sin(phase - CGFloat(i) * 0.9))
                NSColor.white.withAlphaComponent(a).setFill()
                let cx = bounds.midX + CGFloat(i - 1) * 14
                NSBezierPath(ovalIn: NSRect(x: cx - 3.5, y: bounds.midY - 3.5, width: 7, height: 7)).fill()
            }
        case .hidden: break
        }
    }
}
