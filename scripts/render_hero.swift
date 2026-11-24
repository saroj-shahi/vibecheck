// Renders the README hero: the real deck screenshot on the near-black grid background, beside the slogan and the
// three ring states. Run: swift scripts/render_hero.swift  →  docs/screenshots/hero.png
import AppKit

let W: CGFloat = 2000, H: CGFloat = 1100
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let ink = rgb(0x0B0E22), dusk = rgb(0x252A52), mint = rgb(0x3DE0B5), sky = rgb(0x36B6F2),
    violet = rgb(0x8B6CFF), cloud = rgb(0xF5F7FF), haze = rgb(0xAEB4D6), mid = rgb(0xFFC542), cooked = rgb(0xFF5A5F)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

let deck = NSImage(contentsOfFile: "docs/screenshots/deck.png")!
let icon = NSImage(contentsOfFile: "branding/png/icon-512.png")!

let image = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext

    // Background: near-black, a faint 40 px grid, a mint glow behind the deck and a fade from the left
    // (same style as the social card).
    let black = rgb(0x080808)
    black.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.06).cgColor); ctx.setLineWidth(1)
    for x in stride(from: 0, through: W, by: 40) { ctx.stroke(CGRect(x: x + 0.5, y: 0, width: 0, height: H)) }
    for y in stride(from: 0, through: H, by: 40) { ctx.stroke(CGRect(x: 0, y: y + 0.5, width: W, height: 0)) }
    let glowCenter = CGPoint(x: W * 0.8, y: H * 0.42)
    NSGradient(starting: mint.withAlphaComponent(0.22), ending: mint.withAlphaComponent(0))!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: W * 0.44, options: [])
    let accentGlow = CGPoint(x: W * 0.16, y: H * 0.25)
    NSGradient(starting: violet.withAlphaComponent(0.14), ending: violet.withAlphaComponent(0))!
        .draw(fromCenter: accentGlow, radius: 0, toCenter: accentGlow, radius: W * 0.28, options: [])
    NSGradient(colors: [black, black.withAlphaComponent(0.45), black.withAlphaComponent(0)], atLocations: [0, 0.5, 1],
               colorSpace: .sRGB)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 0)

    // The deck, floating on the right.
    // 930 px tall, width from the screenshot's own aspect (the deck's width changes between versions).
    let deckSize = NSSize(width: (930 * deck.size.width / deck.size.height).rounded(), height: 930)
    let deckRect = NSRect(x: W - deckSize.width - 155, y: (H - deckSize.height) / 2, width: deckSize.width, height: deckSize.height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 32), blur: 96, color: NSColor.black.withAlphaComponent(0.65).cgColor)
    deck.draw(in: deckRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    ctx.restoreGState()

    // Left column: icon, slogan, ring states, capability pills.
    let left: CGFloat = 140
    icon.draw(in: NSRect(x: left - 12, y: 148, width: 172, height: 172), from: .zero, operation: .sourceOver,
              fraction: 1, respectFlipped: true, hints: nil)

    let line1 = NSAttributedString(string: "Your Mac's mood,", attributes: [.font: rounded(94, .bold), .foregroundColor: cloud])
    line1.draw(at: NSPoint(x: left, y: 350))
    // Second line in the brand gradient (Mint → Sky → Violet), clipped to the glyphs.
    let line2 = NSAttributedString(string: "in one little ring.", attributes: [.font: rounded(94, .bold), .foregroundColor: cloud])
    let size2 = line2.size()
    let rect2 = NSRect(x: left, y: 460, width: size2.width, height: size2.height)
    let mask = NSImage(size: size2, flipped: true) { _ in line2.draw(at: .zero); return true }
    ctx.saveGState()
    // CG masks are bottom-up; undo the view's flip so the glyphs come out upright.
    ctx.translateBy(x: rect2.minX, y: rect2.maxY)
    ctx.scaleBy(x: 1, y: -1)
    let local = CGRect(origin: .zero, size: size2)
    ctx.clip(to: local, mask: mask.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    NSGradient(colors: [mint, sky, violet])!.draw(in: local, angle: 0)
    ctx.restoreGState()

    let sub = NSAttributedString(string: "Is your Mac vibing or cooked? One glance tells you.",
                                 attributes: [.font: rounded(36, .medium), .foregroundColor: haze])
    sub.draw(at: NSPoint(x: left, y: 604))

    // Ring states: full / two-thirds / one-third, as in the menu bar.
    var x = left
    for (label, color, fill) in [("Vibing", cloud, 1.0), ("Mid", mid, 2.0 / 3), ("Cooked", cooked, 1.0 / 3)] {
        let center = CGPoint(x: x + 34, y: 742)
        let track = NSBezierPath(); track.appendArc(withCenter: center, radius: 26, startAngle: 0, endAngle: 360)
        track.lineWidth = 10; color.withAlphaComponent(0.18).setStroke(); track.stroke()
        let arc = NSBezierPath()
        // Flipped context: clockwise from the top.
        arc.appendArc(withCenter: center, radius: 26, startAngle: -90, endAngle: -90 + 360 * fill * 0.999, clockwise: false)
        arc.lineWidth = 10; arc.lineCapStyle = .round; color.setStroke(); arc.stroke()
        let text = NSAttributedString(string: label, attributes: [.font: rounded(38, .semibold), .foregroundColor: cloud])
        text.draw(at: NSPoint(x: x + 82, y: 742 - text.size().height / 2))
        x += 82 + text.size().width + 66
    }

    // Subtle capability pills
    var px = left
    for pillLabel in ["macOS 14+", "11 Modules", "AI Agents", "100% Local", "GPL-3.0"] {
        let t = NSAttributedString(string: pillLabel, attributes: [.font: rounded(24, .semibold), .foregroundColor: cloud.withAlphaComponent(0.9)])
        let pw = t.size().width + 34, ph: CGFloat = 46
        let pill = NSBezierPath(roundedRect: NSRect(x: px, y: 842, width: pw, height: ph), xRadius: ph / 2, yRadius: ph / 2)
        NSColor.white.withAlphaComponent(0.08).setFill(); pill.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); pill.lineWidth = 1.5; pill.stroke()
        t.draw(at: NSPoint(x: px + 17, y: 842 + (ph - t.size().height) / 2))
        px += pw + 14
    }

    let foot = NSAttributedString(string: "Native Swift · Zero accounts · Zero tracking",
                                  attributes: [.font: rounded(26, .regular), .foregroundColor: haze.withAlphaComponent(0.75)])
    foot.draw(at: NSPoint(x: left, y: 924))
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/screenshots/hero.png"))
print("wrote docs/screenshots/hero.png")
