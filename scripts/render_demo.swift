// Renders the VibeCheck walkthrough video (`docs/screenshots/demo.mp4`, 1280×720 @ 30 fps) and looping README GIF
// (`docs/screenshots/demo.gif`, 960×540 @ 18 fps) from the real screenshots and BRAND.md motion rules.
// Requires ffmpeg on PATH. Run from repo root: swift scripts/render_demo.swift
import AppKit
import Foundation

let W = 1280, H = 720
let FPS = 30
let DURATION: Double = 14.0
let TOTAL_FRAMES = Int(DURATION * Double(FPS))

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let black = rgb(0x080808), mint = rgb(0x3DE0B5), sky = rgb(0x36B6F2), violet = rgb(0x8B6CFF),
    cloud = rgb(0xF5F7FF), haze = rgb(0xAEB4D6), mid = rgb(0xFFC542), cooked = rgb(0xFF5A5F)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

func uiFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func mono(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(x, lo), hi) }
func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}
func easeOutCubic(_ x: Double) -> Double {
    let t = clamp(x)
    return 1 - pow(1 - t, 3)
}
func easeOutBack(_ x: Double) -> Double {
    let t = clamp(x), c1 = 1.4, c3 = c1 + 1
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
}
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func lerpColor(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
    let k = CGFloat(clamp(t))
    let c1 = a.usingColorSpace(.sRGB)!, c2 = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: c1.redComponent + (c2.redComponent - c1.redComponent) * k,
                   green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * k,
                   blue: c1.blueComponent + (c2.blueComponent - c1.blueComponent) * k,
                   alpha: c1.alphaComponent + (c2.alphaComponent - c1.alphaComponent) * k)
}

// Load real assets once
func loadImage(_ path: String) -> NSImage {
    guard let img = NSImage(contentsOfFile: path) else { fatalError("Missing asset: \(path)") }
    return img
}

let iconImg = loadImage("branding/png/icon-512.png")
let deckImg = loadImage("docs/screenshots/deck.png")
let paletteImg = loadImage("docs/screenshots/palette.png")
let cpuImg = loadImage("docs/screenshots/cpu.png")
let memImg = loadImage("docs/screenshots/memory.png")
let agentsImg = loadImage("docs/screenshots/agents.png")

// Pre-render the static grid background for fast compositing
let gridBG: NSImage = {
    let w = CGFloat(W), h = CGFloat(H)
    return NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        black.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.05).cgColor); ctx.setLineWidth(1)
        for x in stride(from: 0, through: w, by: 36) { ctx.stroke(CGRect(x: x + 0.5, y: 0, width: 0, height: h)) }
        for y in stride(from: 0, through: h, by: 36) { ctx.stroke(CGRect(x: 0, y: y + 0.5, width: w, height: 0)) }
        return true
    }
}()

func drawGlow(_ center: CGPoint, color: NSColor, radius: CGFloat) {
    NSGradient(starting: color, ending: color.withAlphaComponent(0))!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func drawGradientText(_ text: String, font: NSFont, at origin: CGPoint, colors: [NSColor], alpha: CGFloat = 1) {
    guard alpha > 0.01 else { return }
    let ctx = NSGraphicsContext.current!.cgContext
    let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: cloud])
    let size = attr.size()
    let rect = NSRect(origin: origin, size: size)
    let mask = NSImage(size: size, flipped: true) { _ in attr.draw(at: .zero); return true }
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    let local = CGRect(origin: .zero, size: size)
    ctx.clip(to: local, mask: mask.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    NSGradient(colors: colors)!.draw(in: local, angle: 0)
    ctx.restoreGState()
}

