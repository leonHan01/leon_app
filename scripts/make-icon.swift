import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(size)
        NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.89, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: s * 0.20, yRadius: s * 0.20).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.23, y: s * 0.32, width: s * 0.55, height: s * 0.43), xRadius: s * 0.10, yRadius: s * 0.10).fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: s * 0.30, y: s * 0.37)); tail.line(to: NSPoint(x: s * 0.28, y: s * 0.22)); tail.line(to: NSPoint(x: s * 0.48, y: s * 0.37)); tail.close(); tail.fill()
        NSColor(calibratedRed: 0.18, green: 0.36, blue: 0.89, alpha: 1).setFill()
        for (y, width) in [(0.57, 0.31), (0.45, 0.21)] {
            NSBezierPath(roundedRect: NSRect(x: s * 0.35, y: s * y, width: s * width, height: s * 0.035), xRadius: s * 0.018, yRadius: s * 0.018).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 1 ? "" : "@2x"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(points)x\(points)\(suffix).png"))
    }
}
