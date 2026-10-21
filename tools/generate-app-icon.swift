import AppKit
import CoreGraphics
import Foundation

// Palm handheld artwork. Each PDF below remains a vector layer in Icon Composer.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let document = root.appendingPathComponent("MacApp/Resources/PalmOS.icon")
let assets = document.appendingPathComponent("Assets")
let iconset = root.appendingPathComponent("MacApp/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let size: CGFloat = 1024
func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: CGColor) {
    c.addPath(rounded(r, radius))
    c.setFillColor(color)
    c.fillPath()
}
func stroke(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ color: CGColor, _ width: CGFloat) {
    c.addPath(rounded(r, radius))
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.strokePath()
}
func oval(_ c: CGContext, _ r: CGRect, _ color: CGColor) {
    c.setFillColor(color)
    c.fillEllipse(in: r)
}
func line(_ c: CGContext, _ points: [CGPoint], _ color: CGColor, _ width: CGFloat) {
    let p = CGMutablePath()
    p.move(to: points[0])
    for point in points.dropFirst() { p.addLine(to: point) }
    c.addPath(p)
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.strokePath()
}
func gradient(_ c: CGContext, _ r: CGRect, _ radius: CGFloat,
              _ lower: CGColor, _ upper: CGColor) {
    c.saveGState()
    c.addPath(rounded(r, radius))
    c.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [lower, upper] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: r.midX, y: r.minY),
                         end: CGPoint(x: r.midX, y: r.maxY), options: [])
    c.restoreGState()
}
func pdf(_ name: String, _ draw: (CGContext) -> Void) {
    var box = CGRect(x: 0, y: 0, width: size, height: size)
    let url = assets.appendingPathComponent(name + ".pdf")
    let c = CGContext(url as CFURL, mediaBox: &box, nil)!
    c.beginPDFPage(nil)
    // Icon Composer maps PDF points at 2× on its 1024 px canvas.
    c.translateBy(x: 256, y: 256)
    c.scaleBy(x: 0.5, y: 0.5)
    draw(c)
    c.endPDFPage()
    c.closePDF()
}

let body: (CGContext) -> Void = { c in
    let shell = CGRect(x: 214, y: 104, width: 596, height: 830)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -22), blur: 32,
                color: rgba(0.01, 0.12, 0.20, 0.42))
    gradient(c, shell, 105, rgba(0.57, 0.70, 0.75), rgba(0.98, 0.99, 1))
    c.restoreGState()
    stroke(c, shell.insetBy(dx: 5, dy: 5), 100, rgba(1, 1, 1, 0.75), 8)
    stroke(c, shell.insetBy(dx: 15, dy: 15), 91, rgba(0.16, 0.34, 0.42, 0.22), 3)
    // The recessed speaker and status LED stand in for tiny illegible lettering.
    fill(c, CGRect(x: 459, y: 876, width: 106, height: 10), 5, rgba(0.26, 0.43, 0.49, 0.58))
    oval(c, CGRect(x: 728, y: 871, width: 16, height: 16), rgba(0.23, 0.65, 0.65))
}

let display: (CGContext) -> Void = { c in
    let bezel = CGRect(x: 267, y: 415, width: 490, height: 418)
    fill(c, bezel, 34, rgba(0.22, 0.34, 0.42))
    stroke(c, bezel.insetBy(dx: 4, dy: 4), 30, rgba(0.07, 0.19, 0.24, 0.45), 5)
    let screen = CGRect(x: 280, y: 429, width: 464, height: 389)
    gradient(c, screen, 22, rgba(0.81, 0.91, 0.85), rgba(0.96, 0.98, 0.93))
    let header = CGRect(x: 280, y: 755, width: 464, height: 63)
    fill(c, header, 19, rgba(0.30, 0.26, 0.58))
    c.setFillColor(rgba(0.30, 0.26, 0.58))
    c.fill(CGRect(x: 280, y: 755, width: 464, height: 27))
    // Four launcher tiles are large enough to remain distinct in the Dock.
    let tiles: [(CGFloat, CGFloat, CGColor)] = [
        (315, 622, rgba(0.32, 0.49, 0.76)),
        (520, 622, rgba(0.58, 0.40, 0.66)),
        (315, 475, rgba(0.45, 0.66, 0.54)),
        (520, 475, rgba(0.76, 0.48, 0.39))
    ]
    for (x, y, color) in tiles {
        fill(c, CGRect(x: x, y: y, width: 174, height: 111), 27, color)
        fill(c, CGRect(x: x + 18, y: y + 80, width: 138, height: 9), 4,
             rgba(1, 1, 1, 0.18))
    }
    // Calendar, Contacts, To Do, and Memo glyphs.
    fill(c, CGRect(x: 365, y: 643, width: 74, height: 62), 8, rgba(1, 1, 1))
    fill(c, CGRect(x: 365, y: 690, width: 74, height: 15), 7, rgba(0.83, 0.88, 0.99))
    oval(c, CGRect(x: 583, y: 672, width: 34, height: 34), rgba(1, 1, 1))
    fill(c, CGRect(x: 569, y: 644, width: 62, height: 23), 11, rgba(1, 1, 1))
    for y: CGFloat in [546, 522, 498] {
        fill(c, CGRect(x: 350, y: y, width: 13, height: 13), 3, rgba(1, 1, 1))
        fill(c, CGRect(x: 378, y: y + 4, width: 69, height: 6), 3, rgba(1, 1, 1))
    }
    fill(c, CGRect(x: 574, y: 492, width: 68, height: 71), 5, rgba(1, 1, 1))
    for y: CGFloat in [544, 529, 514] {
        fill(c, CGRect(x: 585, y: y, width: 47, height: 5), 2,
             rgba(0.76, 0.48, 0.39))
    }
}