func drawRing(center: CGPoint, radius: CGFloat, lineWidth: CGFloat, fill: Double, color: NSColor, alpha: CGFloat = 1, checkProgress: Double = 0) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    color.withAlphaComponent(0.18).setStroke()
    track.stroke()

    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: -90, endAngle: -90 + 360 * CGFloat(fill) * 0.999, clockwise: false)
    arc.lineWidth = lineWidth
    arc.lineCapStyle = .round
    color.setStroke()
    arc.stroke()

    if checkProgress > 0.01 {
        let p = CGFloat(clamp(checkProgress))
        let s = radius * 0.42
        let p1 = CGPoint(x: center.x - s * 0.85, y: center.y + s * 0.05)
        let p2 = CGPoint(x: center.x - s * 0.15, y: center.y + s * 0.72)
        let p3 = CGPoint(x: center.x + s * 0.95, y: center.y - s * 0.62)
        let check = NSBezierPath()
        check.move(to: p1)
        if p < 0.45 {
            let k = p / 0.45
            check.line(to: CGPoint(x: p1.x + (p2.x - p1.x) * k, y: p1.y + (p2.y - p1.y) * k))
        } else {
            check.line(to: p2)
            let k = (p - 0.45) / 0.55
            check.line(to: CGPoint(x: p2.x + (p3.x - p2.x) * k, y: p2.y + (p3.y - p2.y) * k))
        }
        check.lineWidth = lineWidth * 0.72
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        mint.setStroke()
        check.stroke()
    }
    ctx.restoreGState()
}

func drawShadowed(_ image: NSImage, in rect: NSRect, alpha: CGFloat = 1, blur: CGFloat = 46) {
    guard alpha > 0.01 else { return }
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: blur, color: NSColor.black.withAlphaComponent(0.65).cgColor)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    ctx.restoreGState()
}

func drawPill(_ text: String, at origin: CGPoint, accent: NSColor, active: Bool, alpha: CGFloat = 1) {
    guard alpha > 0.01 else { return }
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)
    let attr = NSAttributedString(string: text, attributes: [
        .font: rounded(17, .semibold),
        .foregroundColor: active ? cloud : haze.withAlphaComponent(0.85),
    ])
    let sz = attr.size()
    let rect = NSRect(x: origin.x, y: origin.y, width: sz.width + 44, height: 38)
    let path = NSBezierPath(roundedRect: rect, xRadius: 19, yRadius: 19)
    (active ? accent.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.06)).setFill()
    path.fill()
    (active ? accent.withAlphaComponent(0.6) : NSColor.white.withAlphaComponent(0.12)).setStroke()
    path.lineWidth = 1.4
    path.stroke()
    let dot = NSBezierPath(ovalIn: NSRect(x: rect.minX + 14, y: rect.midY - 4.5, width: 9, height: 9))
    (active ? accent : haze.withAlphaComponent(0.45)).setFill(); dot.fill()
    attr.draw(at: CGPoint(x: rect.minX + 31, y: rect.midY - sz.height / 2))
    ctx.restoreGState()
}

// MARK: - Scenes

