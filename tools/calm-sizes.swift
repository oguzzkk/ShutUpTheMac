import AppKit

/// Sakin hâl için üç kademe: mevcut, orta, iri. Bantlı hâl referans olarak yanında.
func glyph(size: CGFloat, taped: Bool, boost: Int) {
    // boost: 0 = mevcut, 1 = orta, 2 = iri
    let lineWidth = max(1, size * [0.082, 0.090, 0.098][boost])
    let inset: CGFloat = [0.045, 0.030, 0.018][boost]
    let top: CGFloat = [0.930, 0.945, 0.960][boost]
    let bottom: CGFloat = [0.265, 0.250, 0.235][boost]

    let screen = NSRect(x: size * inset, y: size * bottom,
                        width: size * (1 - inset * 2), height: size * (top - bottom))
    let body = NSBezierPath(roundedRect: screen.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                            xRadius: size * 0.13, yRadius: size * 0.13)
    body.lineWidth = lineWidth
    body.stroke()

    let neckWidth = size * 0.10
    let neckBottom = size * [0.145, 0.130, 0.115][boost]
    NSBezierPath(rect: NSRect(x: size * 0.5 - neckWidth / 2, y: neckBottom,
                              width: neckWidth, height: screen.minY - neckBottom + lineWidth)).fill()
    let footWidth = size * [0.50, 0.52, 0.54][boost]
    NSBezierPath(roundedRect: NSRect(x: size * 0.5 - footWidth / 2, y: size * [0.090, 0.080, 0.070][boost],
                                     width: footWidth, height: lineWidth * 1.15),
                 xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()

    let eyeY = screen.minY + screen.height * (taped ? 0.56 : 0.50)
    let eyeSize = size * [0.095, 0.105, 0.115][boost]
    let eyeSpacing = size * [0.175, 0.185, 0.195][boost]
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * eyeSpacing
        NSBezierPath(ovalIn: NSRect(x: x - eyeSize / 2, y: eyeY - eyeSize / 2,
                                    width: eyeSize, height: eyeSize)).fill()
    }

    let mouthY = screen.minY + screen.height * 0.26
    guard taped else {
        let halfMouth = size * [0.15, 0.17, 0.19][boost]
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
        brow.move(to: NSPoint(x: x - sign * size * 0.075, y: eyeY + size * 0.075))
        brow.line(to: NSPoint(x: x + sign * size * 0.075, y: eyeY + size * 0.145))
        brow.lineWidth = lineWidth * 0.95
        brow.lineCapStyle = .round
        brow.stroke()
    }
    for angle in [-26.0, 26.0] as [CGFloat] {
        let strip = NSBezierPath(rect: NSRect(x: -size * 0.22, y: -size * 0.0275,
                                              width: size * 0.44, height: size * 0.055))
        let transform = NSAffineTransform()
        transform.translateX(by: size * 0.50, yBy: mouthY)
        transform.rotate(byDegrees: angle)
        strip.transform(using: transform as AffineTransform)
        strip.fill()
    }
}

func render(size: CGFloat, taped: Bool, boost: Int, color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    color.setFill(); color.setStroke()
    glyph(size: size, taped: taped, boost: boost)
    image.unlockFocus()
    return image
}

let sheet = NSImage(size: NSSize(width: 820, height: 300))
sheet.lockFocus()
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 820, height: 300).fill()

let barRect = NSRect(x: 0, y: 244, width: 820, height: 56)
NSColor(calibratedRed: 0.29, green: 0.51, blue: 0.70, alpha: 1).setFill()
barRect.fill()
var x: CGFloat = 26
for boost in 0...2 {
    render(size: 36, taped: false, boost: boost, color: .white)
        .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
    x += 56
}
x += 20
render(size: 36, taped: true, boost: 0, color: .white)
    .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
NSAttributedString(string: "↑ gerçek boyut: sakin mevcut / orta / iri   —   sağdaki: bantlı (referans)", attributes: [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
]).draw(at: NSPoint(x: x + 56, y: barRect.midY - 7))

let labels = ["mevcut", "orta", "iri"]
for boost in 0...2 {
    let originX = CGFloat(boost) * 270 + 75
    NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: originX - 20, y: 60, width: 150, height: 150), xRadius: 16, yRadius: 16).fill()
    render(size: 110, taped: false, boost: boost, color: .white)
        .draw(at: NSPoint(x: originX, y: 80), from: .zero, operation: .sourceOver, fraction: 1)
    NSAttributedString(string: labels[boost], attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
    ]).draw(at: NSPoint(x: originX - 20, y: 36))
}
sheet.unlockFocus()
if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/calm-sizes.png"))
    print("hazır")
}
