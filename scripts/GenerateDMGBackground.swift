import AppKit

// Background of the installer window. Icon centers must match the positions in package-dmg.sh.
let width = 660.0, height = 400.0
let appCenter = NSPoint(x: 170, y: 215), applicationsCenter = NSPoint(x: 490, y: 215)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func render(scale: CGFloat, to path: String) {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Não foi possível criar o bitmap") }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    let cg = context.cgContext
    // Top-left origin, like Finder's icon coordinates.
    cg.translateBy(x: 0, y: height * scale)
    cg.scaleBy(x: scale, y: -scale)

    color(0xF4F3F7).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color textColor: NSColor, y: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: textColor, .paragraphStyle: style
        ]).draw(in: NSRect(x: 0, y: y, width: width, height: size * 1.5))
    }
    draw("Arraste o Notch para Aplicativos", size: 22, weight: .bold, color: color(0x1D1D1F), y: 46)
    draw("É só soltar o ícone na pasta. Depois, abra o Notch pelo Launchpad.", size: 13, weight: .regular, color: color(0x55555C), y: 82)

    let arrowColor = color(0x5B5BD6)
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: appCenter.x + 82, y: appCenter.y))
    shaft.line(to: NSPoint(x: applicationsCenter.x - 92, y: appCenter.y))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.setLineDash([2, 9], count: 2, phase: 0)
    arrowColor.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    let tip = NSPoint(x: applicationsCenter.x - 78, y: appCenter.y)
    head.move(to: NSPoint(x: tip.x - 12, y: tip.y - 10))
    head.line(to: tip)
    head.line(to: NSPoint(x: tip.x - 12, y: tip.y + 10))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    draw("Se o macOS perguntar, confirme que deseja abrir o Notch.", size: 11.5, weight: .regular, color: color(0x6E6E75), y: 318)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Falha ao gerar PNG") }
    try! data.write(to: URL(fileURLWithPath: path))
}

guard CommandLine.arguments.count == 3 else { fatalError("Use GenerateDMGBackground.swift saida.png saida@2x.png") }
render(scale: 1, to: CommandLine.arguments[1])
render(scale: 2, to: CommandLine.arguments[2])
