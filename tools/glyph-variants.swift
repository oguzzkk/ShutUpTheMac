// Menü çubuğu simgesinin susturulmuş hâli için adaylar.
import AppKit

func macBase(size: CGFloat, lineWidth: CGFloat) {
    let screen = NSRect(x: size * 0.10, y: size * 0.30, width: size * 0.80, height: size * 0.58)
    let body = NSBezierPath(roundedRect: screen.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                            xRadius: size * 0.12, yRadius: size * 0.12)
    body.lineWidth = lineWidth
    body.stroke()
    NSBezierPath(rect: NSRect(x: size * 0.45, y: size * 0.18, width: size * 0.10, height: size * 0.13)).fill()
    NSBezierPath(roundedRect: NSRect(x: size * 0.28, y: size * 0.12, width: size * 0.44, height: lineWidth * 1.1),
                 xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()
}

func eyes(size: CGFloat, y: CGFloat, diameter: CGFloat) {
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * size * 0.16
        NSBezierPath(ovalIn: NSRect(x: x - diameter / 2, y: y - diameter / 2,
                                    width: diameter, height: diameter)).fill()
    }
}

func angryBrows(size: CGFloat, lineWidth: CGFloat, eyeY: CGFloat) {
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = size * 0.50 + sign * size * 0.16
        let brow = NSBezierPath()
        brow.move(to: NSPoint(x: x - sign * size * 0.07, y: eyeY + size * 0.08))
        brow.line(to: NSPoint(x: x + sign * size * 0.07, y: eyeY + size * 0.14))
        brow.lineWidth = lineWidth * 0.9
        brow.lineCapStyle = .round
        brow.stroke()
    }
}

func strip(size: CGFloat, angle: CGFloat, length: CGFloat, thickness: CGFloat, y: CGFloat) {
    let path = NSBezierPath(rect: NSRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness))
    let transform = NSAffineTransform()
    transform.translateX(by: size * 0.50, yBy: y)
    transform.rotate(byDegrees: angle)
    path.transform(using: transform as AffineTransform)
    path.fill()
}

func crossStrokes(size: CGFloat, y: CGFloat, half: CGFloat, width: CGFloat) {
    for sign in [-1.0, 1.0] as [CGFloat] {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: size * 0.50 - half, y: y - sign * half))
        path.line(to: NSPoint(x: size * 0.50 + half, y: y + sign * half))
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }
}

let variants: [(String, (CGFloat) -> Void)] = [
    ("1 mevcut: tek bant", { size in
        let lw = max(1, size * 0.075)
        macBase(size: size, lineWidth: lw)
        eyes(size: size, y: size * 0.62, diameter: size * 0.09)
        angryBrows(size: size, lineWidth: lw, eyeY: size * 0.62)
        strip(size: size, angle: -9, length: size * 0.48, thickness: size * 0.09, y: size * 0.45)
    }),
    ("2 çarpı + kızgın kaş", { size in
        let lw = max(1, size * 0.075)
        macBase(size: size, lineWidth: lw)
        eyes(size: size, y: size * 0.68, diameter: size * 0.085)
        angryBrows(size: size, lineWidth: lw * 0.85, eyeY: size * 0.68)
        crossStrokes(size: size, y: size * 0.48, half: size * 0.095, width: lw)
    }),
    ("3 çarpı, kaşsız", { size in
        let lw = max(1, size * 0.075)
        macBase(size: size, lineWidth: lw)
        eyes(size: size, y: size * 0.68, diameter: size * 0.095)
        crossStrokes(size: size, y: size * 0.48, half: size * 0.105, width: lw)
    }),
    ("4 bant çarpı + kaş", { size in
        let lw = max(1, size * 0.075)
        macBase(size: size, lineWidth: lw)
        eyes(size: size, y: size * 0.68, diameter: size * 0.085)
        angryBrows(size: size, lineWidth: lw * 0.85, eyeY: size * 0.68)
        strip(size: size, angle: -30, length: size * 0.26, thickness: size * 0.065, y: size * 0.48)
        strip(size: size, angle: 30, length: size * 0.26, thickness: size * 0.065, y: size * 0.48)
    }),
    ("5 geniş çarpı + kaş", { size in
        let lw = max(1, size * 0.075)
        macBase(size: size, lineWidth: lw)
        eyes(size: size, y: size * 0.70, diameter: size * 0.08)
        angryBrows(size: size, lineWidth: lw * 0.8, eyeY: size * 0.70)
        crossStrokes(size: size, y: size * 0.46, half: size * 0.13, width: lw * 0.95)
    }),
    ("6 çarpı + düz ağız", { size in
        let lw = max(1, size * 0.075)
        macBase(size: size, lineWidth: lw)
        eyes(size: size, y: size * 0.70, diameter: size * 0.085)
        let mouth = NSBezierPath()
        mouth.move(to: NSPoint(x: size * 0.36, y: size * 0.46))
        mouth.line(to: NSPoint(x: size * 0.64, y: size * 0.46))
        mouth.lineWidth = lw * 0.85
        mouth.lineCapStyle = .round
        mouth.stroke()
        crossStrokes(size: size, y: size * 0.46, half: size * 0.075, width: lw * 0.85)
    }),
]


func render(_ draw: (CGFloat) -> Void, size: CGFloat, color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    color.setFill(); color.setStroke()
    draw(size)
    image.unlockFocus()
    return image
}

let scale: CGFloat = 2
let big: CGFloat = 110
let columns = 3
let cellWidth: CGFloat = 230
let cellHeight: CGFloat = 185
let rows = (variants.count + columns - 1) / columns
let sheetSize = NSSize(width: CGFloat(columns) * cellWidth, height: CGFloat(rows) * cellHeight + 70)

let sheet = NSImage(size: sheetSize)
sheet.lockFocus()
NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
NSRect(origin: .zero, size: sheetSize).fill()

// Üstte gerçek boyut şeridi
let barHeight: CGFloat = 46
let barRect = NSRect(x: 0, y: sheetSize.height - barHeight, width: sheetSize.width, height: barHeight)
NSColor(calibratedRed: 0.29, green: 0.51, blue: 0.70, alpha: 1).setFill()
barRect.fill()
var x: CGFloat = 24
for (_, draw) in variants {
    render(draw, size: 18 * scale, color: .white)
        .draw(at: NSPoint(x: x, y: barRect.midY - 18 * scale / 2), from: .zero, operation: .sourceOver, fraction: 1)
    x += 18 * scale + 26
}
NSAttributedString(string: "↑ menü çubuğunda gerçek boyut (18pt)", attributes: [
    .font: NSFont.systemFont(ofSize: 11, weight: .medium),
    .foregroundColor: NSColor.white,
]).draw(at: NSPoint(x: x + 10, y: barRect.midY - 7))

for (index, variant) in variants.enumerated() {
    let column = index % columns
    let row = index / columns
    let originX = CGFloat(column) * cellWidth + (cellWidth - big) / 2
    let originY = sheetSize.height - barHeight - CGFloat(row + 1) * cellHeight + 52

    NSColor(calibratedWhite: 0.20, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: originX - 18, y: originY - 18, width: big + 36, height: big + 36),
                 xRadius: 14, yRadius: 14).fill()
    render(variant.1, size: big, color: .white)
        .draw(at: NSPoint(x: originX, y: originY), from: .zero, operation: .sourceOver, fraction: 1)

    NSAttributedString(string: variant.0, attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1),
    ]).draw(at: NSPoint(x: originX - 18, y: originY - 40))
}
sheet.unlockFocus()

if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/glyph-variants.png"))
    print("hazır")
}