func drawScene1(t: Double, alpha: CGFloat) {
    let w = CGFloat(W), h = CGFloat(H)
    // 0.0-0.85: Vibing, 0.85-1.85: Mid, 1.85-2.65: Cooked, 2.65-3.2: Recovery -> Vibing
    let toMid = smoothstep(0.82, 1.08, t)
    let toCooked = smoothstep(1.82, 2.08, t)
    let toRecover = smoothstep(2.62, 2.88, t)

    var fill = lerp(1.0, 0.66, toMid)
    fill = lerp(fill, 0.33, toCooked)
    fill = lerp(fill, 1.0, toRecover)

    var ringColor = lerpColor(mint, mid, toMid)
    ringColor = lerpColor(ringColor, cooked, toCooked)
    ringColor = lerpColor(ringColor, mint, toRecover)

    let checkProg = smoothstep(2.75, 3.05, t)

    let stateTitle: String
    let verdict: String
    let badge: String?
    if t < 0.92 {
        stateTitle = "Vibing"
        verdict = "Your Mac is vibing. Nothing's working hard."
        badge = nil
    } else if t < 1.92 {
        stateTitle = "Mid"
        verdict = "Kinda mid: memory is getting tight. Chrome grew 2.4 GB."
        badge = "Memory"
    } else if t < 2.72 {
        stateTitle = "Cooked"
        verdict = "Your Mac is cooked: CPU pinned at 96%. Xcode is the loudest."
        badge = "CPU 96%"
    } else {
        stateTitle = "Vibing"
        verdict = "Your Mac is vibing again. All clear."
        badge = nil
    }

    drawGlow(CGPoint(x: w * 0.5, y: h * 0.48), color: ringColor.withAlphaComponent(0.22 * alpha), radius: 380)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)

    // Simulated dark macOS menu bar pill at top
    let barRect = NSRect(x: 90, y: 46, width: w - 180, height: 42)
    let barPath = NSBezierPath(roundedRect: barRect, xRadius: 12, yRadius: 12)
    NSColor(white: 0.12, alpha: 0.88).setFill(); barPath.fill()
    NSColor.white.withAlphaComponent(0.10).setStroke(); barPath.lineWidth = 1; barPath.stroke()

    let leftMenu = NSAttributedString(string: "   Finder   File   Edit   View", attributes: [
        .font: rounded(14, .medium), .foregroundColor: cloud.withAlphaComponent(0.65),
    ])
    leftMenu.draw(at: CGPoint(x: barRect.minX + 18, y: barRect.midY - leftMenu.size().height / 2))

    // Right side of menu bar: VibeCheck ring + optional culprit badge + time
    let timeStr = NSAttributedString(string: "Tue 10:24 AM", attributes: [
        .font: rounded(14, .medium), .foregroundColor: cloud.withAlphaComponent(0.8),
    ])
    let timeX = barRect.maxX - timeStr.size().width - 18
    timeStr.draw(at: CGPoint(x: timeX, y: barRect.midY - timeStr.size().height / 2))

    var ringRightX = timeX - 24
    if let badge {
        let bAttr = NSAttributedString(string: badge, attributes: [.font: rounded(13, .semibold), .foregroundColor: ringColor])
        let bSize = bAttr.size()
        let bRect = NSRect(x: ringRightX - bSize.width - 16, y: barRect.midY - 12, width: bSize.width + 16, height: 24)
        let bp = NSBezierPath(roundedRect: bRect, xRadius: 12, yRadius: 12)
        ringColor.withAlphaComponent(0.18).setFill(); bp.fill()
        bAttr.draw(at: CGPoint(x: bRect.minX + 8, y: bRect.midY - bSize.height / 2))
        ringRightX = bRect.minX - 10
    }
    let menuRingColor = badge == nil ? cloud : ringColor
    drawRing(center: CGPoint(x: ringRightX - 9, y: barRect.midY), radius: 8.5, lineWidth: 2.6, fill: fill, color: menuRingColor)

    // Eyebrow
    let eye = NSAttributedString(string: "GLANCE · ONE RING IN YOUR MENU BAR",
                                 attributes: [.font: rounded(15, .bold), .foregroundColor: mint, .kern: 1.5])
    eye.draw(at: CGPoint(x: (w - eye.size().width) / 2, y: 148))

    // Large animated hero ring
    let ringCenter = CGPoint(x: w * 0.5, y: 318)
    drawRing(center: ringCenter, radius: 92, lineWidth: 22, fill: fill, color: ringColor, checkProgress: checkProg)

    // State title
    let titleAttr = NSAttributedString(string: stateTitle, attributes: [.font: rounded(62, .bold), .foregroundColor: cloud])
    titleAttr.draw(at: CGPoint(x: (w - titleAttr.size().width) / 2, y: 446))

    // Verdict subtitle
    let verdAttr = NSAttributedString(string: verdict, attributes: [.font: rounded(26, .medium), .foregroundColor: haze])
    verdAttr.draw(at: CGPoint(x: (w - verdAttr.size().width) / 2, y: 534))

    // State legend dots at bottom (centered using exact pill widths)
    let states: [(String, NSColor, Bool)] = [
        ("Vibing", mint, t < 0.92 || t >= 2.72),
        ("Mid", mid, t >= 0.92 && t < 1.92),
        ("Cooked", cooked, t >= 1.92 && t < 2.72),
    ]
    let pillWidths = states.map { name, _, _ -> CGFloat in
        NSAttributedString(string: name, attributes: [.font: rounded(17, .semibold)]).size().width + 44
    }
    let gap: CGFloat = 16
    let totalLegendW = pillWidths.reduce(0, +) + gap * CGFloat(states.count - 1)
    var lx = (w - totalLegendW) / 2
    for (idx, item) in states.enumerated() {
        drawPill(item.0, at: CGPoint(x: lx, y: 604), accent: item.1, active: item.2, alpha: alpha)
        lx += pillWidths[idx] + gap
    }

    ctx.restoreGState()
}

