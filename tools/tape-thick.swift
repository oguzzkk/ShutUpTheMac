import AppKit

/// Kalın çapraz bant denemeleri. Papyon görüntüsünün sebebi kalınlık değil,
/// bantların kısa olmasıydı: uzun bantta kesişme noktası ortada kalıyor ve
/// uçlar dışarı taştığı için "çapraz yapıştırılmış bant" olarak okunuyor.
func glyph(size: CGFloat, taped: Bool, big: Bool, tape: (angle: CGFloat, length: CGFloat, thickness: CGFloat)) {
    let lineWidth = max(1, size * (big ? 0.095 : 0.082))
    let inset: CGFloat = big ? 0.022 : 0.045
    let top: CGFloat = big ? 0.955 : 0.930
    let bottom: CGFloat = big ? 0.240 : 0.265

    let screen = NSRect(x: size * inset, y: size * bottom,
                        width: size * (1 - inset * 2), height: size * (top - bottom))
    let body = NSBezierPath(roundedRect: screen.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                            xRadius: size * 0.13, yRadius: size * 0.13)
    body.lineWidth = lineWidth
    body.stroke()

    let neckWidth = size * 0.10
    let neckBottom = size * (big ? 0.120 : 0.145)
    NSBezierPath(rect: NSRect(x: size * 0.5 - neckWidth / 2, y: neckBottom,
                              width: neckWidth, height: screen.minY - neckBottom + lineWidth)).fill()
    let footWidth = size * (big ? 0.54 : 0.50)
    NSBezierPath(roundedRect: NSRect(x: size * 0.5 - footWidth / 2, y: size * (big ? 0.075 : 0.090),
                                     width: footWidth, height: lineWidth * 1.15),
                 xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()

    let eyeY = screen.minY + screen.height * (taped ? 0.64 : 0.56)
    let eyeSize = size * (big ? 0.115 : 0.095)
    let eyeSpacing = size * (big ? 0.195 : 0.175)
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * eyeSpacing
        NSBezierPath(ovalIn: NSRect(x: x - eyeSize / 2, y: eyeY - eyeSize / 2,
                                    width: eyeSize, height: eyeSize)).fill()
    }

    let mouthY = screen.minY + screen.height * 0.26
    guard taped else {
        let halfMouth = size * (big ? 0.19 : 0.15)
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: size * 0.5 - halfMouth, y: mouthY))
        mouth.line(to: NSPoint(x: size * 0.5 + halfMouth, y: mouthY))
        mouth.lineWidth = lineWidth * 0.95
        mouth.lineCapStyle = .round
        mouth.stroke()
        return
    }

    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * eyeSpacing
        let brow = NSBezierPath()
        brow.move(to: NSPoint(x: x - sign * size * 0.068, y: eyeY + size * 0.072))
        brow.line(to: NSPoint(x: x + sign * size * 0.068, y: eyeY + size * 0.130))
        brow.lineWidth = lineWidth * 0.95
        brow.lineCapStyle = .round
        brow.stroke()
    }

    let angles: [CGFloat] = tape.angle == 0 ? [-9] : [-tape.angle, tape.angle]
    for angle in angles {
        let strip = NSBezierPath(rect: NSRect(x: -size * tape.length / 2, y: -size * tape.thickness / 2,
                                              width: size * tape.length, height: size * tape.thickness))
        let transform = NSAffineTransform()
        transform.translateX(by: size * 0.50, yBy: mouthY)
        transform.rotate(byDegrees: angle)
        strip.transform(using: transform as AffineTransform)
        strip.fill()
    }
}

let options: [(String, (angle: CGFloat, length: CGFloat, thickness: CGFloat))] = [
    ("ince (şu anki)", (26, 0.44, 0.055)),
    ("kalın, kısaltılmış", (20, 0.46, 0.085)),
    ("kalın, biraz dik", (24, 0.44, 0.082)),
    ("tek bant (eski)", (0, 0.52, 0.090)),
]

func render(size: CGFloat, taped: Bool, big: Bool, tape: (angle: CGFloat, length: CGFloat, thickness: CGFloat)) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.white.setFill(); NSColor.white.setStroke()
    glyph(size: size, taped: taped, big: big, tape: tape)
    image.unlockFocus()
    return image
}

let sheet = NSImage(size: NSSize(width: 1000, height: 320))
sheet.lockFocus()
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1000, height: 320).fill()

let barRect = NSRect(x: 0, y: 264, width: 1000, height: 56)
NSColor(calibratedRed: 0.29, green: 0.51, blue: 0.70, alpha: 1).setFill()
barRect.fill()
var x: CGFloat = 26
for (_, tape) in options {
    render(size: 36, taped: true, big: true, tape: tape)
        .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
    x += 54
}
x += 24
render(size: 36, taped: false, big: false, tape: options[0].1)
    .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
x += 54
render(size: 36, taped: false, big: true, tape: options[0].1)
    .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
NSAttributedString(string: "↑ gerçek boyut: dört bant seçeneği · sonra sakin (mevcut / İRİ)", attributes: [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
]).draw(at: NSPoint(x: x + 50, y: barRect.midY - 7))

for (index, option) in options.enumerated() {
    let originX = CGFloat(index) * 240 + 60
    NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: originX - 18, y: 70, width: 146, height: 146), xRadius: 16, yRadius: 16).fill()
    render(size: 110, taped: true, big: true, tape: option.1)
        .draw(at: NSPoint(x: originX, y: 88), from: .zero, operation: .sourceOver, fraction: 1)
    NSAttributedString(string: option.0, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
    ]).draw(at: NSPoint(x: originX - 18, y: 46))
}
sheet.unlockFocus()
if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/tape-thick.png"))
    print("hazır")
}
