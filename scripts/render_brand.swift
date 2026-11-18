// Renders every VibeCheck brand asset from the SVG sources in branding/svg.
// Usage (from the repo root):  swift scripts/render_brand.swift
// Outputs: Resources/AppIcon.icns, branding/png/*.png
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgDir = root.appendingPathComponent("branding/svg")
let pngDir = root.appendingPathComponent("branding/png")
try? FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true)

// MARK: Brand tokens (keep in sync with branding/BRAND.md)

enum Brand {
    static let ink = NSColor(hex: 0x141833)
    static let night = NSColor(hex: 0x0B0E22)
    static let dusk = NSColor(hex: 0x252A52)
    static let mint = NSColor(hex: 0x3DE0B5)
    static let sky = NSColor(hex: 0x36B6F2)
    static let violet = NSColor(hex: 0x8B6CFF)
    static let cloud = NSColor(hex: 0xF5F7FF)
    static let haze = NSColor(hex: 0xAEB4D6)
    static let mid = NSColor(hex: 0xFFC542)
    static let cooked = NSColor(hex: 0xFF5A5F)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: Helpers

func svg(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: svgDir.appendingPathComponent(name)) else { fatalError("missing \(name)") }
    return image
}

func canvas(_ width: Int, _ height: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    draw(context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ url: URL) {
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("  wrote \(url.path.replacingOccurrences(of: root.path + "/", with: ""))")
}

func render(_ image: NSImage, size: Int) -> NSBitmapImageRep {
    canvas(size, size) { _ in image.draw(in: NSRect(x: 0, y: 0, width: size, height: size)) }
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

/// Draws text filled with a left-to-right gradient (used for "Check" in the wordmark).
func drawGradientText(_ text: String, font: NSFont, at origin: CGPoint, colors: [NSColor], in context: CGContext) {
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = attributed.size()
    let maskRep = canvas(Int(ceil(size.width)) + 4, Int(ceil(size.height)) + 4) { _ in
        attributed.draw(at: CGPoint(x: 2, y: 2))
    }
    guard let mask = maskRep.cgImage else { return }
    let rect = CGRect(x: origin.x - 2, y: origin.y - 2, width: CGFloat(mask.width), height: CGFloat(mask.height))
    context.saveGState()
    context.clip(to: rect, mask: mask)
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: colors.map(\.cgColor) as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.midY),
                               end: CGPoint(x: rect.maxX, y: rect.midY), options: [])
    context.restoreGState()
}

/// "Vibe" in a solid color followed by "Check" in the brand gradient. Returns the drawn width.
@discardableResult
func drawWordmark(size: CGFloat, at origin: CGPoint, solid: NSColor, in context: CGContext) -> CGFloat {
    let font = roundedFont(size, .bold)
    let vibe = NSAttributedString(string: "Vibe", attributes: [.font: font, .foregroundColor: solid, .kern: -size * 0.02])
    vibe.draw(at: origin)
    let x = origin.x + vibe.size().width
    drawGradientText("Check", font: font, at: CGPoint(x: x, y: origin.y), colors: [Brand.mint, Brand.sky, Brand.violet], in: context)
    let check = NSAttributedString(string: "Check", attributes: [.font: font])
    return vibe.size().width + check.size().width
}

