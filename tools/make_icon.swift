// Erzeugt Resources/AppIcon.icns: Papierfläche, ein Anführungszeichen in Ochsenblut.
// Aufruf: swift tools/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS-Icon-Raster: 824er Fläche mit 100er Rand
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    color(0xF6F1E7).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // feine Linie wie eine Satzspiegel-Kante
    color(0xD3C7B2).setFill()
    NSRect(x: 322 * s, y: 330 * s, width: 380 * s, height: 8 * s).fill()

    // Anführungszeichen, anhand der echten Glyphen-Grenzen über der Linie zentriert
    let size = 1100 * s
    let base = NSFont.systemFont(ofSize: size, weight: .regular)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.serif)!, size: size)!
    let glyph = NSAttributedString(string: "\u{201E}", attributes: [.font: font, .foregroundColor: color(0x8B3A2B)])
    let line = CTLineCreateWithAttributedString(glyph)
    let ink = CTLineGetImageBounds(line, nil)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.textPosition = CGPoint(x: (CGFloat(px) - ink.width) / 2 - ink.minX,
                               y: 410 * s - ink.minY)
    CTLineDraw(line, ctx)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
try render(1024).write(to: root.appendingPathComponent("docs/icon.png"))
print("→ \(out.path)")