func drawScene2(t: Double, alpha: CGFloat) {
    let w = CGFloat(W), h = CGFloat(H)
    let enter = easeOutBack(clamp(t / 0.55))
    drawGlow(CGPoint(x: w * 0.72, y: h * 0.48), color: mint.withAlphaComponent(0.20 * alpha), radius: 400)
    drawGlow(CGPoint(x: w * 0.18, y: h * 0.72), color: sky.withAlphaComponent(0.10 * alpha), radius: 280)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)

    // Left copy
    let left: CGFloat = 94
    NSAttributedString(string: "01 · THE DECK", attributes: [.font: rounded(15, .bold), .foregroundColor: mint, .kern: 1.5])
        .draw(at: CGPoint(x: left, y: 122))
    NSAttributedString(string: "Verdict first.", attributes: [.font: rounded(56, .bold), .foregroundColor: cloud])
        .draw(at: CGPoint(x: left, y: 158))
    drawGradientText("Cockpit second.", font: rounded(56, .bold), at: CGPoint(x: left, y: 224), colors: [mint, sky, violet], alpha: alpha)
    NSAttributedString(string: "One click opens a calm glass sheet with\nquick controls, a live summary, and tiles.",
                       attributes: [.font: uiFont(22, .regular), .foregroundColor: haze])
        .draw(at: CGPoint(x: left, y: 308))

    // Staggered callout pills
    let activeIdx = t < 1.1 ? 0 : (t < 2.1 ? 1 : 2)
    let items: [(String, NSColor)] = [
        ("Verdict & culprit in plain words", mint),
        ("Mic, Bluetooth, Volume & Brightness", sky),
        ("Live tiles & 2×2 summary card", violet),
    ]
    for (i, item) in items.enumerated() {
        let pAlpha = CGFloat(smoothstep(0.18 + Double(i) * 0.14, 0.42 + Double(i) * 0.14, t)) * alpha
        drawPill(item.0, at: CGPoint(x: left, y: 404 + CGFloat(i) * 54), accent: item.1, active: i == activeIdx, alpha: pAlpha)
    }

    // Floating deck screenshot on the right
    let deckH: CGFloat = 626
    let deckW = (deckH * deckImg.size.width / deckImg.size.height).rounded()
    let dropOffset = CGFloat((1 - enter) * -32)
    let deckRect = NSRect(x: w - deckW - 140, y: (h - deckH) / 2 + dropOffset, width: deckW, height: deckH)
    drawShadowed(deckImg, in: deckRect, alpha: alpha)

    ctx.restoreGState()
}

