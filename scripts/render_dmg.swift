// Renders the DMG window background (the install screen colleagues see when they open the DMG).
// Usage (from the repo root):  swift scripts/render_dmg.swift
// Outputs, each at 1x and 2x (680×500 pt): branding/dmg/share.png (with the one-time Terminal step, for the
// un-notarized --share DMG) and branding/dmg/release.png (notarized: just drag and open). scripts/release.sh
// combines the pair into a HiDPI TIFF and places the icons on top. Layout constants here must match DMG_* in release.sh.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outDir = root.appendingPathComponent("branding/dmg")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Brand tokens (branding/BRAND.md)
func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}
let night = hex(0x0B0E22), dusk = hex(0x252A52), mint = hex(0x3DE0B5), sky = hex(0x36B6F2)
let violet = hex(0x8B6CFF), cloud = hex(0xF5F7FF), haze = hex(0xAEB4D6)
// Finder draws icon labels white in dark mode and black in light mode, whatever the background; this slate
// keeps both readable (about 4:1 against white, 5:1 against black).
let labelPlate = hex(0x717AA8)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// Layout in points, top-left origin (Finder's icon positions are icon centres in the same space).
let W: CGFloat = 680, H: CGFloat = 500
let appCenter = CGPoint(x: 180, y: 222), appsCenter = CGPoint(x: 500, y: 222), noteCenter = CGPoint(x: 572, y: 390)
let iconSize: CGFloat = 100, labelOffset: CGFloat = 66   // label centre below the icon centre

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

func render(scale: CGFloat, share: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // points, so the 2x rep carries 144 dpi
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let cg = ns.cgContext   // already in points: rep.size is W×H, so a 2x rep comes with a 2x transform
    // Flip to top-left so the numbers match Finder's.
    cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1)
    draw(cg, share: share)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Text in the flipped context: AppKit text needs a local unflip around its baseline box.
func text(_ string: String, font: NSFont, color: NSColor, at topLeft: CGPoint, in cg: CGContext, kern: CGFloat = 0) {
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let size = attributed.size()
    cg.saveGState()
    cg.translateBy(x: topLeft.x, y: topLeft.y + size.height); cg.scaleBy(x: 1, y: -1)
    attributed.draw(at: .zero)
    cg.restoreGState()
}

func textWidth(_ string: String, font: NSFont) -> CGFloat { NSAttributedString(string: string, attributes: [.font: font]).size().width }

func gradientFill(_ path: CGPath, colors: [NSColor], from: CGPoint, to: CGPoint, in cg: CGContext) {
    cg.saveGState()
    cg.addPath(path); cg.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    cg.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()
}

func gradientText(_ string: String, font: NSFont, at topLeft: CGPoint, in cg: CGContext) {
    // Draw the glyphs as a mask, then fill the mask with the brand gradient.
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = attributed.size()
    let px = 4.0
    let maskRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * px)), pixelsHigh: Int(ceil(size.height * px)),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: maskRep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: px, y: px)
    attributed.draw(at: .zero)
    NSGraphicsContext.restoreGraphicsState()
    let rect = CGRect(x: topLeft.x, y: topLeft.y, width: size.width, height: size.height)
    cg.saveGState()
    // The mask image is bottom-up; flip locally so it lands upright.
    cg.translateBy(x: 0, y: rect.minY + rect.maxY); cg.scaleBy(x: 1, y: -1)
    cg.clip(to: rect, mask: maskRep.cgImage!)
    let gradient = CGGradient(colorsSpace: space, colors: [mint, sky, violet].map(\.cgColor) as CFArray, locations: nil)!
    cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: 0), end: CGPoint(x: rect.maxX, y: 0), options: [])
    cg.restoreGState()
}

func labelPill(below center: CGPoint, width: CGFloat, in cg: CGContext) {
    let rect = CGRect(x: center.x - width / 2, y: center.y + labelOffset - 11, width: width, height: 22)
    cg.addPath(CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil))
    cg.setFillColor(labelPlate.cgColor); cg.fillPath()
}

func stepBadge(_ number: String, at topLeft: CGPoint, in cg: CGContext) {
    let rect = CGRect(x: topLeft.x, y: topLeft.y, width: 22, height: 22)
    gradientFill(CGPath(ellipseIn: rect, transform: nil), colors: [mint, violet],
                 from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY), in: cg)
    let font = roundedFont(13, .heavy)
    text(number, font: font, color: night, at: CGPoint(x: rect.midX - textWidth(number, font: font) / 2, y: rect.minY + 3), in: cg)
}

