// Cymba's black Cy lettermark on a white macOS icon tile.
// Run from macOS/: swift scripts/make-icon.swift
import AppKit
import CoreText

func render(size: Int) -> NSBitmapImageRep {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: size * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.clip()
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(tile)

    // Same typography and proportions as ios/scripts/make-native-icon.swift.
    let font = NSFont.systemFont(ofSize: 540 * 824 / 1024, weight: .bold)
    let text = NSAttributedString(string: "Cy", attributes: [.font: font, .foregroundColor: NSColor.black])
    let line = CTLineCreateWithAttributedString(text)
    let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
    context.textPosition = CGPoint(x: tile.midX - bounds.width / 2 - bounds.minX,
                                   y: tile.midY - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, context)
    return NSBitmapImageRep(cgImage: context.makeImage()!)
}

let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = fm.temporaryDirectory.appendingPathComponent("Cymba-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 1024).representation(using: .png, properties: [:])!
    .write(to: resources.appendingPathComponent("AppIcon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Cymba AppIcon.icns and AppIcon.png")
