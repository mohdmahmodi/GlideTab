// Generates the app icon: swift scripts/make-icon.swift Resources/AppIcon.icns
// Flat graphite tile with two overlapping windows, drawn on Apple's 1024pt icon grid.
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func gray(_ white: CGFloat) -> NSColor { NSColor(srgbRed: white, green: white, blue: white, alpha: 1) }

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = CGFloat(pixels) / 1024 // one unit of the 1024pt grid

    // Tile
    let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    gray(0.17).setFill()
    NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u).fill()

    func window(_ rect: NSRect, body: NSColor, bar: NSColor, dots: Bool) {
        let radius = 36 * u
        body.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let barRect = NSRect(x: rect.minX, y: rect.maxY - 64 * u, width: rect.width, height: 64 * u)
        bar.setFill()
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)
        barPath.append(NSBezierPath(rect: NSRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: radius)))
        barPath.fill()
        guard dots else { return }
        gray(0.62).setFill()
        for i in 0..<3 {
            NSBezierPath(ovalIn: NSRect(x: rect.minX + (34 + CGFloat(i) * 40) * u, y: barRect.midY - 11 * u,
                                        width: 22 * u, height: 22 * u)).fill()
        }
    }
    window(NSRect(x: 232 * u, y: 420 * u, width: 440 * u, height: 330 * u), body: gray(0.36), bar: gray(0.42), dots: false)
    window(NSRect(x: 352 * u, y: 274 * u, width: 440 * u, height: 330 * u), body: gray(0.96), bar: gray(0.84), dots: true)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
