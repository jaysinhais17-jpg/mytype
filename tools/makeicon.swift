import AppKit

/// App icon: the dictation HUD as a Dock icon: a black disc with a glowing purple rim, ripples and a white mic, on a deep purple tile.
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bright = NSColor(red: 0.55, green: 0.36, blue: 0.98, alpha: 1)
    let c = CGPoint(x: s / 2, y: s / 2)

    // Tile
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.13, blue: 0.42, alpha: 1),
                        NSColor(red: 0.07, green: 0.05, blue: 0.16, alpha: 1)])!.draw(in: path, angle: -70)
    ctx.saveGState(); path.addClip()

    func circle(_ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
    let r = s * 0.27
    // Ripples, as when speaking
    for (k, a) in [(1, 0.55), (2, 0.28), (3, 0.12)] as [(CGFloat, CGFloat)] {
        let ring = circle(r + k * s * 0.062)
        ring.lineWidth = s * 0.012
        bright.withAlphaComponent(a).setStroke(); ring.stroke()
    }
    // Disc with purple glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.07, color: bright.withAlphaComponent(0.95).cgColor)
    NSColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1).setFill(); circle(r).fill()
    ctx.restoreGState()
    let edge = circle(r - s * 0.005); edge.lineWidth = s * 0.02
    NSColor(red: 0.66, green: 0.52, blue: 1, alpha: 1).setStroke(); edge.stroke()
    ctx.restoreGState()

    // Mic
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.27, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { rect in
            sym.draw(in: rect); NSColor.white.set(); rect.fill(using: .sourceAtop); return true
        }
        let w = tinted.size.width, h = tinted.size.height
        tinted.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