func draw(_ cg: CGContext, share: Bool) {
    // Night sky with the brand glows (as in the lockups and social card).
    let base = CGGradient(colorsSpace: space, colors: [dusk.cgColor, night.cgColor] as CFArray, locations: nil)!
    cg.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: H), options: [])
    for (color, center, radius, alpha) in [(mint, CGPoint(x: 120, y: 330), 380.0, 0.16),
                                           (violet, CGPoint(x: 600, y: 60), 360.0, 0.22),
                                           (sky, CGPoint(x: 360, y: 230), 260.0, 0.07)] {
        let glow = CGGradient(colorsSpace: space, colors: [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: nil)!
        cg.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // Header: mark + wordmark, one calm line under it.
    if let mark = NSImage(contentsOf: root.appendingPathComponent("branding/svg/mark-on-dark.svg")) {
        cg.saveGState()
        cg.translateBy(x: 32, y: 24 + 36); cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current!.imageInterpolation = .high
        mark.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        cg.restoreGState()
    }
    let wordFont = roundedFont(24, .bold)
    text("Vibe", font: wordFont, color: cloud, at: CGPoint(x: 76, y: 27), in: cg, kern: -0.5)
    gradientText("Check", font: wordFont, at: CGPoint(x: 76 + textWidth("Vibe", font: wordFont) - 2.5, y: 27), in: cg)
    text(share ? "Two quick steps, then your Mac's vibe lives in the menu bar." : "One drag, then your Mac's vibe lives in the menu bar.", font: roundedFont(13, .medium), color: haze,
         at: CGPoint(x: 33, y: 72), in: cg)

    // Step 1: soft halos behind the two icons, and the arc arrow (a slice of the vibe ring) between them.
    stepBadge("1", at: CGPoint(x: 33, y: 112), in: cg)
    text("Drag VibeCheck into Applications", font: roundedFont(15, .semibold), color: cloud, at: CGPoint(x: 63, y: 113), in: cg)
    for center in [appCenter, appsCenter] {
        let r: CGFloat = 70
        let halo = CGGradient(colorsSpace: space, colors: [NSColor(white: 1, alpha: 0.09).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: nil)!
        cg.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
    }
    let start = CGPoint(x: appCenter.x + 72, y: appCenter.y - 6), end = CGPoint(x: appsCenter.x - 78, y: appsCenter.y - 6)
    let arc = CGMutablePath()
    arc.move(to: start)
    arc.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: appCenter.y - 70))
    // Arrowhead: a chevron along the curve's end tangent.
    let tangent = atan2(end.y - (appCenter.y - 70), end.x - (start.x + end.x) / 2)
    let head: CGFloat = 13
    arc.move(to: CGPoint(x: end.x - head * cos(tangent - .pi / 5), y: end.y - head * sin(tangent - .pi / 5)))
    arc.addLine(to: end)
    arc.addLine(to: CGPoint(x: end.x - head * cos(tangent + .pi / 5), y: end.y - head * sin(tangent + .pi / 5)))
    let stroked = arc.copy(strokingWithWidth: 5, lineCap: .round, lineJoin: .round, miterLimit: 4)
    cg.saveGState()
    cg.setShadow(offset: .zero, blur: 14, color: sky.withAlphaComponent(0.55).cgColor)
    gradientFill(stroked, colors: [mint, sky, violet], from: start, to: end, in: cg)
    cg.restoreGState()
    labelPill(below: appCenter, width: 96, in: cg)
    labelPill(below: appsCenter, width: 108, in: cg)

    guard share else {
        text("Then open VibeCheck from Applications. It shows up in the menu bar, top right.", font: roundedFont(13, .medium),
             color: haze, at: CGPoint(x: 33, y: 330), in: cg)
        return
    }
    // Step 2: a glass card with the one Terminal line, and the note (which has the line to copy).
    let card = CGRect(x: 24, y: 318, width: W - 48, height: 160)
    cg.addPath(CGPath(roundedRect: card, cornerWidth: 20, cornerHeight: 20, transform: nil))
    cg.setFillColor(NSColor(white: 1, alpha: 0.055).cgColor); cg.fillPath()
    cg.addPath(CGPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 20, cornerHeight: 20, transform: nil))
    cg.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor); cg.setLineWidth(1); cg.strokePath()

    stepBadge("2", at: CGPoint(x: 44, y: 338), in: cg)
    text("Once, in Terminal", font: roundedFont(15, .semibold), color: cloud, at: CGPoint(x: 74, y: 339), in: cg)
    text("macOS blocks apps shared outside the App Store. This line lets VibeCheck open.", font: roundedFont(12, .regular),
         color: haze, at: CGPoint(x: 45, y: 366), in: cg)
    let chip = CGRect(x: 44, y: 390, width: 458, height: 30)
    cg.addPath(CGPath(roundedRect: chip, cornerWidth: 8, cornerHeight: 8, transform: nil))
    cg.setFillColor(night.withAlphaComponent(0.75).cgColor); cg.fillPath()
    let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
    text("$", font: mono, color: haze.withAlphaComponent(0.6), at: CGPoint(x: 56, y: 397), in: cg)
    text("xattr -dr com.apple.quarantine /Applications/VibeCheck.app", font: mono, color: mint, at: CGPoint(x: 70, y: 397), in: cg)
    text("Copy it from the note  →   then open VibeCheck from Applications.", font: roundedFont(12, .medium),
         color: cloud.withAlphaComponent(0.85), at: CGPoint(x: 45, y: 434), in: cg)
    labelPill(below: noteCenter, width: 112, in: cg)
}

for (share, base) in [(true, "share"), (false, "release")] {
    for (scale, suffix) in [(1.0, ""), (2.0, "@2x")] {
        let name = "\(base)\(suffix).png"
        try! render(scale: scale, share: share).representation(using: .png, properties: [:])!
            .write(to: outDir.appendingPathComponent(name))
        print("  wrote branding/dmg/\(name)")
    }
}
