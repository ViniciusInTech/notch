import AppKit

// Editable vector artwork, rasterized by macOS. No external design tools required.
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

guard CommandLine.arguments.count == 2,
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Use GenerateIcon.swift /absolute/path/AppIcon.png")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 192, yRadius: 192)
let shadow = NSShadow()
shadow.shadowColor = color(0x060916, alpha: 0.25)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
color(0x172036).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(colors: [color(0x12192B), color(0x344A70), color(0x75699E)])!
    .draw(in: tile, angle: 45)
let halo = NSBezierPath(ovalIn: NSRect(x: 150, y: 170, width: 720, height: 670))
NSGradient(starting: color(0xB8A6FF, alpha: 0.25), ending: color(0x889ED2, alpha: 0))!
    .draw(in: halo, relativeCenterPosition: NSPoint(x: 0.1, y: 0.1))
NSGraphicsContext.restoreGraphicsState()
color(0xFFFFFF, alpha: 0.16).setStroke()
tile.lineWidth = 2
tile.stroke()

let island = NSBezierPath(roundedRect: NSRect(x: 206, y: 352, width: 612, height: 320), xRadius: 112, yRadius: 112)
NSGraphicsContext.saveGraphicsState()
let islandShadow = NSShadow()
islandShadow.shadowColor = color(0x02030B, alpha: 0.6)
islandShadow.shadowBlurRadius = 34
islandShadow.shadowOffset = NSSize(width: 0, height: -22)
islandShadow.set()
color(0x070B16).setFill()
island.fill()
NSGraphicsContext.restoreGraphicsState()
color(0xD8E2FF, alpha: 0.15).setStroke()
island.lineWidth = 2
island.stroke()

let heights: [CGFloat] = [72, 132, 190, 132, 72]
for (index, height) in heights.enumerated() {
    let bar = NSBezierPath(roundedRect: NSRect(x: 364 + CGFloat(index) * 68, y: 512 - height / 2,
                                               width: 24, height: height), xRadius: 12, yRadius: 12)
    NSGradient(colors: [color(0x80E4DF), color(0xAEAEFF), color(0xE1C9FF)])!
        .draw(in: bar, angle: 55)
}
let camera = NSBezierPath(roundedRect: NSRect(x: 470, y: 724, width: 84, height: 12), xRadius: 6, yRadius: 6)
color(0xD9E6FF, alpha: 0.45).setFill()
camera.fill()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