func drawScene3(t: Double, alpha: CGFloat) {
    let w = CGFloat(W), h = CGFloat(H)
    // Cycle focus across CPU (0..1.05), Memory (1.05..2.1), Agents (2.1..3.2)
    let focusIndex = t < 1.05 ? 0 : (t < 2.1 ? 1 : 2)
    let glowColors = [sky, violet, mint]
    let activeGlow = glowColors[focusIndex]
    drawGlow(CGPoint(x: w * 0.70, y: h * 0.50), color: activeGlow.withAlphaComponent(0.20 * alpha), radius: 420)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)

    let left: CGFloat = 94
    NSAttributedString(string: "02 · MODULES & AI AGENTS", attributes: [.font: rounded(15, .bold), .foregroundColor: sky, .kern: 1.5])
        .draw(at: CGPoint(x: left, y: 122))
    NSAttributedString(string: "Answers, not", attributes: [.font: rounded(56, .bold), .foregroundColor: cloud])
        .draw(at: CGPoint(x: left, y: 158))
    drawGradientText("walls of numbers.", font: rounded(56, .bold), at: CGPoint(x: left, y: 224), colors: [mint, sky, violet], alpha: alpha)
    NSAttributedString(string: "Every module unfolds with a chart and\nwho's responsible — plus local AI tracking.",
                       attributes: [.font: uiFont(22, .regular), .foregroundColor: haze])
        .draw(at: CGPoint(x: left, y: 308))

    let pills: [(String, NSColor)] = [
        ("CPU · Vibe Replay & per-core bars", sky),
        ("Memory · Apps folded, not helpers", violet),
        ("AI Agents · Claude, Codex, Antigravity…", mint),
    ]
    for (i, p) in pills.enumerated() {
        drawPill(p.0, at: CGPoint(x: left, y: 404 + CGFloat(i) * 54), accent: p.1, active: i == focusIndex, alpha: alpha)
    }

    // Smoothly carousel the 3 panels on the right
    let panels = [cpuImg, memImg, agentsImg]
    let posProgress: Double
    if t < 1.05 {
        posProgress = 0
    } else if t < 2.1 {
        posProgress = easeOutCubic((t - 1.05) / 0.42)
    } else {
        posProgress = 1 + easeOutCubic((t - 2.1) / 0.42)
    }

    let centerX: CGFloat = w - 315
    // Draw back-to-front so the active card sits cleanly on top
    let order = [0, 1, 2].sorted { abs(Double($0) - posProgress) > abs(Double($1) - posProgress) }
    for idx in order {
        let dist = Double(idx) - posProgress
        let absD = abs(dist)
        let cardScale = CGFloat(max(0.78, 1.0 - absD * 0.14))
        let baseH: CGFloat = 590
        let shot = panels[idx]
        let cardH = baseH * cardScale
        let cardW = (cardH * shot.size.width / shot.size.height).rounded()
        let dx = CGFloat(dist) * 125
        let rect = NSRect(x: centerX - cardW / 2 + dx, y: (h - cardH) / 2 + CGFloat(absD * 14), width: cardW, height: cardH)
        let cardAlpha = CGFloat(max(0.28, 1.0 - absD * 0.55)) * alpha
        drawShadowed(shot, in: rect, alpha: cardAlpha, blur: absD < 0.2 ? 52 : 28)
    }

    ctx.restoreGState()
}

func drawScene4(t: Double, alpha: CGFloat) {
    let w = CGFloat(W), h = CGFloat(H)
    let enter = easeOutBack(clamp(t / 0.50))
    drawGlow(CGPoint(x: w * 0.72, y: h * 0.50), color: violet.withAlphaComponent(0.22 * alpha), radius: 380)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)

    let left: CGFloat = 94
    NSAttributedString(string: "03 · COMMAND PALETTE", attributes: [.font: rounded(15, .bold), .foregroundColor: violet, .kern: 1.5])
        .draw(at: CGPoint(x: left, y: 132))
    NSAttributedString(string: "Press ⌘K.", attributes: [.font: rounded(56, .bold), .foregroundColor: cloud])
        .draw(at: CGPoint(x: left, y: 168))
    drawGradientText("Act in one second.", font: rounded(56, .bold), at: CGPoint(x: left, y: 234), colors: [mint, sky, violet], alpha: alpha)
    NSAttributedString(string: "Start typing anywhere in the deck.\nNever steals focus from your active app.",
                       attributes: [.font: uiFont(22, .regular), .foregroundColor: haze])
        .draw(at: CGPoint(x: left, y: 318))

    // Animated simulated search pill
    let queries = ["share vibe card", "keep awake 1h", "quit heavy app"]
    let qIdx = min(queries.count - 1, Int(t / 0.85))
    let qLocal = (t - Double(qIdx) * 0.85) / 0.45
    let fullText = queries[qIdx]
    let charCount = Int(clamp(qLocal) * Double(fullText.count))
    let shown = String(fullText.prefix(charCount))

    let searchRect = NSRect(x: left, y: 416, width: 410, height: 50)
    let sp = NSBezierPath(roundedRect: searchRect, xRadius: 12, yRadius: 12)
    NSColor.white.withAlphaComponent(0.08).setFill(); sp.fill()
    sky.withAlphaComponent(0.55).setStroke(); sp.lineWidth = 1.6; sp.stroke()
    let cursor = Int(t * 4) % 2 == 0 ? "│" : ""
    let qAttr = NSAttributedString(string: "⌘K   \(shown)\(cursor)", attributes: [.font: mono(20, .medium), .foregroundColor: cloud])
    qAttr.draw(at: CGPoint(x: searchRect.minX + 18, y: searchRect.midY - qAttr.size().height / 2))

    // Palette screenshot on right
    let palH: CGFloat = 530
    let palW = (palH * paletteImg.size.width / paletteImg.size.height).rounded()
    let scale = CGFloat(0.92 + 0.08 * enter)
    let rw = palW * scale, rh = palH * scale
    let palRect = NSRect(x: w - rw - 110, y: (h - rh) / 2, width: rw, height: rh)
    drawShadowed(paletteImg, in: palRect, alpha: alpha)

    ctx.restoreGState()
}

