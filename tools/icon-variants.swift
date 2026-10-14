// İkon adaylarını tek bir karşılaştırma tablosunda üretir.
import AppKit

let tile: CGFloat = 200
let padding: CGFloat = 24
let labelHeight: CGFloat = 26
let columns = 3

struct Variant {
    let name: String
    let draw: (CGFloat) -> Void      // verilen kenar uzunluğunda sembolü çizer
}

func symbol(_ name: String, side: CGFloat, scale: CGFloat = 0.46,
            colors: [NSColor] = [NSColor(calibratedRed: 0.97, green: 0.98, blue: 1, alpha: 1)],
            offset: CGPoint = .zero) {
    var configuration = NSImage.SymbolConfiguration(pointSize: side * scale, weight: .semibold)
    configuration = configuration.applying(NSImage.SymbolConfiguration(paletteColors: colors))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return }
    let size = image.size
    image.draw(at: NSPoint(x: (side - size.width) / 2 + offset.x, y: (side - size.height) / 2 + offset.y),
               from: .zero, operation: .sourceOver, fraction: 1)
}

let white = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.00, alpha: 1)
let red = NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.38, alpha: 1)
let amber = NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.35, alpha: 1)

/// Elle çizilen "şşşt" — dudak + üstüne gelen parmak.
func drawShush(side: CGFloat) {
    let center = NSPoint(x: side / 2, y: side * 0.40)

    // Dudaklar: geniş ve yassı olmalı, yoksa göze benziyor
    let lipWidth = side * 0.52
    let lipHeight = side * 0.10
    let lips = NSBezierPath()
    lips.move(to: NSPoint(x: center.x - lipWidth / 2, y: center.y))
    lips.curve(to: NSPoint(x: center.x + lipWidth / 2, y: center.y),
               controlPoint1: NSPoint(x: center.x - lipWidth * 0.2, y: center.y + lipHeight),
               controlPoint2: NSPoint(x: center.x + lipWidth * 0.2, y: center.y + lipHeight))
    lips.curve(to: NSPoint(x: center.x - lipWidth / 2, y: center.y),
               controlPoint1: NSPoint(x: center.x + lipWidth * 0.2, y: center.y - lipHeight),
               controlPoint2: NSPoint(x: center.x - lipWidth * 0.2, y: center.y - lipHeight))
    red.setFill()
    lips.fill()

    // Parmak — dudakları örtecek şekilde, hafif eğik
    let fingerWidth = side * 0.095
    let fingerHeight = side * 0.50
    let finger = NSBezierPath(roundedRect: NSRect(x: -fingerWidth / 2,
                                                  y: -fingerHeight * 0.32,
                                                  width: fingerWidth,
                                                  height: fingerHeight),
                              xRadius: fingerWidth / 2, yRadius: fingerWidth / 2)
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: -9)
    finger.transform(using: transform as AffineTransform)
    white.setFill()
    finger.fill()
}

let variants: [Variant] = [
    Variant(name: "1 · şu anki") { side in symbol("speaker.slash.fill", side: side, colors: [red, white]) },
    Variant(name: "2 · ağız + çizgi") { side in
        symbol("mouth.fill", side: side, scale: 0.42, colors: [white])
        let path = NSBezierPath()
        path.move(to: NSPoint(x: side * 0.26, y: side * 0.28))
        path.line(to: NSPoint(x: side * 0.74, y: side * 0.72))
        path.lineWidth = side * 0.075
        path.lineCapStyle = .round
        red.setStroke(); path.stroke() },
    Variant(name: "3 · şşşt (düzeltilmiş)") { side in drawShush(side: side) },
    Variant(name: "4 · balon kesik") { side in symbol("bubble.left.fill", side: side, scale: 0.46, colors: [white])
        let path = NSBezierPath()
        path.move(to: NSPoint(x: side * 0.24, y: side * 0.26))
        path.line(to: NSPoint(x: side * 0.76, y: side * 0.74))
        path.lineWidth = side * 0.08
        path.lineCapStyle = .round
        red.setStroke(); path.stroke() },
    Variant(name: "5 · dalga kesik") { side in symbol("waveform.slash", side: side, scale: 0.48, colors: [white]) },
    Variant(name: "6 · el dur") { side in
        symbol("waveform", side: side, scale: 0.34, colors: [amber], offset: CGPoint(x: -side * 0.14, y: 0))
        symbol("hand.raised.fill", side: side, scale: 0.36, colors: [white], offset: CGPoint(x: side * 0.10, y: 0)) },
    Variant(name: "7 · Mac + susturma") { side in
        symbol("macwindow", side: side, scale: 0.50, colors: [white], offset: CGPoint(x: 0, y: side * 0.03))
        symbol("speaker.slash.fill", side: side, scale: 0.22, colors: [red, white], offset: CGPoint(x: side * 0.16, y: -side * 0.15)) },
    Variant(name: "8 · yazı: SUS!") { side in
        let text = NSAttributedString(string: "SUS!", attributes: [
            .font: NSFont.systemFont(ofSize: side * 0.26, weight: .heavy),
            .foregroundColor: white,
            .kern: side * 0.005,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)) },
    Variant(name: "9 · yasak + hoparlör") { side in
        symbol("speaker.wave.2.fill", side: side, scale: 0.34, colors: [white])
        symbol("nosign", side: side, scale: 0.62, colors: [red]) },
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

    // Tek bir ikon karesini ayrı görüntüde çizip yerleştiriyoruz
    let icon = NSImage(size: NSSize(width: tile, height: tile))
    icon.lockFocus()
    let inset = tile * 0.06
    let rect = NSRect(x: inset, y: inset, width: tile - inset * 2, height: tile - inset * 2)
    let background = NSBezierPath(roundedRect: rect, xRadius: tile * 0.22, yRadius: tile * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.27, alpha: 1),
                        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1)])?.draw(in: background, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
    background.lineWidth = tile * 0.012
    background.stroke()
    variant.draw(tile)
    icon.unlockFocus()

    icon.draw(in: NSRect(x: x, y: y, width: tile, height: tile))

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1),
    ]
    let label = NSAttributedString(string: variant.name, attributes: attributes)
    label.draw(at: NSPoint(x: x + 4, y: y - labelHeight + 6))
}

sheet.unlockFocus()

if let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
   let png = bitmap.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/icon-variants.png"))
    print("tablo hazır: /tmp/icon-variants.png")
}
