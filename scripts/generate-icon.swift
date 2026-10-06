#!/usr/bin/env swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)
let manager = FileManager.default
try manager.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: iconset) }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 84, y: 84, width: 856, height: 856), xRadius: 192, yRadius: 192)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0.20, 0.11, 0.41, 0.26)
    tileShadow.shadowOffset = NSSize(width: 0, height: -13)
    tileShadow.shadowBlurRadius = 23
    tileShadow.set()
    color(0.47, 0.32, 0.86).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.63, 0.49, 0.96), color(0.42, 0.28, 0.82), color(0.32, 0.20, 0.65)])!.draw(in: tile, angle: -70)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let halo = NSBezierPath(ovalIn: NSRect(x: 270, y: 475, width: 750, height: 750))
    color(1, 1, 1, 0.075).setFill()
    halo.fill()
    let glow = NSBezierPath(ovalIn: NSRect(x: -220, y: -345, width: 840, height: 840))
    color(0.73, 0.57, 1, 0.08).setFill()
    glow.fill()
    NSGraphicsContext.restoreGraphicsState()

    let bubble = NSBezierPath(roundedRect: NSRect(x: 225, y: 277, width: 574, height: 511), xRadius: 127, yRadius: 127)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 298, y: 310))
    tail.line(to: NSPoint(x: 283, y: 211))
    tail.curve(to: NSPoint(x: 393, y: 288), controlPoint1: NSPoint(x: 280, y: 190), controlPoint2: NSPoint(x: 359, y: 244))
    tail.close()
    bubble.append(tail)
    NSGraphicsContext.saveGraphicsState()
    let bubbleShadow = NSShadow()
    bubbleShadow.shadowColor = color(0.21, 0.10, 0.45, 0.30)
    bubbleShadow.shadowOffset = NSSize(width: 0, height: -12)
    bubbleShadow.shadowBlurRadius = 24
    bubbleShadow.set()
    color(0.99, 0.98, 1).setFill()
    bubble.fill()
    NSGraphicsContext.restoreGraphicsState()

    color(0.43, 0.29, 0.78).setStroke()
    let clock = NSBezierPath(ovalIn: NSRect(x: 361, y: 381, width: 302, height: 302))
    clock.lineWidth = 35
    clock.stroke()
    let hands = NSBezierPath()
    hands.move(to: NSPoint(x: 512, y: 636))
    hands.line(to: NSPoint(x: 512, y: 532))
    hands.line(to: NSPoint(x: 598, y: 488))
    hands.lineWidth = 35
    hands.lineCapStyle = .round
    hands.lineJoinStyle = .round
    hands.stroke()
    color(0.43, 0.29, 0.78).setFill()
    NSBezierPath(ovalIn: NSRect(x: 493, y: 513, width: 38, height: 38)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try render(size: 1024).write(to: output.appendingPathComponent("AppIcon-preview.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Generated \(output.appendingPathComponent("AppIcon.icns").path)")