func darkBackground(_ context: CGContext, _ rect: CGRect) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    let base = CGGradient(colorsSpace: space, colors: [Brand.dusk.cgColor, Brand.night.cgColor] as CFArray, locations: nil)!
    context.drawLinearGradient(base, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    for (color, center, radius, alpha) in [(Brand.mint, CGPoint(x: rect.width * 0.25, y: rect.height * 0.3), rect.width * 0.45, 0.20),
                                           (Brand.violet, CGPoint(x: rect.width * 0.85, y: rect.height * 0.85), rect.width * 0.45, 0.26)] {
        let glow = CGGradient(colorsSpace: space, colors: [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: nil)!
        context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
}

// MARK: 1. App icon (.icns): simplified art at 16–32 px, full art above

print("App icon")
let icon = svg("icon.svg"), iconSmall = svg("icon-small.svg")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let slots: [(String, Int, NSImage)] = [
    ("16x16", 16, iconSmall), ("16x16@2x", 32, iconSmall), ("32x32", 32, iconSmall), ("32x32@2x", 64, icon),
    ("128x128", 128, icon), ("128x128@2x", 256, icon), ("256x256", 256, icon), ("256x256@2x", 512, icon),
    ("512x512", 512, icon), ("512x512@2x", 1024, icon),
]
for (name, px, art) in slots {
    try! render(art, size: px).representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run(); iconutil.waitUntilExit()
print("  wrote Resources/AppIcon.icns")
for px in [1024, 512, 256, 128] { save(render(icon, size: px), pngDir.appendingPathComponent("icon-\(px).png")) }
save(render(iconSmall, size: 64), pngDir.appendingPathComponent("icon-small-64.png"))

// MARK: 2. Marks

print("Marks")
for name in ["mark-on-dark", "mark-on-light", "mark-mono"] {
    save(render(svg("\(name).svg"), size: 512), pngDir.appendingPathComponent("\(name)-512.png"))
}

// MARK: 3. Wordmark lockups (transparent; light = for light backgrounds, dark = for dark backgrounds)

print("Lockups")
for (variant, text, markName) in [("light", Brand.ink, "mark-on-light"), ("dark", Brand.cloud, "mark-on-dark")] {
    let rep = canvas(1600, 400) { context in
        svg("\(markName).svg").draw(in: NSRect(x: 30, y: 40, width: 320, height: 320))
        drawWordmark(size: 200, at: CGPoint(x: 390, y: 75), solid: text, in: context)
    }
    save(rep, pngDir.appendingPathComponent("lockup-\(variant).png"))
}

// MARK: 4. Social card (GitHub social preview, 1280×640)

print("Social card")
let card = canvas(1280, 640) { context in
    let rect = CGRect(x: 0, y: 0, width: 1280, height: 640)
    darkBackground(context, rect)
    icon.draw(in: NSRect(x: 90, y: 150, width: 360, height: 360))
    drawWordmark(size: 112, at: CGPoint(x: 500, y: 330), solid: Brand.cloud, in: context)
    NSAttributedString(string: "Is your Mac vibing or cooked?", attributes: [
        .font: roundedFont(40, .medium), .foregroundColor: Brand.haze,
    ]).draw(at: CGPoint(x: 506, y: 268))
    var x: CGFloat = 506
    for label in ["CPU", "GPU", "Memory", "Network", "Sensors", "+4"] {
        let text = NSAttributedString(string: label, attributes: [.font: roundedFont(22, .semibold), .foregroundColor: Brand.cloud])
        let width = text.size().width + 32
        let pill = NSBezierPath(roundedRect: NSRect(x: x, y: 180, width: width, height: 42), xRadius: 21, yRadius: 21)
        NSColor.white.withAlphaComponent(0.10).setFill(); pill.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke(); pill.lineWidth = 1.5; pill.stroke()
        text.draw(at: CGPoint(x: x + 16, y: 188))
        x += width + 12
    }
}
save(card, pngDir.appendingPathComponent("social-card.png"))

// MARK: 5. Palette sheet

print("Palette")
let swatches: [(String, String, NSColor, NSColor)] = [
    ("Ink", "#141833", Brand.ink, Brand.cloud), ("Night", "#0B0E22", Brand.night, Brand.cloud),
    ("Mint", "#3DE0B5", Brand.mint, Brand.ink), ("Sky", "#36B6F2", Brand.sky, Brand.ink),
    ("Violet", "#8B6CFF", Brand.violet, Brand.cloud), ("Cloud", "#F5F7FF", Brand.cloud, Brand.ink),
    ("Mid", "#FFC542", Brand.mid, Brand.ink), ("Cooked", "#FF5A5F", Brand.cooked, Brand.ink),
]
let palette = canvas(1600, 300) { _ in
    let width: CGFloat = 1600 / CGFloat(swatches.count)
    for (index, swatch) in swatches.enumerated() {
        let rect = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: 300)
        swatch.2.setFill(); rect.fill()
        NSAttributedString(string: swatch.0, attributes: [.font: roundedFont(30, .bold), .foregroundColor: swatch.3])
            .draw(at: CGPoint(x: rect.minX + 22, y: 70))
        NSAttributedString(string: swatch.1, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .medium), .foregroundColor: swatch.3.withAlphaComponent(0.8)])
            .draw(at: CGPoint(x: rect.minX + 22, y: 36))
    }
}
save(palette, pngDir.appendingPathComponent("palette.png"))
print("Done")