let graffiti: (CGContext) -> Void = { c in
    let panel = CGRect(x: 267, y: 313, width: 490, height: 111)
    fill(c, panel, 17, rgba(0.22, 0.34, 0.42))
    gradient(c, panel.insetBy(dx: 13, dy: 11), 7,
             rgba(0.67, 0.76, 0.75), rgba(0.84, 0.90, 0.86))
    line(c, [CGPoint(x: 512, y: 333), CGPoint(x: 512, y: 404)],
         rgba(0.28, 0.45, 0.48, 0.48), 3)
    let pen = CGMutablePath()
    pen.move(to: CGPoint(x: 394, y: 388))
    pen.addCurve(to: CGPoint(x: 366, y: 346), control1: CGPoint(x: 327, y: 411),
                 control2: CGPoint(x: 325, y: 354))
    pen.addCurve(to: CGPoint(x: 444, y: 375), control1: CGPoint(x: 405, y: 331),
                 control2: CGPoint(x: 449, y: 342))
    c.addPath(pen)
    c.setStrokeColor(rgba(0.23, 0.42, 0.45))
    c.setLineWidth(14)
    c.setLineCap(.round)
    c.strokePath()
    // Simplified numerical input mark, rather than unreadable 123 text.
    for x: CGFloat in [577, 609, 641] {
        line(c, [CGPoint(x: x, y: 350), CGPoint(x: x, y: 389)],
             rgba(0.31, 0.48, 0.51), 8)
    }
}

let controls: (CGContext) -> Void = { c in
    for x: CGFloat in [322, 410, 614, 702] {
        let button = CGRect(x: x - 30, y: 202, width: 60, height: 65)
        gradient(c, button, 25, rgba(0.63, 0.76, 0.80), rgba(0.95, 0.97, 0.95))
        stroke(c, button, 25, rgba(0.30, 0.49, 0.56, 0.75), 4)
    }
    let rocker = CGRect(x: 453, y: 181, width: 118, height: 100)
    gradient(c, rocker, 43, rgba(0.53, 0.68, 0.74), rgba(0.87, 0.93, 0.92))
    stroke(c, rocker, 43, rgba(0.28, 0.46, 0.53), 5)
    fill(c, CGRect(x: 488, y: 207, width: 49, height: 49), 23,
         rgba(0.32, 0.48, 0.57))
    oval(c, CGRect(x: 503, y: 222, width: 19, height: 19),
         rgba(0.77, 0.91, 0.91))
}

for (name, draw) in [
    ("Body", body), ("Display", display), ("Graffiti", graffiti), ("Controls", controls)
] {
    pdf(name, draw)
}

// The native background and material effects remain editable in Icon Composer.
let json: [String: Any] = [
    "fill": ["automatic-gradient": "extended-srgb:0.03500,0.43500,0.51500,1.00000"],
    "groups": [[
        "name": "Palm handheld",
        "layers": [
            ["image-name": "Controls.pdf", "name": "Hardware buttons"],
            ["glass": false, "image-name": "Graffiti.pdf", "name": "Graffiti input"],
            ["glass": false, "image-name": "Display.pdf", "name": "Palm OS launcher"],
            ["image-name": "Body.pdf", "name": "Handheld body"]
        ],
        "shadow": ["kind": "neutral", "opacity": 0.48],
        "translucency": ["enabled": true, "value": 0.20]
    ]],
    "supported-platforms": ["squares": ["macOS"]]
]
let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try data.write(to: document.appendingPathComponent("icon.json"))

// Flat PNGs remain only as a compatibility fallback for older build tools.
let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024 * 1024 * 4)
pixels.initialize(repeating: 0, count: 1024 * 1024 * 4)
defer { pixels.deallocate() }
let bitmap = CGContext(data: pixels, width: 1024, height: 1024, bitsPerComponent: 8,
                       bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setAllowsAntialiasing(true)
bitmap.setShouldAntialias(true)
gradient(bitmap, CGRect(x: 38, y: 38, width: 948, height: 948), 215,
         rgba(0.03, 0.32, 0.40), rgba(0.24, 0.65, 0.70))
for draw in [body, display, graffiti, controls] { draw(bitmap) }
let master = iconset.appendingPathComponent("icon_512x512@2x.png")
try NSBitmapImageRep(cgImage: bitmap.makeImage()!)
    .representation(using: .png, properties: [:])!.write(to: master)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2),
                        (128, 1), (128, 2), (256, 1), (256, 2), (512, 1)] {
    let suffix = scale == 2 ? "@2x" : ""
    let output = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-z", "\(points * scale)", "\(points * scale)",
                      master.path, "--out", output.path]
    task.standardOutput = FileHandle.nullDevice
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { throw NSError(domain: "sips", code: 1) }
}