func drawScene5(t: Double, alpha: CGFloat) {
    let w = CGFloat(W), h = CGFloat(H)
    let enter = easeOutCubic(clamp(t / 0.45))
    drawGlow(CGPoint(x: w * 0.5, y: h * 0.42), color: mint.withAlphaComponent(0.22 * alpha), radius: 380)
    drawGlow(CGPoint(x: w * 0.62, y: h * 0.58), color: violet.withAlphaComponent(0.16 * alpha), radius: 300)

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setAlpha(alpha)

    let iconSize: CGFloat = 152
    let yShift = CGFloat((1 - enter) * 18)
    iconImg.draw(in: NSRect(x: (w - iconSize) / 2, y: 120 + yShift, width: iconSize, height: iconSize),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

    // Centered "VibeCheck" wordmark
    let vibePart = NSAttributedString(string: "Vibe", attributes: [.font: rounded(72, .bold), .foregroundColor: cloud])
    let checkPart = NSAttributedString(string: "Check", attributes: [.font: rounded(72, .bold), .foregroundColor: cloud])
    let totalW = vibePart.size().width + checkPart.size().width
    let wordX = (w - totalW) / 2
    vibePart.draw(at: CGPoint(x: wordX, y: 294 + yShift))
    drawGradientText("Check", font: rounded(72, .bold), at: CGPoint(x: wordX + vibePart.size().width, y: 294 + yShift),
                     colors: [mint, sky, violet], alpha: alpha)

    let sub = NSAttributedString(string: "Mac health in one ring · Free & open source (GPL-3.0)",
                                 attributes: [.font: rounded(26, .medium), .foregroundColor: haze])
    sub.draw(at: CGPoint(x: (w - sub.size().width) / 2, y: 396 + yShift))

    // Install command pill
    let cmd = NSAttributedString(string: "brew install --cask saroj-shahi/tap/vibecheck",
                                 attributes: [.font: mono(19, .medium), .foregroundColor: mint])
    let cSz = cmd.size()
    let cRect = NSRect(x: (w - cSz.width - 48) / 2, y: 472 + yShift, width: cSz.width + 48, height: 50)
    let cp = NSBezierPath(roundedRect: cRect, xRadius: 25, yRadius: 25)
    NSColor.white.withAlphaComponent(0.07).setFill(); cp.fill()
    mint.withAlphaComponent(0.38).setStroke(); cp.lineWidth = 1.5; cp.stroke()
    cmd.draw(at: CGPoint(x: cRect.minX + 24, y: cRect.midY - cSz.height / 2))

    ctx.restoreGState()
}

// MARK: - Pipe raw RGBA frames to ffmpeg

let mp4Path = "docs/screenshots/demo.mp4"
let gifPath = "docs/screenshots/demo.gif"

let ffmpegPath = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")
    ? "/opt/homebrew/bin/ffmpeg" : "/usr/local/bin/ffmpeg"
guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
    fatalError("ffmpeg not found (install with: brew install ffmpeg)")
}

