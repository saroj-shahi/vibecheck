import AppKit
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
let rep = img.representations.first as! NSBitmapImageRep
let y = Int(a[3])!, h = Int(a[4])!
let cg = rep.cgImage!.cropping(to: CGRect(x: 0, y: y, width: rep.pixelsWide, height: h))!
try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
