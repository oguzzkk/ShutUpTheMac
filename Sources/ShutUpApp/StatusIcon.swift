import AppKit

/// Menü çubuğu simgesi: bantlı Mac.
///
/// macOS menü çubuğunda renk kullanılamaz; şablon (template) simge çizilir ve sistem
/// onu temaya göre boyar. Durum simgenin kendisinden okunur: hiçbir şey kısılmamışken
/// Mac sakin, bir şey susturulduğunda kaşları çatılıp ağzına çapraz bant yapışır.
///
/// Ölçüler birlikte seçildi: gözler yukarıda (gövde yüksekliğinin %64'ü), bant aşağıda
/// (%26) — aralarında rahat bir boşluk kalıyor, bant kaşlara ya da yan duvarlara değmiyor.
/// Gövde çerçeveyi neredeyse tamamen dolduruyor: menü çubuğunda küçük kalmasın diye.
enum StatusIcon {

    static func image(muted: Bool, size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.black.setFill()
        NSColor.black.setStroke()
        draw(size: size, taped: muted)
        image.unlockFocus()
        image.isTemplate = true     // rengi sistem belirlesin
        return image
    }

    private static func draw(size: CGFloat, taped: Bool) {
        let lineWidth = max(1, size * 0.095)

        let screen = NSRect(x: size * 0.022, y: size * 0.240, width: size * 0.956, height: size * 0.715)
        let body = NSBezierPath(roundedRect: screen.insetBy(dx: lineWidth / 2, dy: lineWidth / 2),
                                xRadius: size * 0.13, yRadius: size * 0.13)
        body.lineWidth = lineWidth
        body.stroke()

        // Ayak
        let neckWidth = size * 0.10
        let neckBottom = size * 0.120
        NSBezierPath(rect: NSRect(x: size * 0.5 - neckWidth / 2, y: neckBottom,
                                  width: neckWidth, height: screen.minY - neckBottom + lineWidth)).fill()
        let footWidth = size * 0.54
        NSBezierPath(roundedRect: NSRect(x: size * 0.5 - footWidth / 2, y: size * 0.075,
                                         width: footWidth, height: lineWidth * 1.15),
                     xRadius: lineWidth / 2, yRadius: lineWidth / 2).fill()

        // Gözler
        let eyeY = screen.minY + screen.height * (taped ? 0.58 : 0.64)
        let eyeSize = size * 0.115
        let eyeSpacing = size * 0.195
        for sign in [-1.0, 1.0] as [CGFloat] {
            let x = size * 0.50 + sign * eyeSpacing
            NSBezierPath(ovalIn: NSRect(x: x - eyeSize / 2, y: eyeY - eyeSize / 2,
                                        width: eyeSize, height: eyeSize)).fill()
        }

        let mouthY = screen.minY + screen.height * 0.34

        guard taped else {
            // Konuşan hâl: kaş yok, ağız yampiri bir yarım ay —
            // üstü düz, altı yuvarlak, hafif eğik: keyifli, şarkı söyler gibi.
            let mouthWidth = size * 0.32
            let depth = size * 0.11
            let path = NSBezierPath()
            path.move(to: NSPoint(x: -mouthWidth / 2, y: 0))
            path.line(to: NSPoint(x: mouthWidth / 2, y: 0))
            path.curve(to: NSPoint(x: -mouthWidth / 2, y: 0),
                       controlPoint1: NSPoint(x: mouthWidth / 2, y: -depth * 1.7),
                       controlPoint2: NSPoint(x: -mouthWidth / 2, y: -depth * 1.7))
            let transform = NSAffineTransform()
            transform.translateX(by: size * 0.52, yBy: screen.minY + screen.height * 0.36)
            transform.rotate(byDegrees: -14)
            path.transform(using: transform as AffineTransform)
            path.fill()
            return
        }

        // Kızgın kaşlar
        for sign in [-1.0, 1.0] as [CGFloat] {
            let x = size * 0.50 + sign * eyeSpacing
            let brow = NSBezierPath()
            brow.move(to: NSPoint(x: x - sign * size * 0.068, y: eyeY + size * 0.082))
            brow.line(to: NSPoint(x: x + sign * size * 0.068, y: eyeY + size * 0.145))
            brow.lineWidth = lineWidth * 0.95
            brow.lineCapStyle = .round
            brow.stroke()
        }

        // Ağza yapıştırılmış tek kalın bant. (Çapraz denendi: 18 pikselde iki kalın
        // şerit birbirine karışıp lekeye dönüşüyor, tek bant daha net okunuyor.)
        let strip = NSBezierPath(rect: NSRect(x: -size * 0.25, y: -size * 0.0425,
                                              width: size * 0.50, height: size * 0.085))
        let transform = NSAffineTransform()
        transform.translateX(by: size * 0.50, yBy: mouthY)
        transform.rotate(byDegrees: -10)
        strip.transform(using: transform as AffineTransform)
        strip.fill()
    }
}
