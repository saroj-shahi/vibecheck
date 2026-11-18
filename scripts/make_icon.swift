// Renders the VibeCheck app icon (rounded square, gradient, heartbeat line) into an .iconset folder.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 1),
                        NSColor(red: 0.12, green: 0.22, blue: 0.42, alpha: 1)])!.draw(in: shape, angle: 90)

    let line = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(0.18, 0.48), (0.36, 0.48), (0.43, 0.66), (0.52, 0.28), (0.6, 0.6), (0.65, 0.48), (0.82, 0.48)]
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: s * p.0, y: s * p.1)
        i == 0 ? line.move(to: pt) : line.line(to: pt)
    }
    line.lineWidth = s * 0.045
    line.lineJoinStyle = .round
    line.lineCapStyle = .round
    NSColor(red: 0.3, green: 0.95, blue: 0.8, alpha: 1).setStroke()
    line.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
