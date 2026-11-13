// Deterministic lettermark using the same bold system typography as the native app.
// Run from the repository root: swift ios/scripts/make-native-icon.swift
import AppKit
import CoreText

let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("StockBar/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(gray: 1, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let font = NSFont.systemFont(ofSize: 540, weight: .bold)
let text = NSAttributedString(string: "Cy", attributes: [.font: font, .foregroundColor: NSColor.black])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
context.textPosition = CGPoint(x: (1024 - bounds.width) / 2 - bounds.minX,
                               y: (1024 - bounds.height) / 2 - bounds.minY)
CTLineDraw(line, context)
let image = context.makeImage()!
let bitmap = NSBitmapImageRep(cgImage: image)
try bitmap.representation(using: .png, properties: [:])!.write(to: output, options: .atomic)
let assets = output.deletingLastPathComponent().deletingLastPathComponent()
let png = try Data(contentsOf: output)
for name in ["light", "dark"] {
    try png.write(to: assets.appendingPathComponent("LaunchMark.imageset/\(name).png"), options: .atomic)
}
print("Wrote native app icon and launch marks")
