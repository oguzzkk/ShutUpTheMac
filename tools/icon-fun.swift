// Daha şakacı ikon adayları: karakterli, renkli, bantlı.
import AppKit

let tile: CGFloat = 220
let padding: CGFloat = 26
let labelHeight: CGFloat = 26
let columns = 3

let cream  = NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.95, alpha: 1)
let tape   = NSColor(calibratedRed: 0.91, green: 0.80, blue: 0.52, alpha: 0.95)
let tapeEdge = NSColor(calibratedRed: 0.76, green: 0.63, blue: 0.36, alpha: 1)
let skin   = NSColor(calibratedRed: 1.00, green: 0.82, blue: 0.33, alpha: 1)
let ink    = NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.18, alpha: 1)
let hotRed = NSColor(calibratedRed: 0.98, green: 0.35, blue: 0.33, alpha: 1)
let white  = NSColor(calibratedWhite: 0.99, alpha: 1)

struct Variant {
    let name: String
    let background: [NSColor]
    let draw: (CGFloat) -> Void
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// Bir bant şeridi: hafif eğik, kenarları koyu, uçları yırtık hissi versin diye kısa.
func tapeStrip(center: NSPoint, length: CGFloat, thickness: CGFloat, angle: CGFloat) {
    let path = roundedRect(NSRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness),
                           radius: thickness * 0.12)
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: angle)
    path.transform(using: transform as AffineTransform)
    tape.setFill(); path.fill()
    tapeEdge.setStroke(); path.lineWidth = thickness * 0.10; path.stroke()
}

func eyes(centerY: CGFloat, side: CGFloat, spacing: CGFloat, size: CGFloat, angry: Bool) {
    for sign in [-1.0, 1.0] as [CGFloat] {
        let x = side / 2 + sign * spacing
        let eye = NSBezierPath(ovalIn: NSRect(x: x - size / 2, y: centerY - size / 2, width: size, height: size))
        ink.setFill(); eye.fill()

        guard angry else { continue }
        // Sinirli kaş: dış uç yukarıda, iç uç (buruna yakın) aşağıda.
        let inner = NSPoint(x: x + (sign < 0 ? size * 1.0 : -size * 1.0), y: centerY + size * 0.9)
        let outer = NSPoint(x: x + (sign < 0 ? -size * 1.0 : size * 1.0), y: centerY + size * 1.9)
        let brow = NSBezierPath()
        brow.move(to: inner)
        brow.line(to: outer)
        brow.lineWidth = size * 0.45
        brow.lineCapStyle = .round
        ink.setStroke(); brow.stroke()
    }
}

/// Mac ekranı: gövde + ayak
func macBody(side: CGFloat) -> NSRect {
    let screen = NSRect(x: side * 0.18, y: side * 0.30, width: side * 0.64, height: side * 0.46)
    cream.setFill()
    roundedRect(screen, radius: side * 0.07).fill()

    let neck = NSRect(x: side * 0.45, y: side * 0.21, width: side * 0.10, height: side * 0.10)
    cream.setFill(); NSBezierPath(rect: neck).fill()
    let foot = roundedRect(NSRect(x: side * 0.33, y: side * 0.17, width: side * 0.34, height: side * 0.055),
                           radius: side * 0.025)
    cream.setFill(); foot.fill()
    return screen
}