let pipe = Pipe()
let ffmpeg = Process()
ffmpeg.executableURL = URL(fileURLWithPath: ffmpegPath)
ffmpeg.arguments = [
    "-y", "-loglevel", "error",
    "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(W)x\(H)", "-r", "\(FPS)", "-i", "pipe:0",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "slow", "-crf", "20", "-movflags", "+faststart",
    mp4Path,
]
ffmpeg.standardInput = pipe
try! ffmpeg.run()

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: W * 4, bitsPerPixel: 32)!
let frameBytes = W * H * 4

let scenes: [(start: Double, end: Double, draw: (Double, CGFloat) -> Void)] = [
    (0.0, 3.2, drawScene1),
    (3.2, 6.4, drawScene2),
    (6.4, 9.6, drawScene3),
    (9.6, 12.2, drawScene4),
    (12.2, 14.0, drawScene5),
]
let fade = 0.24

print("Rendering \(TOTAL_FRAMES) frames at \(W)x\(H) (\(FPS) fps)...")
for f in 0..<TOTAL_FRAMES {
    autoreleasepool {
        let t = Double(f) / Double(FPS)
        let img = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
            gridBG.draw(in: NSRect(x: 0, y: 0, width: W, height: H), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
            for s in scenes {
                let inStart = s.start - fade
                let outEnd = s.end + fade
                guard t >= inStart && t <= outEnd else { continue }
                let aIn = s.start == 0 ? 1.0 : smoothstep(inStart, s.start + fade * 0.5, t)
                let aOut = s.end == DURATION ? (1.0 - smoothstep(DURATION - 0.25, DURATION, t)) : (1.0 - smoothstep(s.end - fade * 0.5, outEnd, t))
                let a = CGFloat(min(aIn, aOut))
                if a > 0.01 { s.draw(max(0, t - s.start), a) }
            }
            // Subtle bottom progress bar
            let progW = CGFloat(t / DURATION) * CGFloat(W)
            NSGradient(colors: [mint, sky, violet])!.draw(in: NSRect(x: 0, y: CGFloat(H) - 3, width: progW, height: 3), angle: 0)
            return true
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
        NSGraphicsContext.restoreGraphicsState()
        let data = Data(bytesNoCopy: rep.bitmapData!, count: frameBytes, deallocator: .none)
        try! pipe.fileHandleForWriting.write(contentsOf: data)
    }
}
try! pipe.fileHandleForWriting.close()
ffmpeg.waitUntilExit()
guard ffmpeg.terminationStatus == 0 else { fatalError("ffmpeg mp4 encode failed") }
print("wrote \(mp4Path)")

// Convert MP4 → compact two-pass palette-optimized looping GIF for GitHub README autoplay
let palettePath = FileManager.default.temporaryDirectory.appendingPathComponent("vc-demo-palette.png").path
defer { try? FileManager.default.removeItem(atPath: palettePath) }

let palProc = Process()
palProc.executableURL = URL(fileURLWithPath: ffmpegPath)
palProc.standardInput = FileHandle.nullDevice
palProc.arguments = [
    "-nostdin", "-y", "-loglevel", "error", "-i", mp4Path,
    "-vf", "fps=12,scale=760:-1:flags=lanczos,palettegen=max_colors=96",
    "-frames:v", "1", "-update", "1",
    palettePath,
]
try! palProc.run()
palProc.waitUntilExit()
guard palProc.terminationStatus == 0 else { fatalError("ffmpeg palettegen failed") }

let gifProc = Process()
gifProc.executableURL = URL(fileURLWithPath: ffmpegPath)
gifProc.standardInput = FileHandle.nullDevice
gifProc.arguments = [
    "-nostdin", "-y", "-loglevel", "error", "-i", mp4Path, "-i", palettePath,
    "-lavfi", "fps=12,scale=760:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
    "-loop", "0",
    gifPath,
]
try! gifProc.run()
gifProc.waitUntilExit()
guard gifProc.terminationStatus == 0 else { fatalError("ffmpeg gif encode failed") }
print("wrote \(gifPath)")
