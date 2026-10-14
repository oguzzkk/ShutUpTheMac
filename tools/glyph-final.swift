// Mevcut tasarım + çapraz bant, çizim alanını daha dolduran büyük hâl.
import AppKit

/// Çizim ölçüleri, gözlerin ve bandın asla çakışmaması için birlikte seçildi:
/// göz alt kenarı 0.575, bant üst sınırı ~0.535.
enum TapeStyle { case single, symmetric, asymmetric }

func macGlyph(size: CGFloat, taped: Bool, scaleUp: Bool, style: TapeStyle = .asymmetric) {
    let lw = max(1, size * (scaleUp ? 0.082 : 0.075))

    // Büyük hâlde kenar boşluğu azaltıldı: ekran gövdesi çerçeveyi daha çok dolduruyor.
    let screen = scaleUp
        ? NSRect(x: size * 0.045, y: size * 0.265, width: size * 0.91, height: size * 0.665)
        : NSRect(x: size * 0.10, y: size * 0.30, width: size * 0.80, height: size * 0.58)

    let body = NSBezierPath(roundedRect: screen.insetBy(dx: lw / 2, dy: lw / 2),
                            xRadius: size * 0.13, yRadius: size * 0.13)
    body.lineWidth = lw
    body.stroke()

    let neckWidth = size * 0.10
    let neckBottom = scaleUp ? size * 0.145 : size * 0.18
    NSBezierPath(rect: NSRect(x: size * 0.5 - neckWidth / 2, y: neckBottom,
                              width: neckWidth, height: screen.minY - neckBottom + lw)).fill()
    let footWidth = size * (scaleUp ? 0.50 : 0.44)
    NSBezierPath(roundedRect: NSRect(x: size * 0.5 - footWidth / 2, y: scaleUp ? size * 0.09 : size * 0.12,
                                     width: footWidth, height: lw * 1.15),
                 xRadius: lw / 2, yRadius: lw / 2).fill()

    // Gözler
    let eyeY = screen.minY + screen.height * (taped ? 0.56 : 0.50)
    let eyeSize = size * 0.095
    let eyeSpacing = size * 0.175
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * eyeSpacing
        NSBezierPath(ovalIn: NSRect(x: x - eyeSize / 2, y: eyeY - eyeSize / 2,
                                    width: eyeSize, height: eyeSize)).fill()
    }

    guard taped else {
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: size * 0.35, y: screen.minY + screen.height * 0.26))
        mouth.line(to: NSPoint(x: size * 0.65, y: screen.minY + screen.height * 0.26))
        mouth.lineWidth = lw * 0.95
        mouth.lineCapStyle = .round
        mouth.stroke()
        return
    }

    // Kızgın kaşlar
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * eyeSpacing
        let brow = NSBezierPath()
        brow.move(to: NSPoint(x: x - sign * size * 0.075, y: eyeY + size * 0.075))
        brow.line(to: NSPoint(x: x + sign * size * 0.075, y: eyeY + size * 0.145))
        brow.lineWidth = lw * 0.95
        brow.lineCapStyle = .round
        brow.stroke()
    }

    // Çapraz bant: sığ açılar, bant bandı gözlerin altında kalıyor
    let mouthY = screen.minY + screen.height * 0.26
    // (açı, uzunluk, kalınlık) üçlüleri
    let strips: [(CGFloat, CGFloat, CGFloat)]
    switch style {
    case .single:
        strips = [(-10, 0.46, 0.085)]
    case .symmetric:
        strips = [(-26, 0.44, 0.055), (26, 0.44, 0.055)]
    case .asymmetric:
        strips = [(-8, 0.46, 0.075), (34, 0.38, 0.058)]
    }

    for (angle, length, thickness) in strips {
        let strip = NSBezierPath(rect: NSRect(x: -size * length / 2, y: -size * thickness / 2,
                                              width: size * length, height: size * thickness))
        let transform = NSAffineTransform()
        transform.translateX(by: size * 0.50, yBy: mouthY)
        transform.rotate(byDegrees: angle)
        strip.transform(using: transform as AffineTransform)
        strip.fill()
    }
}

func render(size: CGFloat, taped: Bool, scaleUp: Bool, style: TapeStyle = .asymmetric, color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    color.setFill(); color.setStroke()
    macGlyph(size: size, taped: taped, scaleUp: scaleUp, style: style)
    image.unlockFocus()
    return image
}

let sheet = NSImage(size: NSSize(width: 860, height: 330))
sheet.lockFocus()
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 860, height: 330).fill()

let barRect = NSRect(x: 0, y: 274, width: 860, height: 56)
NSColor(calibratedRed: 0.29, green: 0.51, blue: 0.70, alpha: 1).setFill()
barRect.fill()

let styles: [(TapeStyle, String)] = [(.single, "tek bant"), (.symmetric, "simetrik X"), (.asymmetric, "asimetrik bant")]
var x: CGFloat = 26
for (style, _) in styles {
    render(size: 36, taped: true, scaleUp: true, style: style, color: .white)
        .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
    x += 58
}
render(size: 36, taped: false, scaleUp: true, color: .white)
    .draw(at: NSPoint(x: x, y: barRect.midY - 18), from: .zero, operation: .sourceOver, fraction: 1)
NSAttributedString(string: "↑ gerçek boyut (hepsi büyütülmüş gövde): tek bant / simetrik X / asimetrik / sakin", attributes: [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white,
]).draw(at: NSPoint(x: x + 48, y: barRect.midY - 7))

for (index, entry) in styles.enumerated() {
    let originX = CGFloat(index) * 280 + 75
    NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: originX - 20, y: 70, width: 150, height: 150), xRadius: 16, yRadius: 16).fill()
    render(size: 110, taped: true, scaleUp: true, style: entry.0, color: .white)
        .draw(at: NSPoint(x: originX, y: 90), from: .zero, operation: .sourceOver, fraction: 1)
    NSAttributedString(string: entry.1, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
    ]).draw(at: NSPoint(x: originX - 20, y: 44))
}
sheet.unlockFocus()
if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/glyph-final.png"))
    print("hazır")
}
