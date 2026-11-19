// Writes the vibe ring as custom SF Symbols, one per state, into Resources/Symbols.xcassets:
//   vibe.ring.vibing (full), vibe.ring.mid (two-thirds), vibe.ring.cooked (one-third).
// Two layers each: the track (hierarchical-1, secondary) and the arc (hierarchical-0, primary), so palette
// rendering can color the arc and dim the track. Template v.4.0, the three sources SF Symbols needs
// (Ultralight-S, Regular-S, Black-S); every weight uses the same path structure so they interpolate.
// build.sh compiles the catalog with actool. Run: swift scripts/render_ring_symbol.swift
import Foundation

// Template geometry for the small scale (from the SF Symbols v4 template): baseline and cap height.
let baselineS = 696.0, capHeight = 70.459
let columns: [(id: String, center: Double, stroke: Double)] = [
    ("Ultralight-S", 559.711, 4.5), ("Regular-S", 1449.84, 13.0), ("Black-S", 2933.4, 21.0),
]
let ringRadius = 40.0          // centre line of the ring, in template units (100 pt type)
let sidePad = 3.0              // side bearing either side of the glyph

struct P { var x, y: Double }
func + (a: P, b: P) -> P { P(x: a.x + b.x, y: a.y + b.y) }
func * (a: P, s: Double) -> P { P(x: a.x * s, y: a.y * s) }
func f(_ v: Double) -> String { String(format: "%.3f", v) }
func pt(_ p: P) -> String { "\(f(p.x)) \(f(p.y))" }

/// Paths for one weight. Angles are clockwise from 12 o'clock in screen space (y grows down).
struct Ring {
    let c: P, r: Double, h: Double   // centre, centre-line radius, half the stroke

    func at(_ radius: Double, _ deg: Double) -> P {
        let t = deg * .pi / 180
        return P(x: c.x + radius * sin(t), y: c.y - radius * cos(t))
    }
    /// Cubic arcs along `radius` from a0 to a1 (either direction), split into pieces of at most 90°.
    func arc(_ radius: Double, _ a0: Double, _ a1: Double) -> String {
        let pieces = max(1, Int((abs(a1 - a0) / 90).rounded(.up)))
        let step = (a1 - a0) / Double(pieces)
        var out = ""
        for i in 0..<pieces {
            let s = a0 + step * Double(i), e = s + step
            let k = 4.0 / 3 * tan(abs(step) * .pi / 180 / 4) * radius * (step < 0 ? -1 : 1)
            let ts = s * .pi / 180, te = e * .pi / 180
            let c1 = at(radius, s) + P(x: cos(ts), y: sin(ts)) * k
            let c2 = at(radius, e) + P(x: cos(te), y: sin(te)) * -k
            out += " C\(pt(c1)) \(pt(c2)) \(pt(at(radius, e)))"
        }
        return out
    }
    /// Half-circle cap at angle `deg` from the outer edge to the inner one (or back), bulging along `dir`.
    func cap(_ deg: Double, forward: Bool) -> String {
        let t = deg * .pi / 180
        let m = at(r, deg)
        let n = P(x: sin(t), y: -cos(t)), tan = P(x: cos(t), y: sin(t)) * (forward ? 1 : -1)
        let from = forward ? n : n * -1, to = from * -1
        let k = 0.5523 * h
        func quarter(_ u: P, _ v: P) -> String {
            " C\(pt(m + u * h + v * k)) \(pt(m + v * h + u * k)) \(pt(m + v * h))"
        }
        return quarter(from, tan) + quarter(tan, to)
    }
    var track: String {
        let o = r + h, i = r - h
        return "M\(pt(at(o, 0)))\(arc(o, 0, 360))Z M\(pt(at(i, 0)))\(arc(i, 0, -360))Z"
    }
    func filled(_ fraction: Double) -> String {
        guard fraction < 1 else { return track }
        let end = 360 * fraction, o = r + h, i = r - h
        return "M\(pt(at(o, 0)))\(arc(o, 0, end))\(cap(end, forward: true))\(arc(i, end, 0))\(cap(0, forward: false))Z"
    }
}

func svg(fraction: Double, name: String) -> String {
    var guides = "", symbols = ""
    for column in columns {
        let h = column.stroke / 2, width = 2 * (ringRadius + h) + 2 * sidePad
        let left = column.center - width / 2
        guides += """
          <line id="left-margin-\(column.id)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(f(left))" x2="\(f(left))" y1="600.785" y2="720.121"/>
          <line id="right-margin-\(column.id)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\(f(left + width))" x2="\(f(left + width))" y1="600.785" y2="720.121"/>

        """
        let ring = Ring(c: P(x: sidePad + ringRadius + h, y: -capHeight / 2), r: ringRadius, h: h)
        symbols += """
          <g id="\(column.id)" transform="matrix(1 0 0 1 \(f(left)) \(f(baselineS)))">
           <path class="monochrome-1 multicolor-1:tintColor hierarchical-1:secondary" d="\(ring.track)"/>
           <path class="monochrome-0 multicolor-0:tintColor hierarchical-0:primary" d="\(ring.filled(fraction))"/>
          </g>

        """
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE svg
    PUBLIC "-//W3C//DTD SVG 1.1//EN"
           "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
     <!--template writer version: "101"-->
     <style>.monochrome-0 {fill:#000000}

    .monochrome-1 {fill:#000000}

    .multicolor-0:tintColor {fill:#007AFF}

    .multicolor-1:tintColor {fill:#007AFF}

    .hierarchical-0:primary {fill:#212121}

    .hierarchical-1:secondary {fill:#8E8E8E}

    .SFSymbolsPreviewWireframe {fill:none;opacity:1.0;stroke:#000000;stroke-width:0.5}
    </style>
    <g id="Notes">
      <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
      <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.4.0</text>
      <text id="descriptive-name" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1969)">\(name)</text>
     </g>
    <g id="Guides">
      <line id="Baseline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="696" y2="696"/>
      <line id="Capline-S" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="625.541" y2="625.541"/>
      <line id="Baseline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1126" y2="1126"/>
      <line id="Capline-M" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1055.541" y2="1055.541"/>
      <line id="Baseline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1556" y2="1556"/>
      <line id="Capline-L" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="1485.541" y2="1485.541"/>
    \(guides) </g>
    <g id="Symbols">
    \(symbols) </g>
    </svg>

    """
}

let catalog = URL(fileURLWithPath: "Resources/Symbols.xcassets")
let fm = FileManager.default
try? fm.createDirectory(at: catalog, withIntermediateDirectories: true)
try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
for (state, fraction) in [("vibing", 1.0), ("mid", 2.0 / 3), ("cooked", 1.0 / 3)] {
    let name = "vibe.ring.\(state)"
    let set = catalog.appendingPathComponent("\(name).symbolset")
    try? fm.createDirectory(at: set, withIntermediateDirectories: true)
    try svg(fraction: fraction, name: name).write(to: set.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
    try #"{"info":{"author":"xcode","version":1},"symbols":[{"filename":"\#(name).svg","idiom":"universal"}]}"#
        .write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(set.path)")
}
