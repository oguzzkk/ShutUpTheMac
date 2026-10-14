// Uygulama ikonu: ağzına bant yapıştırılmış sinirli Mac.
// Xcode gerekmez; `swift tools/make-icon.swift` ile çalışır.
import AppKit

let sizes = [16, 32, 128, 256, 512, 1024]
let iconset = "build/ShutUpTheMac.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let cream = NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.95, alpha: 1)
let ink = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.18, alpha: 1)
let tape = NSColor(calibratedRed: 0.91, green: 0.80, blue: 0.52, alpha: 1)
let tapeEdge = NSColor(calibratedRed: 0.74, green: 0.61, blue: 0.34, alpha: 1)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Arka plan
    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.27, green: 0.23, blue: 0.38, alpha: 1),
                        NSColor(calibratedRed: 0.11, green: 0.09, blue: 0.17, alpha: 1)])?.draw(in: background, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    background.lineWidth = size * 0.012
    background.stroke()

    // Mac gövdesi
    let screen = NSRect(x: size * 0.155, y: size * 0.30, width: size * 0.69, height: size * 0.50)
    cream.setFill()
    NSBezierPath(roundedRect: screen, xRadius: size * 0.07, yRadius: size * 0.07).fill()
    NSBezierPath(rect: NSRect(x: size * 0.455, y: size * 0.215, width: size * 0.09, height: size * 0.09)).fill()
    NSBezierPath(roundedRect: NSRect(x: size * 0.325, y: size * 0.175, width: size * 0.35, height: size * 0.052),
                 xRadius: size * 0.026, yRadius: size * 0.026).fill()

    // Gözler
    let eyeSize = size * 0.062
    let eyeY = screen.midY + size * 0.075
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * size * 0.135
        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: x - eyeSize / 2, y: eyeY - eyeSize / 2, width: eyeSize, height: eyeSize)).fill()

        // Sinirli kaş: dış uç yukarıda, iç uç aşağıda
        let brow = NSBezierPath()
        brow.move(to: NSPoint(x: x - sign * size * 0.045, y: eyeY + size * 0.045))
        brow.line(to: NSPoint(x: x + sign * size * 0.050, y: eyeY + size * 0.085))
        brow.lineWidth = size * 0.022
        brow.lineCapStyle = .round
        ink.setStroke()
        brow.stroke()
    }

    // Ağza yapıştırılmış tek kalın bant
    let strip = NSBezierPath(roundedRect: NSRect(x: -size * 0.215, y: -size * 0.042,
                                                 width: size * 0.43, height: size * 0.084),
                             xRadius: size * 0.006, yRadius: size * 0.006)
    let transform = NSAffineTransform()
    transform.translateX(by: size * 0.50, yBy: screen.midY - size * 0.080)
    transform.rotate(byDegrees: -10)
    strip.transform(using: transform as AffineTransform)
    tape.setFill(); strip.fill()
    tapeEdge.setStroke(); strip.lineWidth = size * 0.007; strip.stroke()

    image.unlockFocus()
    return image
}

for size in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(size)x\(size).png"))
    if size >= 32 {
        let half = size / 2
        try? png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(half)x\(half)@2x.png"))
    }
}
print("iconset hazır")
