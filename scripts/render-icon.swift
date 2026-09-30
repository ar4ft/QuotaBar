import AppKit
import Foundation

// Original vector artwork. Render every icon size directly so small icons stay sharp.
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist", isDirectory: true)
let iconset = output.appendingPathComponent("QuotaBar.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in sizes {
    let pixels = points * scale
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot render icon") }
    context.cgContext.clear(CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
    shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 20
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.43, alpha: 1).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.21, blue: 0.43, alpha: 1),
                              ending: NSColor(calibratedRed: 0.26, green: 0.55, blue: 0.96, alpha: 1))!
    gradient.draw(in: tile, angle: 65)
    for (index, height) in [268.0, 404.0, 560.0].enumerated() {
        let x = 268.0 + Double(index) * 188
        let track = NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: 232, width: 112, height: 560), xRadius: 56, yRadius: 56)
        NSColor.white.withAlphaComponent(0.18).setFill(); track.fill()
        let fill = NSBezierPath(roundedRect: NSRect(x: CGFloat(x), y: 232, width: 112, height: CGFloat(height)), xRadius: 56, yRadius: 56)
        (index == 2 ? NSColor(calibratedRed: 0.70, green: 0.96, blue: 0.92, alpha: 1) : .white).setFill()
        fill.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try png.write(to: iconset.appendingPathComponent(name))
    if pixels == 1024 { try png.write(to: output.appendingPathComponent("QuotaBar-icon.png")) }
}
