// Generates AppIcon.iconset/ for Open-Wispr: violet gradient squircle with a
// white voice waveform. Run with `swift make_icon.swift`, then
// `iconutil -c icns AppIcon.iconset -o AppIcon.icns` (build.sh does both).
import AppKit

func drawIcon(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)

    // Squircle background with the standard macOS icon margin.
    let inset = 0.065 * s
    let bgRect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: 0.2 * s, yRadius: 0.2 * s)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.11, blue: 0.58, alpha: 1.0), // deep violet
        NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.97, alpha: 1.0), // bright purple
    ])!
    gradient.draw(in: bg, angle: 60)

    // Soft top-edge highlight for a bit of depth.
    let highlight = NSGradient(colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.18),
        NSColor(calibratedWhite: 1.0, alpha: 0.0),
    ])!
    highlight.draw(in: bg, angle: -90)

    // Voice waveform: five rounded bars.
    let heights: [CGFloat] = [0.30, 0.52, 0.74, 0.52, 0.30]
    let alphas: [CGFloat] = [0.85, 0.95, 1.0, 0.95, 0.85]
    let barW = 0.075 * s
    let gap = 0.055 * s
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = (s - totalW) / 2
    for (i, h) in heights.enumerated() {
        let barH = h * s
        let barRect = NSRect(x: x, y: (s - barH) / 2, width: barW, height: barH)
        NSColor(calibratedWhite: 1.0, alpha: alphas[i]).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: barW / 2, yRadius: barW / 2).fill()
        x += barW + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    let rep = drawIcon(px: px)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("Wrote AppIcon.iconset (\(sizes.count) images)")
