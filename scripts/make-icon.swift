// Renders Resources/AppIcon.icns: a portfolio line climbing past a dashed benchmark.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // macOS icon grid: 824pt body centered in 1024, ~185pt corner radius.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(hex: 0x1D2C4C), NSColor(hex: 0x0C1424)])!.draw(in: shape, angle: -90)

    shape.addClip()
    // Faint grid lines.
    NSColor.white.withAlphaComponent(0.06).setStroke()
    for y in stride(from: 300.0, through: 750.0, by: 150.0) {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 100 * s, y: y * s))
        line.line(to: NSPoint(x: 924 * s, y: y * s))
        line.lineWidth = 4 * s
        line.stroke()
    }

    func path(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: points[0].0 * s, y: points[0].1 * s))
        for (x, y) in points.dropFirst() { p.line(to: NSPoint(x: x * s, y: y * s)) }
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        return p
    }

    // Benchmark: steady, dashed (like CDI on the chart).
    let benchmark = path([(190, 330), (830, 560)])
    benchmark.lineWidth = 34 * s
    benchmark.setLineDash([60 * s, 44 * s], count: 2, phase: 0)
    NSColor(hex: 0xEB6834).setStroke()
    benchmark.stroke()

    // Portfolio: jagged, ending well above the benchmark.
    let portfolio = path([(190, 330), (290, 400), (370, 350), (470, 500), (560, 450), (660, 620), (740, 580), (830, 760)])
    portfolio.lineWidth = 50 * s
    NSColor(hex: 0x3987E5).setStroke()
    portfolio.stroke()

    let dot = NSBezierPath(ovalIn: NSRect(x: (830 - 52) * s, y: (760 - 52) * s, width: 104 * s, height: 104 * s))
    NSColor.white.setFill()
    dot.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
