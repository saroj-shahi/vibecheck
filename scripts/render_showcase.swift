// Renders the Agents showcase banner (`docs/screenshots/showcase-agents.png`) and the balanced 6-module
// overview (`docs/screenshots/modules.png`) from the committed screenshots.
// Run from repo root: swift scripts/render_showcase.swift
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let black = rgb(0x080808), mint = rgb(0x3DE0B5), sky = rgb(0x36B6F2), violet = rgb(0x8B6CFF),
    cloud = rgb(0xF5F7FF), haze = rgb(0xAEB4D6)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

func bodyFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func savePNG(_ image: NSImage, to path: String) {
    let w = Int(image.size.width), h = Int(image.size.height)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func drawGridBackground(w: CGFloat, h: CGFloat, glowA: (CGPoint, NSColor, CGFloat), glowB: (CGPoint, NSColor, CGFloat)? = nil) {
    let ctx = NSGraphicsContext.current!.cgContext
    black.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.055).cgColor); ctx.setLineWidth(1)
    for x in stride(from: 0, through: w, by: 40) { ctx.stroke(CGRect(x: x + 0.5, y: 0, width: 0, height: h)) }
    for y in stride(from: 0, through: h, by: 40) { ctx.stroke(CGRect(x: 0, y: y + 0.5, width: w, height: 0)) }
    NSGradient(starting: glowA.1, ending: glowA.1.withAlphaComponent(0))!
        .draw(fromCenter: glowA.0, radius: 0, toCenter: glowA.0, radius: glowA.2, options: [])
    if let g = glowB {
        NSGradient(starting: g.1, ending: g.1.withAlphaComponent(0))!
            .draw(fromCenter: g.0, radius: 0, toCenter: g.0, radius: g.2, options: [])
    }
}

func drawGradientText(_ text: String, font: NSFont, at origin: CGPoint, colors: [NSColor]) {
    let ctx = NSGraphicsContext.current!.cgContext
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: cloud])
    let size = attr.size()
    let rect = NSRect(origin: origin, size: size)
    let mask = NSImage(size: size, flipped: true) { _ in attr.draw(at: .zero); return true }
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    let local = CGRect(origin: .zero, size: size)
    ctx.clip(to: local, mask: mask.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    NSGradient(colors: colors)!.draw(in: local, angle: 0)
    ctx.restoreGState()
}

// MARK: 1. AI Agents showcase (2000×1040)

