import AppKit
let files = Array(CommandLine.arguments.dropFirst(2)); let out = CommandLine.arguments[1]
let imgs = files.compactMap { NSImage(contentsOfFile: $0) }
let w: CGFloat = 760, h: CGFloat = 560, cols = 2
let rows = (imgs.count + cols - 1) / cols
let canvas = NSImage(size: NSSize(width: w * CGFloat(cols), height: h * CGFloat(rows)))
canvas.lockFocus()
for (i, img) in imgs.enumerated() {
    let c = i % cols, r = i / cols
    img.draw(in: NSRect(x: CGFloat(c) * w, y: CGFloat(rows - 1 - r) * h, width: w, height: h))
}
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