let variants: [Variant] = [
    Variant(name: "A · bantlı Mac", background: [NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.36, alpha: 1),
                                                NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.18, alpha: 1)]) { side in
        let screen = macBody(side: side)
        eyes(centerY: screen.midY + side * 0.07, side: side, spacing: side * 0.11, size: side * 0.045, angry: false)
        tapeStrip(center: NSPoint(x: side / 2, y: screen.midY - side * 0.06), length: side * 0.46, thickness: side * 0.085, angle: -12)
        tapeStrip(center: NSPoint(x: side / 2, y: screen.midY - side * 0.06), length: side * 0.46, thickness: side * 0.085, angle: 14)
    },

    Variant(name: "B · sinirli bantlı Mac", background: [NSColor(calibratedRed: 0.24, green: 0.20, blue: 0.34, alpha: 1),
                                                        NSColor(calibratedRed: 0.11, green: 0.09, blue: 0.17, alpha: 1)]) { side in
        let screen = macBody(side: side)
        eyes(centerY: screen.midY + side * 0.06, side: side, spacing: side * 0.115, size: side * 0.042, angry: true)
        tapeStrip(center: NSPoint(x: side / 2, y: screen.midY - side * 0.075), length: side * 0.44, thickness: side * 0.08, angle: -10)
    },

    Variant(name: "C · şşşt surat", background: [NSColor(calibratedRed: 0.27, green: 0.33, blue: 0.52, alpha: 1),
                                                 NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.28, alpha: 1)]) { side in
        let face = NSBezierPath(ovalIn: NSRect(x: side * 0.17, y: side * 0.17, width: side * 0.66, height: side * 0.66))
        skin.setFill(); face.fill()
        eyes(centerY: side * 0.62, side: side, spacing: side * 0.14, size: side * 0.055, angry: false)
        let mouth = NSBezierPath(ovalIn: NSRect(x: side * 0.455, y: side * 0.345, width: side * 0.09, height: side * 0.06))
        ink.setFill(); mouth.fill()
        // parmak ağzın ÜSTÜNDE dursun diye merkez aşağı alındı
        let finger = roundedRect(NSRect(x: -side * 0.042, y: -side * 0.15, width: side * 0.084, height: side * 0.30),
                                 radius: side * 0.042)
        let transform = NSAffineTransform()
        transform.translateX(by: side * 0.50, yBy: side * 0.375)
        transform.rotate(byDegrees: -8)
        finger.transform(using: transform as AffineTransform)
        skin.setFill(); finger.fill()
        ink.setStroke(); finger.lineWidth = side * 0.011; finger.stroke()
        // el: çenenin altından giren küçük yumru
        let hand = roundedRect(NSRect(x: side * 0.40, y: side * 0.145, width: side * 0.20, height: side * 0.11), radius: side * 0.05)
        skin.setFill(); hand.fill()
        ink.setStroke(); hand.lineWidth = side * 0.011; hand.stroke()
    },

    Variant(name: "D · SHHH!", background: [NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.28, alpha: 1),
                                            NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.20, alpha: 1)]) { side in
        let text = NSAttributedString(string: "SHHH!", attributes: [
            .font: NSFont.systemFont(ofSize: side * 0.21, weight: .black),
            .foregroundColor: ink,
        ])
        let size = text.size()
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: side / 2, yBy: side / 2)
        transform.rotate(byDegrees: -8)
        transform.concat()
        text.draw(at: NSPoint(x: -size.width / 2, y: -size.height / 2))
        NSGraphicsContext.restoreGraphicsState()
        ink.setStroke()
        for index in 0..<3 {
            let line = NSBezierPath()
            let y = side * (0.70 + CGFloat(index) * 0.055)
            line.move(to: NSPoint(x: side * (0.22 + CGFloat(index) * 0.04), y: y))
            line.line(to: NSPoint(x: side * (0.40 + CGFloat(index) * 0.04), y: y))
            line.lineWidth = side * 0.022
            line.lineCapStyle = .round
            line.stroke()
        }
    },

    Variant(name: "E · fermuar surat", background: [NSColor(calibratedRed: 0.17, green: 0.42, blue: 0.47, alpha: 1),
                                                    NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.26, alpha: 1)]) { side in
        let face = NSBezierPath(ovalIn: NSRect(x: side * 0.17, y: side * 0.17, width: side * 0.66, height: side * 0.66))
        skin.setFill(); face.fill()
        eyes(centerY: side * 0.60, side: side, spacing: side * 0.13, size: side * 0.055, angry: false)
        let zip = NSBezierPath()
        zip.move(to: NSPoint(x: side * 0.32, y: side * 0.40))
        zip.line(to: NSPoint(x: side * 0.68, y: side * 0.40))
        zip.lineWidth = side * 0.022
        ink.setStroke(); zip.stroke()
        for index in 0..<7 {
            let x = side * (0.335 + CGFloat(index) * 0.052)
            let tooth = NSBezierPath()
            tooth.move(to: NSPoint(x: x, y: side * 0.378))
            tooth.line(to: NSPoint(x: x, y: side * 0.422))
            tooth.lineWidth = side * 0.016
            tooth.lineCapStyle = .round
            ink.setStroke(); tooth.stroke()
        }
        let pull = roundedRect(NSRect(x: side * 0.655, y: side * 0.345, width: side * 0.075, height: side * 0.055), radius: side * 0.018)
        hotRed.setFill(); pull.fill()
    },

    Variant(name: "F · fermuarlı Mac", background: [NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.40, alpha: 1),
                                                    NSColor(calibratedRed: 0.07, green: 0.16, blue: 0.21, alpha: 1)]) { side in
        let screen = macBody(side: side)
        eyes(centerY: screen.midY + side * 0.07, side: side, spacing: side * 0.11, size: side * 0.045, angry: false)
        let y = screen.midY - side * 0.055
        let zip = NSBezierPath()
        zip.move(to: NSPoint(x: side * 0.30, y: y))
        zip.line(to: NSPoint(x: side * 0.70, y: y))
        zip.lineWidth = side * 0.020
        ink.setStroke(); zip.stroke()
        for index in 0..<8 {
            let x = side * (0.315 + CGFloat(index) * 0.051)
            let tooth = NSBezierPath()
            tooth.move(to: NSPoint(x: x, y: y - side * 0.021))
            tooth.line(to: NSPoint(x: x, y: y + side * 0.021))
            tooth.lineWidth = side * 0.015
            tooth.lineCapStyle = .round
            ink.setStroke(); tooth.stroke()
        }
        let pull = roundedRect(NSRect(x: side * 0.675, y: y - side * 0.028, width: side * 0.07, height: side * 0.055), radius: side * 0.018)
        hotRed.setFill(); pull.fill()
    },
]


