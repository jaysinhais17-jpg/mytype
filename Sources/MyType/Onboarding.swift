import AppKit
import AVFoundation
import ApplicationServices

/// Small looping illustration above each setup step: a stand-in for the "how to" clips other apps ship.
final class StepArt: NSView {
    enum Kind { case welcome, deepgramKey, groqKey, permissions, fn, tryIt }
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

    private func text(_ s: String, _ p: CGPoint, size: CGFloat, weight: NSFont.Weight = .medium, color: NSColor = .labelColor, center: Bool = true, mono: Bool = false) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
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
        // Nothing may paint outside the rounded box.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 15, yRadius: 15).addClip()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if kind == .deepgramKey { drawTutorial(.deepgram, t: t); return }
        if kind == .groqKey { drawTutorial(.groq, t: t); return }
        if kind == .permissions { drawPermissions(t: t); return }
        // Scenes are laid out for a 170pt-high box; scale them up about the centre to fill a taller one.
        NSGraphicsContext.saveGraphicsState()
        let zoom = NSAffineTransform()
        zoom.translateX(by: c.x, yBy: c.y); zoom.scale(by: min(1.6, bounds.height / 170)); zoom.translateX(by: -c.x, yBy: -c.y)
        zoom.concat()
        defer { NSGraphicsContext.restoreGraphicsState() }
        switch kind {
        case .welcome:
            let r: CGFloat = 34
            for i in 0..<3 {
                let p = CGFloat((t * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r - 8 - p * 38, y: c.y - r - 8 - p * 38, width: (r + 8 + p * 38) * 2, height: (r + 8 + p * 38) * 2))
                Theme.purple.withAlphaComponent((1 - p) * 0.45).setStroke(); ring.lineWidth = 2; ring.stroke()
            }
            NSColor(white: 0.12, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            Theme.purple.withAlphaComponent(0.6 + 0.4 * CGFloat(sin(t * 3))).setStroke(); ring.lineWidth = 2; ring.stroke()
            symbol("mic.fill", NSRect(x: c.x - 13, y: c.y - 15, width: 26, height: 30), .white)

        case .deepgramKey, .groqKey:
            break

        case .permissions:
            break

        case .fn:
            let cyc = t.truncatingRemainder(dividingBy: 3.8)
            let held = cyc > 0.5 && cyc < 2.8
            let press: CGFloat = held ? ease((cyc - 0.5) / 0.12) : 0
            let key = NSRect(x: c.x - 46, y: c.y - 36 - press * 4, width: 92, height: 76)
            rr(NSRect(x: key.minX, y: key.minY - 5 + press * 4, width: key.width, height: key.height), 14, fill: NSColor.secondaryLabelColor.withAlphaComponent(0.25))
            if held { rr(key.insetBy(dx: -6, dy: -6), 18, fill: Theme.purple.withAlphaComponent(0.16)) }
            rr(key, 14, fill: Theme.card, stroke: held ? Theme.purple : Theme.line, width: held ? 2 : 1)
            // Our own generic key: keyboards differ, so no globe and no layout copied from one model.
            text("fn", CGPoint(x: key.midX, y: key.midY), size: 28, weight: .semibold, color: held ? Theme.purple : .labelColor, mono: true)
            if held {
                bars(around: CGPoint(x: key.minX - 84, y: c.y), count: 7, t: t, spread: 12, height: 34, alpha: press)
                bars(around: CGPoint(x: key.maxX + 84, y: c.y), count: 7, t: t + 1, spread: 12, height: 34, alpha: press)
            }
            text(held ? "Hold and talk" : (cyc >= 2.8 ? "Let go: your words appear" : "Press and hold Fn"),
                 CGPoint(x: c.x, y: key.minY - 22), size: 12, color: .secondaryLabelColor)

        case .tryIt:
            let cyc = t.truncatingRemainder(dividingBy: 6.5)
            let b = NSRect(x: c.x - 200, y: c.y - 32, width: 400, height: 64)
            rr(b, 12, fill: Theme.card, stroke: Theme.line)
            if cyc < 1.6 {
                bars(around: CGPoint(x: b.midX, y: b.midY), count: 9, t: t, spread: 12, height: 30, alpha: 1)
            } else {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: b.insetBy(dx: 14, dy: 0)).addClip()
                defer { NSGraphicsContext.restoreGraphicsState() }
                let full = "Hey Sam, can you send me the notes from today?"
                let n = min(full.count, Int((cyc - 1.6) * 16))
                text(String(full.prefix(n)), CGPoint(x: b.minX + 18, y: b.midY), size: 13, center: false)
                if Int(t * 2) % 2 == 0, n < full.count {
                    let w = String(full.prefix(n)).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)]).width
                    rr(NSRect(x: b.minX + 19 + w, y: b.midY - 9, width: 1.5, height: 18), 0.5, fill: Theme.purple)
                }
            }
        }
    }

    // MARK: key tutorials

    /// Simplified, generic mock of each console. Layout and wording follow the vendors' public docs (Groq: API Keys in the top bar;
    /// Deepgram: Settings, then API Keys, then "Create a New API Key"); colours, spacing and icons are illustrative, not pixel-accurate.
    struct Tutorial {
        let site, title, cta, create, prefix, mtLabel, modalTitle, modalButton, nameLabel, secretNote, navCaption: String
        let nav: [String]
        let target: Int          // nav item that leads towards the keys page
        let sub: String?         // second-level item revealed under the target (Deepgram: Settings, then API Keys)
        let topBar: Bool         // navigation across the top (Groq) or down the side (Deepgram)
        let extra: [String]      // read-only form rows shown in the create dialog
        let accent, onAccent: NSColor
        static let deepgram = Tutorial(site: "console.deepgram.com", title: "Create your account", cta: "Sign up", create: "Create a New API Key",
                                       prefix: "dg_", mtLabel: "Deepgram key", modalTitle: "Create a New API Key", modalButton: "Create Key",
                                       nameLabel: "Friendly Name", secretNote: "Copy the key secret now. It is only shown once.",
                                       navCaption: "2   Open Settings, then API Keys",
                                       nav: ["Playground", "Settings", "Usage"], target: 1, sub: "API Keys", topBar: false,
                                       extra: ["Permissions   Member", "Expiration   Never"],
                                       accent: NSColor(srgbRed: 0.10, green: 0.78, blue: 0.50, alpha: 1), onAccent: NSColor(white: 0.05, alpha: 1))
        static let groq = Tutorial(site: "console.groq.com", title: "Log in to your account", cta: "Log in", create: "Create API Key",
                                   prefix: "gsk_", mtLabel: "Cleanup key", modalTitle: "Create API Key", modalButton: "Submit",
                                   nameLabel: "Display name", secretNote: "Copy the key now. It is only shown once.",
                                   navCaption: "2   Click API Keys in the top bar",
                                   nav: ["Playground", "API Keys", "Dashboard"], target: 1, sub: nil, topBar: true, extra: [],
                                   accent: NSColor(srgbRed: 0.96, green: 0.31, blue: 0.21, alpha: 1), onAccent: .white)
    }

    private func typed(_ s: String, _ t: Double, from: Double, cps: Double) -> String {
        String(s.prefix(max(0, min(s.count, Int((t - from) * cps)))))
    }

    private func path(_ k: [(Double, CGPoint)], _ t: Double) -> CGPoint {
        guard let f = k.first, let l = k.last else { return .zero }
        if t <= f.0 { return f.1 }
        if t >= l.0 { return l.1 }
        for i in 1..<k.count where t <= k[i].0 {
            let a = k[i - 1], b = k[i], u = ease((t - a.0) / (b.0 - a.0))
            return CGPoint(x: a.1.x + (b.1.x - a.1.x) * u, y: a.1.y + (b.1.y - a.1.y) * u)
        }
        return l.1
    }

    private func trafficLights(at o: CGPoint) {
        for (i, col) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            col.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: o.x + CGFloat(i) * 14, y: o.y - 4, width: 8, height: 8)).fill()
        }
    }

    private func drawPointer(_ keys: [(Double, CGPoint)], _ clicks: [Double], _ t: Double) {
        let pos = path(keys, t)
        for ck in clicks where t >= ck && t < ck + 0.45 {
            let q = CGFloat((t - ck) / 0.45)
            let p = path(keys, ck)
            let ring = NSBezierPath(ovalIn: NSRect(x: p.x - 6 - q * 12, y: p.y - 6 - q * 12, width: 12 + q * 24, height: 12 + q * 24))
            Theme.purple.withAlphaComponent(1 - q).setStroke(); ring.lineWidth = 2; ring.stroke()
        }
        symbol("cursorarrow", NSRect(x: pos.x - 3, y: pos.y - 18, width: 20, height: 22), .labelColor)
    }

    /// A mock Chrome window walks through: open the site, sign up, find API Keys, create a key, copy it; then the key is pasted into MyType.
    private func drawTutorial(_ tu: Tutorial, t rawT: Double) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let loop = 15.6
        let t = rawT.truncatingRemainder(dividingBy: loop)
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        func mid(_ r: NSRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

        // Timeline
        let tKeys = tu.sub == nil ? 4.75 : 5.7           // keys page is showing from here
        let tCreate = 6.9, tModalEnd = 9.0, tCopy = 10.1, tFadeOut = 10.7, tMy = 11.2, tPaste = 12.2, tFill = 12.6, tCheck = 13.0, tEnd = 14.9

        let win = NSRect(x: c.x - 270, y: bounds.minY + 42, width: 540, height: bounds.height - 56)
        let bar = NSRect(x: win.minX, y: win.maxY - 30, width: win.width, height: 30)
        let pg = NSRect(x: win.minX, y: win.minY, width: win.width, height: win.height - 30)
        let card = NSRect(x: pg.midX - 110, y: pg.midY - 62, width: 220, height: 124)
        let f1 = NSRect(x: card.minX + 16, y: card.maxY - 58, width: 188, height: 22)
        let f2 = NSRect(x: card.minX + 16, y: card.maxY - 88, width: 188, height: 22)
        let cta = NSRect(x: card.minX + 16, y: card.minY + 10, width: 188, height: 22)

        let showSub = tu.sub != nil && t >= 4.5
        let navH: CGFloat = 28
        let sbW: CGFloat = tu.topBar ? 0 : 120
        let topH: CGFloat = tu.topBar ? 30 : 0
        func item(_ i: Int) -> NSRect {
            if tu.topBar { return NSRect(x: pg.minX + 12 + CGFloat(i) * 92, y: pg.maxY - 27, width: 84, height: 22) }
            let slot = (showSub && i > tu.target) ? i + 1 : i
            return NSRect(x: pg.minX + 8, y: pg.maxY - 34 - CGFloat(slot) * navH, width: 104, height: 22)
        }
        let subItem = NSRect(x: pg.minX + 18, y: pg.maxY - 34 - CGFloat(tu.target + 1) * navH, width: 94, height: 22)
        let m = NSRect(x: pg.minX + sbW + 16, y: pg.minY + 10, width: pg.width - sbW - 32, height: pg.height - 20 - topH)
        let createBtn = NSRect(x: m.maxX - (tu.topBar ? 120 : 156), y: m.maxY - 24, width: tu.topBar ? 120 : 156, height: 22)
        let mh = 108 + CGFloat(tu.extra.count) * 28
        let modal = NSRect(x: m.midX - 115, y: pg.midY - mh / 2, width: 230, height: mh)
        let mField = NSRect(x: modal.minX + 14, y: modal.maxY - 68, width: 202, height: 22)
        let mBtn = NSRect(x: modal.maxX - 94, y: modal.minY + 12, width: 80, height: 22)
        let row = NSRect(x: m.minX, y: m.maxY - 78, width: m.width, height: 30)
        let copyBtn = NSRect(x: row.maxX - 66, y: row.midY - 11, width: 60, height: 22)
        let mw = NSRect(x: c.x - 190, y: bounds.minY + 46, width: 380, height: bounds.height - 62)
        let field = NSRect(x: mw.minX + 24, y: mw.midY - 18, width: 332, height: 30)

        let far = CGPoint(x: win.maxX - 30, y: win.minY + 24)
        var keys: [(Double, CGPoint)] = [(0, far), (2.3, far), (2.9, mid(cta)), (3.3, mid(cta)), (4.2, mid(item(tu.target)))]
        var clicks: [Double] = [3.1, 4.4]
        if tu.sub != nil {
            keys += [(4.5, mid(item(tu.target))), (5.3, mid(subItem)), (5.7, mid(subItem))]; clicks.append(5.5)
        } else {
            keys += [(4.9, mid(item(tu.target)))]
            clicks = [3.1, 4.7]
        }
        keys += [(tCreate - 0.5, mid(createBtn)), (tCreate + 0.1, mid(createBtn)), (tCreate + 1.4, mid(mBtn)), (tCreate + 2.0, mid(mBtn)),
                 (tCopy - 0.4, mid(copyBtn)), (tCopy + 0.3, mid(copyBtn)), (tMy + 0.3, mid(field)), (loop, mid(field))]
        clicks += [tCreate - 0.05, tCreate + 1.85, tCopy, tPaste - 0.7]

        // Browser
        let bAlpha = CGFloat(min(t < 0.4 ? t / 0.4 : 1, t > tFadeOut + 0.5 ? 0 : (t > tFadeOut ? 1 - (t - tFadeOut) / 0.5 : 1)))
        if bAlpha > 0.01 {
            cg.saveGState(); cg.setAlpha(bAlpha)
            rr(win, 10, fill: Theme.card, stroke: Theme.line)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: win, xRadius: 10, yRadius: 10).addClip()
            Theme.field.setFill(); bar.fill()
            Theme.line.setFill(); NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 1).fill()
            trafficLights(at: CGPoint(x: bar.minX + 12, y: bar.midY))
            // Real Chrome icon when installed, otherwise a generic browser badge
            let ic = CGPoint(x: bar.minX + 70, y: bar.midY)
            if let chrome = Self.appIcon("com.google.Chrome") {
                chrome.draw(in: NSRect(x: ic.x - 8, y: ic.y - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1)
            } else { for (i, col) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                let w = NSBezierPath(); w.move(to: ic)
                w.appendArc(withCenter: ic, radius: 7, startAngle: CGFloat(30 + 120 * i), endAngle: CGFloat(150 + 120 * i)); w.close()
                col.setFill(); w.fill()
            }
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: ic.x - 3.4, y: ic.y - 3.4, width: 6.8, height: 6.8)).fill()
            NSColor.systemBlue.setFill(); NSBezierPath(ovalIn: NSRect(x: ic.x - 2.5, y: ic.y - 2.5, width: 5, height: 5)).fill()
            }
            let ab = NSRect(x: bar.minX + 88, y: bar.midY - 10, width: bar.width - 88 - 16, height: 20)
            rr(ab, 10, fill: Theme.card, stroke: Theme.line)
            symbol("lock.fill", NSRect(x: ab.minX + 9, y: ab.midY - 5, width: 9, height: 10), .secondaryLabelColor)
            text(typed(tu.site, t, from: 0.3, cps: 18), CGPoint(x: ab.minX + 24, y: ab.midY), size: 11, color: .labelColor, center: false)

            let onKeys = t >= tKeys
            if t < 3.3 {
                rr(card, 10, fill: Theme.field, stroke: Theme.line)
                if t > 1.2 {
                    text(tu.title, CGPoint(x: card.midX, y: card.maxY - 18), size: 11, weight: .bold)
                    rr(f1, 6, fill: Theme.card, stroke: Theme.line); rr(f2, 6, fill: Theme.card, stroke: Theme.line)
                    text(typed("you@email.com", t, from: 1.6, cps: 12), CGPoint(x: f1.minX + 8, y: f1.midY), size: 10, center: false)
                    text(typed("••••••••", t, from: 2.4, cps: 10), CGPoint(x: f2.minX + 8, y: f2.midY), size: 10, center: false)
                    rr(cta, 6, fill: tu.accent)
                    text(tu.cta, mid(cta), size: 11, weight: .semibold, color: tu.onAccent)
                }
            } else {
                if tu.topBar {
                    Theme.field.setFill(); NSRect(x: pg.minX, y: pg.maxY - topH, width: pg.width, height: topH).fill()
                    Theme.line.setFill(); NSRect(x: pg.minX, y: pg.maxY - topH, width: pg.width, height: 1).fill()
                } else {
                    Theme.field.setFill(); NSRect(x: pg.minX, y: pg.minY, width: sbW, height: pg.height).fill()
                    Theme.line.setFill(); NSRect(x: pg.minX + sbW - 1, y: pg.minY, width: 1, height: pg.height).fill()
                }
                for (i, name) in tu.nav.enumerated() {
                    let r = item(i)
                    let sel = i == tu.target && (tu.sub == nil ? onKeys : t >= 4.4)
                    if sel { rr(r, 6, fill: tu.accent.withAlphaComponent(0.25)) }
                    text(name, CGPoint(x: r.minX + 10, y: r.midY), size: 11, weight: sel ? .semibold : .regular, center: false)
                }
                if showSub, let sub = tu.sub {
                    let sel = onKeys
                    if sel { rr(subItem, 6, fill: tu.accent.withAlphaComponent(0.25)) }
                    text(sub, CGPoint(x: subItem.minX + 10, y: subItem.midY), size: 11, weight: sel ? .semibold : .regular, center: false)
                }
                if !onKeys {
                    for (i, w) in [0.7, 0.5, 0.6].enumerated() {
                        rr(NSRect(x: m.minX, y: m.maxY - 22 - CGFloat(i) * 28, width: m.width * CGFloat(w), height: 14), 5, fill: Theme.line)
                    }
                } else {
                    text("API Keys", CGPoint(x: m.minX, y: m.maxY - 13), size: 13, weight: .bold, center: false)
                    rr(createBtn, 6, fill: tu.accent)
                    text(tu.create, mid(createBtn), size: 10.5, weight: .semibold, color: tu.onAccent)
                    Theme.line.setFill(); NSRect(x: m.minX, y: m.maxY - 34, width: m.width, height: 1).fill()
                    if t < tModalEnd {
                        text("No API keys yet", CGPoint(x: m.midX, y: m.maxY - 62), size: 11, color: .secondaryLabelColor)
                    } else {
                        let copied = t >= tCopy
                        rr(row, 8, fill: Theme.field, stroke: Theme.line)
                        text("MyType", CGPoint(x: row.minX + 12, y: row.midY), size: 11, weight: .semibold, center: false)
                        text(tu.prefix + "••••••••••••••••", CGPoint(x: row.minX + 84, y: row.midY), size: 11, color: .secondaryLabelColor, center: false)
                        rr(copyBtn, 6, fill: copied ? NSColor.systemGreen.withAlphaComponent(0.2) : Theme.card, stroke: copied ? NSColor.systemGreen : Theme.line)
                        text(copied ? "Copied ✓" : "Copy", mid(copyBtn), size: 10.5, weight: .semibold, color: copied ? .systemGreen : .labelColor)
                        text(tu.secretNote, CGPoint(x: m.minX, y: row.minY - 14), size: 10, color: .secondaryLabelColor, center: false)
                    }
                }
                if t >= tCreate + 0.1 && t < tModalEnd {
                    NSColor.black.withAlphaComponent(0.28).setFill(); pg.fill()
                    rr(modal, 10, fill: Theme.card, stroke: Theme.line)
                    text(tu.modalTitle, CGPoint(x: modal.midX, y: modal.maxY - 16), size: 11, weight: .bold)
                    text(tu.nameLabel, CGPoint(x: mField.minX, y: mField.maxY + 7), size: 9, color: .secondaryLabelColor, center: false)
                    rr(mField, 6, fill: Theme.field, stroke: Theme.line)
                    text(typed("MyType", t, from: tCreate + 0.4, cps: 9), CGPoint(x: mField.minX + 8, y: mField.midY), size: 10, center: false)
                    for (i, e) in tu.extra.enumerated() {
                        let r = NSRect(x: mField.minX, y: mField.minY - 28 * CGFloat(i + 1), width: mField.width, height: 20)
                        rr(r, 6, fill: Theme.field, stroke: Theme.line)
                        text(e, CGPoint(x: r.minX + 8, y: r.midY), size: 9.5, color: .secondaryLabelColor, center: false)
                    }
                    rr(mBtn, 6, fill: tu.accent)
                    text(tu.modalButton, mid(mBtn), size: 10.5, weight: .semibold, color: tu.onAccent)
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            cg.restoreGState()
        }

        // MyType window
        let mAlpha = CGFloat(min(max(0, (t - tMy) / 0.4), t > tEnd ? max(0, 1 - (t - tEnd) / 0.5) : 1))
        if mAlpha > 0.01 {
            cg.saveGState(); cg.setAlpha(mAlpha)
            rr(mw, 12, fill: Theme.card, stroke: Theme.line)
            trafficLights(at: CGPoint(x: mw.minX + 12, y: mw.maxY - 14))
            text("MyType", CGPoint(x: mw.midX, y: mw.maxY - 14), size: 11, weight: .semibold, color: .secondaryLabelColor)
            text(tu.mtLabel, CGPoint(x: field.minX, y: field.maxY + 16), size: 11, color: .secondaryLabelColor, center: false)
            let focus = t >= tPaste - 0.7
            rr(field, 8, fill: Theme.field, stroke: focus ? Theme.purple : Theme.line, width: focus ? 1.5 : 1)
            if t >= tFill {
                text(String(repeating: "•", count: 26), CGPoint(x: field.minX + 12, y: field.midY), size: 14, center: false)
                if t >= tCheck {
                    let s = 0.6 + 0.4 * ease((t - tCheck) / 0.25)
                    let badge = NSRect(x: field.maxX - 30, y: field.midY - 10 * s, width: 20 * s, height: 20 * s)
                    NSColor.systemGreen.setFill(); NSBezierPath(ovalIn: badge).fill()
                    symbol("checkmark", badge.insetBy(dx: 5 * s, dy: 5 * s), .white)
                }
            } else if focus, Int(t * 2) % 2 == 0 {
                rr(NSRect(x: field.minX + 12, y: field.midY - 9, width: 1.5, height: 18), 0.5, fill: Theme.purple)
            }
            if t >= tPaste && t < tPaste + 0.6 {
                let chip = NSRect(x: field.maxX - 48, y: field.maxY + 6, width: 44, height: 20)
                rr(chip, 6, fill: Theme.purple)
                text("⌘V", mid(chip), size: 11, weight: .semibold, color: .white)
            }
            cg.restoreGState()
        }

        // Caption
        let caption: String
        switch t {
        case ..<3.4: caption = "1   Open \(tu.site) in Chrome and \(tu.cta.lowercased())"
        case ..<(tKeys + 0.3): caption = tu.navCaption
        case ..<tModalEnd: caption = "3   Click “\(tu.create)” and name your key"
        case ..<tMy: caption = "4   Copy the key. It is only shown once"
        default: caption = "5   Paste it into MyType"
        }
        text(caption, CGPoint(x: c.x, y: bounds.minY + 22), size: 12, weight: .semibold, color: .secondaryLabelColor)
        text("Simplified illustration", CGPoint(x: bounds.maxX - 62, y: bounds.minY + 12), size: 8.5, weight: .regular,
             color: NSColor.secondaryLabelColor.withAlphaComponent(0.7))

        drawPointer(keys, clicks, t)
    }

    // MARK: permissions tutorial

    private static var iconCache: [String: NSImage] = [:]
    /// The real icon of an installed app ("self" = MyType). Nil when the app isn't on this Mac.
    static func appIcon(_ id: String) -> NSImage? {
        if let c = iconCache[id] { return c }
        let img: NSImage?
        if id == "self" { img = NSApp.applicationIconImage }
        else { img = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) } }
        if let img { iconCache[id] = img }
        return img
    }

    /// System Settings mock, one pane at a time: Microphone, Accessibility, Input Monitoring. MyType sits in the list next to
    /// well-known apps and is switched on. Real app icons are read from this Mac; a coloured symbol square stands in when an app isn't installed.
    private func drawPermissions(t rawT: Double) {
        struct App { let name, sym: String; let color: NSColor; let on: Bool; var id: String? = nil }
        struct Pane { let title, blurb, caption: String; let apps: [App] }
        let mt = App(name: "MyType", sym: "mic.fill", color: NSColor(srgbRed: 0.42, green: 0.24, blue: 0.85, alpha: 1), on: false, id: "self")
        let panes = [
            Pane(title: "Microphone", blurb: "Allow the applications below to access your microphone.", caption: "Microphone",
                 apps: [App(name: "FaceTime", sym: "video.fill", color: .systemGreen, on: true, id: "com.apple.FaceTime"), mt,
                        App(name: "Safari", sym: "safari.fill", color: .systemBlue, on: false, id: "com.apple.Safari")]),
            Pane(title: "Accessibility", blurb: "Allow the applications below to control your computer.", caption: "Accessibility",
                 apps: [App(name: "Automator", sym: "gearshape.2.fill", color: .systemGray, on: true, id: "com.apple.Automator"), mt,
                        App(name: "Terminal", sym: "terminal.fill", color: NSColor(white: 0.15, alpha: 1), on: true, id: "com.apple.Terminal")]),
            Pane(title: "Input Monitoring", blurb: "Allow the applications below to monitor input from your keyboard.", caption: "Input Monitoring",
                 apps: [App(name: "Google Chrome", sym: "globe", color: .systemOrange, on: false, id: "com.google.Chrome"), mt,
                        App(name: "Terminal", sym: "terminal.fill", color: NSColor(white: 0.15, alpha: 1), on: true, id: "com.apple.Terminal")]),
        ]
        let per = 5.4
        let t = rawT.truncatingRemainder(dividingBy: per * 3)
        let idx = min(2, Int(t / per)), u = t - Double(idx) * per
        let pane = panes[idx]
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        func mid(_ r: NSRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

        let win = NSRect(x: c.x - 250, y: bounds.minY + 42, width: 500, height: bounds.height - 56)
        let bar = NSRect(x: win.minX, y: win.maxY - 28, width: win.width, height: 28)
        rr(win, 10, fill: Theme.card, stroke: Theme.line)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: win, xRadius: 10, yRadius: 10).addClip()
        Theme.field.setFill(); bar.fill()
        Theme.line.setFill(); NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 1).fill()
        trafficLights(at: CGPoint(x: bar.minX + 12, y: bar.midY))

        let a = CGFloat(min(u / 0.4, (per - u) / 0.4, 1))
        cg.saveGState(); cg.setAlpha(max(0, a))
        text("‹", CGPoint(x: bar.minX + 62, y: bar.midY), size: 15, weight: .regular, color: .secondaryLabelColor)
        text("Privacy & Security  ›  \(pane.title)", CGPoint(x: bar.midX, y: bar.midY), size: 11, weight: .semibold)
        text(pane.title, CGPoint(x: win.minX + 24, y: bar.minY - 20), size: 14, weight: .bold, center: false)
        text(pane.blurb, CGPoint(x: win.minX + 24, y: bar.minY - 38), size: 10, color: .secondaryLabelColor, center: false)

        let top = bar.minY - 52
        let rowH = min(38, (top - win.minY - 12) / 3)
        let list = NSRect(x: win.minX + 24, y: top - rowH * 3, width: win.width - 48, height: rowH * 3)
        rr(list, 9, fill: Theme.field, stroke: Theme.line)
        var mtSwitch = NSRect.zero, mtRow = NSRect.zero
        let switchOn = u >= 1.85 && u < per - 0.5
        let flip = ease((u - 1.85) / 0.25)
        for (i, app) in pane.apps.enumerated() {
            let r = NSRect(x: list.minX, y: list.maxY - rowH * CGFloat(i + 1), width: list.width, height: rowH)
            let isMT = app.name == "MyType"
            if i > 0 { Theme.line.setFill(); NSRect(x: r.minX + 12, y: r.maxY, width: r.width - 24, height: 1).fill() }
            if isMT && u > 1.0 && u < per - 0.5 { rr(r.insetBy(dx: 3, dy: 3), 7, fill: Theme.purple.withAlphaComponent(0.10)) }
            let ic = NSRect(x: r.minX + 12, y: r.midY - 12, width: 24, height: 24)
            if let img = app.id.flatMap(Self.appIcon) {
                img.draw(in: ic, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                rr(ic, 6, fill: app.color)
                symbol(app.sym, ic.insetBy(dx: 5, dy: 5), .white)
            }
            text(app.name, CGPoint(x: ic.maxX + 10, y: r.midY), size: 12, weight: isMT ? .semibold : .regular, center: false)
            let sw = NSRect(x: r.maxX - 12 - 36, y: r.midY - 10, width: 36, height: 20)
            let on = isMT ? flip : (app.on ? 1 : 0)
            let off = NSColor.secondaryLabelColor.withAlphaComponent(0.3), green = NSColor.systemGreen
            rr(sw, 10, fill: off.blended(withFraction: on, of: green) ?? off)
            let kx = sw.minX + 2 + on * 16
            NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: kx, y: sw.minY + 2, width: 16, height: 16)).fill()
            if isMT { mtSwitch = sw; mtRow = r }
        }
        cg.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        let far = CGPoint(x: win.maxX - 24, y: win.minY + 16)
        let keys: [(Double, CGPoint)] = [(0, far), (0.5, far), (1.7, mid(mtSwitch)), (per, mid(mtSwitch))]
        if a > 0.3 { drawPointer(keys, [1.8], u) }

        let cap = switchOn ? "MyType is on for \(pane.caption)" : "Switch MyType on under \(pane.caption)"
        text("\(idx + 1) of 3   " + cap, CGPoint(x: c.x, y: bounds.minY + 22), size: 12, weight: .semibold, color: .secondaryLabelColor)
        for i in 0..<3 {
            (i == idx ? Theme.purple : NSColor.secondaryLabelColor.withAlphaComponent(0.3)).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 14 + CGFloat(i) * 12, y: bounds.minY + 8 - 4, width: 6, height: 6)).fill()
        }
        _ = mtRow
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
    private let titleLabel = makeLabel("", size: 30, weight: .bold)
    private let bodyLabel = makeLabel("", size: 14, color: .secondaryLabelColor, wrap: true)
    private let extra = NSStackView()
    private let backButton = PillButton(title: "Back", primary: false)
    private let nextButton = PillButton(title: "Continue")
    private var dots: [Surface] = []
    private var timer: Timer?

    private let dgField = SecureInputField(), llmField = SecureInputField()
    private let nameField = InputField()
    private lazy var dgBox = InputBox(dgField, width: 420)
    private lazy var llmBox = InputBox(llmField, width: 420)
    private let nameRow = NSStackView()
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

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
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
        extra.orientation = .vertical; extra.alignment = .centerX; extra.spacing = 12
        titleLabel.alignment = .center
        bodyLabel.alignment = .center
        let column = NSStackView(views: [art, titleLabel, bodyLabel, extra])
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 14
        titleLabel.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        column.setCustomSpacing(20, after: art)
        root.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        for v in [art, bodyLabel, extra] as [NSView] { v.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        art.heightAnchor.constraint(equalToConstant: 250).isActive = true

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
            column.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            column.widthAnchor.constraint(equalToConstant: 700),
            backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 56),
            backButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            nextButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -56),
            nextButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            dotRow.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            dotRow.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
        ])

        dgField.delegate = self; llmField.delegate = self; nameField.delegate = self
        nameField.placeholderString = "Your name or nickname"
        nameRow.setViews([InputBox(nameField, width: 260, align: .center)], in: .center)
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
        nameField.stringValue = Profile.name
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

    /// Numbered lines: the block is centred, the text inside stays left-aligned so the numbers line up.
    private func steps(_ lines: [String]) -> NSView {
        let l = makeLabel(lines.enumerated().map { "\($0.offset + 1)   \($0.element)" }.joined(separator: "\n"), size: 13, wrap: true)
        let row = NSStackView(views: [l]); row.orientation = .vertical; row.alignment = .centerX
        return row
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
            views = [makeLabel("What should MyType call you?", size: 13, weight: .medium), nameRow,
                     steps(["Add your Deepgram key (turns speech into text)", "Add your Groq key (tidies the text, optional)",
                            "Allow three macOS permissions", "Set up the Fn key and try it"]),
                     makeLabel("Privacy: audio goes to Deepgram and text to Groq, using your own keys. Nothing passes through anyone else, and MyType keeps no copy of your voice.",
                               size: 11, color: .secondaryLabelColor, wrap: true)]
        case 1:
            art.kind = .deepgramKey
            titleLabel.stringValue = "Add your speech key"
            bodyLabel.stringValue = "MyType uses Deepgram to turn your voice into text. New accounts get $200 of free credit, which is up to 2 years of moderate to heavy use."
            views = [steps(["Sign up at console.deepgram.com", "Open API Keys and click Create a New API Key", "Copy the key and paste it below"]),
                     btn("Open Deepgram") { [weak self] in self?.open("https://console.deepgram.com/signup") }, dgBox, status]
        case 2:
            art.kind = .groqKey
            titleLabel.stringValue = "Add your cleanup key (optional)"
            bodyLabel.stringValue = "Groq's free tier fixes punctuation, removes “um”s and honours self-corrections. Skip it and you still get accurate text, just less polished."
            views = [steps(["Sign up at console.groq.com", "Open API Keys and click Create API Key", "Copy the key and paste it below"]),
                     btn("Open Groq") { [weak self] in self?.open("https://console.groq.com/keys") }, llmBox, status]
        case 3:
            art.kind = .permissions
            titleLabel.stringValue = "Allow three permissions"
            bodyLabel.stringValue = "macOS asks for these so MyType can hear you, see the Fn key and type for you. Click Grant, then switch MyType on in the list that opens."
            views = [micRow.view, axRow.view, inputRow.view,
                     makeLabel("A switch already on but still red? Turn it off and on again.", size: 11, color: .secondaryLabelColor)]
        case 4:
            art.kind = .fn
            titleLabel.stringValue = "Set up the Fn key"
            bodyLabel.stringValue = "By default, the fn key opens the emoji picker. Tell macOS to leave it alone so MyType can use it."
            views = [steps(["Open Keyboard settings below", "Find “Press fn key to”", "Choose Do Nothing"]),
                     btn("Open Keyboard settings") { [weak self] in self?.open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension") },
                     fnRow.view]
        default:
            art.kind = .tryIt
            titleLabel.stringValue = "Try it"
            bodyLabel.stringValue = "Click the box, hold Fn, say something, and let go. Double-tap Fn for hands-free; tap once to stop. Right Option works too: tap it once for hands-free."
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
        for case let l as NSTextField in views where !l.isEditable { l.alignment = .center }
        for v in views { extra.addArrangedSubview(v); if !(v is LinkButton || v is InputBox) { v.widthAnchor.constraint(equalTo: extra.widthAnchor).isActive = true } }
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
        case 0: Profile.name = nameField.stringValue; go(1)
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
