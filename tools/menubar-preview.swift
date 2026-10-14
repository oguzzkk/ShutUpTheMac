// Menü çubuğu simgesinin gerçek ölçekte nasıl durduğunu gösterir.
import AppKit

/// Bantlı Mac simgesi — tek renk (şablon simge mantığı).
/// `taped`: susturulmuş bir şey varsa Mac'in ağzına bant yapışıyor.
func drawMacGlyph(size: CGFloat, taped: Bool, color: NSColor) {
    color.setStroke()
    color.setFill()

    let lineWidth = max(1, size * 0.075)

    // Ekran gövdesi
    let screen = NSRect(x: size * 0.10, y: size * 0.30, width: size * 0.80, height: size * 0.58)
    let body = NSBezierPath(roundedRect: screen.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                            xRadius: size * 0.12, yRadius: size * 0.12)
    body.lineWidth = lineWidth
    body.stroke()

    // Ayak
    let neck = NSBezierPath(rect: NSRect(x: size * 0.45, y: size * 0.18, width: size * 0.10, height: size * 0.13))
    neck.fill()
    let foot = NSBezierPath(roundedRect: NSRect(x: size * 0.28, y: size * 0.12, width: size * 0.44, height: lineWidth * 1.1),
                            xRadius: lineWidth / 2, yRadius: lineWidth / 2)
    foot.fill()

    // Gözler
    let eyeSize = size * 0.09
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * size * 0.16
        NSBezierPath(ovalIn: NSRect(x: x - eyeSize / 2, y: size * 0.62 - eyeSize / 2,
                                    width: eyeSize, height: eyeSize)).fill()
    }

    if taped {
        // Sinirli kaşlar
        for sign in [-1.0, 1.0] as [CGFloat] {
            let x = size * 0.50 + sign * size * 0.16
            let brow = NSBezierPath()
            brow.move(to: NSPoint(x: x - sign * size * 0.07, y: size * 0.70))
            brow.line(to: NSPoint(x: x + sign * size * 0.07, y: size * 0.76))
            brow.lineWidth = lineWidth * 0.9
            brow.lineCapStyle = .round
            brow.stroke()
        }
        // Bant
        let tape = NSBezierPath(rect: NSRect(x: -size * 0.24, y: -size * 0.045, width: size * 0.48, height: size * 0.09))
        let transform = NSAffineTransform()
        transform.translateX(by: size * 0.50, yBy: size * 0.45)
        transform.rotate(byDegrees: -9)
        tape.transform(using: transform as AffineTransform)
        tape.fill()
    } else {
        // Sakin ağız
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: size * 0.36, y: size * 0.45))
        mouth.line(to: NSPoint(x: size * 0.64, y: size * 0.45))
        mouth.lineWidth = lineWidth * 0.9
        mouth.lineCapStyle = .round
        mouth.stroke()
    }
}

func glyphImage(size: CGFloat, taped: Bool, color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    drawMacGlyph(size: size, taped: taped, color: color)
    image.unlockFocus()
    return image
}

// --- Önizleme tablosu ---
let scale: CGFloat = 2            // Retina
let barHeight: CGFloat = 24 * scale
let sheetWidth: CGFloat = 760 * scale / 2
let sheetHeight: CGFloat = 260

let sheet = NSImage(size: NSSize(width: sheetWidth, height: sheetHeight))
sheet.lockFocus()
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

// Kullanıcının menü çubuğu mavisi
let barColor = NSColor(calibratedRed: 0.29, green: 0.51, blue: 0.70, alpha: 1)
let barRect = NSRect(x: 0, y: sheetHeight - barHeight, width: sheetWidth, height: barHeight)
barColor.setFill()
barRect.fill()

// Menü çubuğunda gerçek ölçek: 18pt simge
let iconSize: CGFloat = 18 * scale
var x = sheetWidth - 30
let symbols = ["battery.75", "wifi", "moon.fill", "bluetooth"]
for name in symbols {
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 13 * scale, weight: .regular)) else { continue }
    x -= iconSize + 10
    NSColor.white.set()
    let rect = NSRect(x: x, y: barRect.midY - symbol.size.height / 2, width: symbol.size.width, height: symbol.size.height)
    symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    rect.fill(using: .sourceAtop)
}

// Bizim simgemiz: önce sakin, sonra bantlı
x -= iconSize + 14
glyphImage(size: iconSize, taped: false, color: .white)
    .draw(at: NSPoint(x: x, y: barRect.midY - iconSize / 2), from: .zero, operation: .sourceOver, fraction: 1)
x -= iconSize + 14
glyphImage(size: iconSize, taped: true, color: .white)
    .draw(at: NSPoint(x: x, y: barRect.midY - iconSize / 2), from: .zero, operation: .sourceOver, fraction: 1)

// Büyütülmüş hâlleri
let labels = ["sessiz hâl (hiçbir şey kısılmamış)", "bantlı hâl (bir şey susturulmuş)"]
for (index, taped) in [false, true].enumerated() {
    let big: CGFloat = 120
    let originX = 60 + CGFloat(index) * 320
    let originY: CGFloat = 60
    NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: originX - 20, y: originY - 20, width: big + 40, height: big + 40),
                 xRadius: 14, yRadius: 14).fill()
    glyphImage(size: big, taped: taped, color: .white)
        .draw(at: NSPoint(x: originX, y: originY), from: .zero, operation: .sourceOver, fraction: 1)

    NSAttributedString(string: labels[index], attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1),
    ]).draw(at: NSPoint(x: originX - 18, y: originY - 42))
}

NSAttributedString(string: "↑ menü çubuğunda gerçek boyut (18pt)", attributes: [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.7, alpha: 1),
]).draw(at: NSPoint(x: sheetWidth - 330, y: sheetHeight - barHeight - 26))

sheet.unlockFocus()
if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/menubar-preview.png"))
    print("hazır")
}