let rows = (variants.count + columns - 1) / columns
let sheetWidth = CGFloat(columns) * tile + CGFloat(columns + 1) * padding
let sheetHeight = CGFloat(rows) * (tile + labelHeight) + CGFloat(rows + 1) * padding

let sheet = NSImage(size: NSSize(width: sheetWidth, height: sheetHeight))
sheet.lockFocus()
NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight).fill()

for (index, variant) in variants.enumerated() {
    let column = index % columns
    let row = index / columns
    let x = padding + CGFloat(column) * (tile + padding)
    let y = sheetHeight - padding - CGFloat(row + 1) * tile - CGFloat(row) * (labelHeight + padding)

    let icon = NSImage(size: NSSize(width: tile, height: tile))
    icon.lockFocus()
    let inset = tile * 0.06
    let rect = NSRect(x: inset, y: inset, width: tile - inset * 2, height: tile - inset * 2)
    let background = roundedRect(rect, radius: tile * 0.22)
    NSGradient(colors: variant.background)?.draw(in: background, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    background.lineWidth = tile * 0.012
    background.stroke()
    variant.draw(tile)
    icon.unlockFocus()
    icon.draw(in: NSRect(x: x, y: y, width: tile, height: tile))

    let label = NSAttributedString(string: variant.name, attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1),
    ])
    label.draw(at: NSPoint(x: x + 4, y: y - labelHeight + 6))
}
sheet.unlockFocus()

if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/icon-fun2.png"))
    print("hazır: /tmp/icon-fun2.png")
}
