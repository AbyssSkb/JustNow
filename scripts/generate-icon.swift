#!/usr/bin/env swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)
let manager = FileManager.default
let sourceURL = root.appendingPathComponent("Resources/AppIcon-source.png")
guard let source = NSImage(contentsOf: sourceURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      source.width == source.height else {
    fatalError("Expected a square PNG at \(sourceURL.path)")
}
try manager.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: iconset) }

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.clear(bounds)
    context.interpolationQuality = .high
    context.draw(source, in: bounds)
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try render(size: 1024).write(to: output.appendingPathComponent("AppIcon-preview.png"))
let brandResources = root.appendingPathComponent("Sources/JustNow/Resources", isDirectory: true)
try manager.createDirectory(at: brandResources, withIntermediateDirectories: true)
try render(size: 256).write(to: brandResources.appendingPathComponent("BrandMark.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Generated \(output.appendingPathComponent("AppIcon.icns").path)")