do {
    let W: CGFloat = 2000, H: CGFloat = 1040
    let agentsShot = NSImage(contentsOfFile: "docs/screenshots/agents.png")!
    let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        drawGridBackground(
            w: W, h: H,
            glowA: (CGPoint(x: W * 0.78, y: H * 0.45), violet.withAlphaComponent(0.22), W * 0.40),
            glowB: (CGPoint(x: W * 0.22, y: H * 0.75), sky.withAlphaComponent(0.14), W * 0.32)
        )

        // Real agents screenshot on the right
        let shotH: CGFloat = 880
        let shotW = (shotH * agentsShot.size.width / agentsShot.size.height).rounded()
        let shotRect = NSRect(x: W - shotW - 150, y: (H - shotH) / 2, width: shotW, height: shotH)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 28), blur: 84, color: NSColor.black.withAlphaComponent(0.65).cgColor)
        agentsShot.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ctx.restoreGState()

        let left: CGFloat = 136
        // Eyebrow pill
        let eyebrow = NSAttributedString(string: "100% LOCAL LOGS · ZERO CLOUD",
                                         attributes: [.font: rounded(22, .bold), .foregroundColor: mint, .kern: 1.4])
        eyebrow.draw(at: CGPoint(x: left, y: 120))

        NSAttributedString(string: "Track every AI agent",
                           attributes: [.font: rounded(76, .bold), .foregroundColor: cloud])
            .draw(at: CGPoint(x: left, y: 168))
        drawGradientText("from your menu bar.", font: rounded(76, .bold), at: CGPoint(x: left, y: 256), colors: [mint, sky, violet])

        let body = NSAttributedString(
            string: "Tokens today, 24-hour and 7-day charts, live session pace,\nrun-out forecasts, and automatic keep-awake while agents run.",
            attributes: [.font: bodyFont(28, .regular), .foregroundColor: haze])
        body.draw(at: CGPoint(x: left, y: 374))

        // Supported agents pills (including Antigravity!)
        let agents: [(String, NSColor)] = [
            ("Claude Code", rgb(0xD97757)),
            ("Codex", rgb(0x10A37F)),
            ("GitHub Copilot", rgb(0x8957E5)),
            ("OpenCode", rgb(0x8E8E93)),
            ("Antigravity", rgb(0x4285F4)),
        ]
        var x = left, y: CGFloat = 492
        let maxRight: CGFloat = shotRect.minX - 90
        for (name, dotColor) in agents {
            let t = NSAttributedString(string: name, attributes: [.font: rounded(26, .semibold), .foregroundColor: cloud])
            let pw = t.size().width + 60, ph: CGFloat = 52
            if x + pw > maxRight { x = left; y += ph + 16 }
            let pill = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: pw, height: ph), xRadius: ph / 2, yRadius: ph / 2)
            NSColor.white.withAlphaComponent(0.08).setFill(); pill.fill()
            dotColor.withAlphaComponent(0.45).setStroke(); pill.lineWidth = 1.6; pill.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: x + 20, y: y + (ph - 14) / 2, width: 14, height: 14))
            dotColor.setFill(); dot.fill()
            t.draw(at: CGPoint(x: x + 44, y: y + (ph - t.size().height) / 2))
            x += pw + 14
        }

        // Three highlight rows
        let bullets: [(String, String, NSColor)] = [
            ("Live pace & run-out forecast", "Know whether your 5-hour or weekly window will last until reset.", mint),
            ("Agent watch & keep-awake", "Stops idle sleep while an agent is writing, notifies when long runs finish.", sky),
            ("Vibe Hooks (zero polling)", "Any CLI can drop a JSON pill in ~/.config/vibecheck/hooks/ and pulse the ring.", violet),
        ]
        var by = y + 104
        for (title, desc, accent) in bullets {
            let bar = NSBezierPath(roundedRect: NSRect(x: left, y: by + 6, width: 6, height: 64), xRadius: 3, yRadius: 3)
            accent.setFill(); bar.fill()
            NSAttributedString(string: title, attributes: [.font: rounded(28, .semibold), .foregroundColor: cloud])
                .draw(at: CGPoint(x: left + 24, y: by))
            NSAttributedString(string: desc, attributes: [.font: bodyFont(22, .regular), .foregroundColor: haze])
                .draw(at: CGPoint(x: left + 24, y: by + 38))
            by += 102
        }
        return true
    }
    savePNG(img, to: "docs/screenshots/showcase-agents.png")
}

// MARK: 2. Balanced 6-module showcase (2000×1520, nothing awkwardly clipped)

do {
    let W: CGFloat = 2000, H: CGFloat = 1520
    let shotNames = [
        ["cpu.png", "gpu.png"],
        ["memory.png", "battery.png"],
        ["network.png", "sensors.png"],
    ]
    let shots = shotNames.map { col in col.map { NSImage(contentsOfFile: "docs/screenshots/\($0)")! } }
    let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        drawGridBackground(
            w: W, h: H,
            glowA: (CGPoint(x: W * 0.5, y: H * 0.32), mint.withAlphaComponent(0.18), W * 0.45),
            glowB: (CGPoint(x: W * 0.82, y: H * 0.78), sky.withAlphaComponent(0.12), W * 0.35)
        )
        let padX: CGFloat = 86, gapX: CGFloat = 48, gapY: CGFloat = 44
        let colW: CGFloat = (W - padX * 2 - gapX * 2) / 3
        let staggers: [CGFloat] = [56, 108, 72]
        for (c, col) in shots.enumerated() {
            let x = padX + CGFloat(c) * (colW + gapX)
            var y = staggers[c]
            for shot in col {
                let h = (colW * shot.size.height / shot.size.width).rounded()
                let rect = NSRect(x: x, y: y, width: colW, height: h)
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: 22), blur: 56, color: NSColor.black.withAlphaComponent(0.6).cgColor)
                shot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                ctx.restoreGState()
                y += h + gapY
            }
        }
        // Gentle bottom vignette
        let fadeH: CGFloat = 190
        NSGradient(starting: black.withAlphaComponent(0), ending: black)!
            .draw(in: NSRect(x: 0, y: H - fadeH, width: W, height: fadeH), angle: 90)
        return true
    }
    savePNG(img, to: "docs/screenshots/modules.png")
}
