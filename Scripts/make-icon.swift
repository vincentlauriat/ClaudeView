#!/usr/bin/swift
// Renders the ClaudeView app icon (orange gradient + waveform glyph) into
// ClaudeView/Resources/ClaudeView.icns via an intermediate .iconset.
import AppKit

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("ClaudeView/Resources")
let iconset = resources.appendingPathComponent("ClaudeView.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let inset = size * 0.08                    // macOS icon grid margin
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 0.80, green: 0.25, blue: 0.05, alpha: 1),
    ])!.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                            accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let scale = min(rect.width * 0.62 / s.width, rect.height * 0.62 / s.height)
        let drawSize = NSSize(width: s.width * scale, height: s.height * scale)
        let origin = NSPoint(x: rect.midX - drawSize.width / 2,
                             y: rect.midY - drawSize.height / 2)
        symbol.draw(in: NSRect(origin: origin, size: drawSize))
    }
    return image
}

func write(_ image: NSImage, pixels: Int, name: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { fatalError("rep failed") }
    rep.size = NSSize(width: pixels, height: pixels)
    let resized = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: resized)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let png = resized.representation(using: .png, properties: [:])!
    try png.write(to: iconset.appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    let image = render(size: CGFloat(base * 2))
    try write(image, pixels: base, name: "icon_\(base)x\(base).png")
    try write(image, pixels: base * 2, name: "icon_\(base)x\(base)@2x.png")
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path,
                  "-o", resources.appendingPathComponent("ClaudeView.icns").path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "✅ ClaudeView.icns generated" : "✗ iconutil failed")
