import AppKit
import Foundation

/// Uygulama ikonlarını küçültülmüş hâlde saklar.
///
/// Neden gerekli: SwiftUI satırları sık yeniden çiziliyor ve her çizimde ikonu
/// sistemden yeniden istemek, 512×512'lik bir görüntüyü tekrar tekrar üretmek demek.
/// 35 uygulamalık listede bu, bellek tepe değerini gereksiz yere yukarı çekiyordu.
/// İkonlar nadiren değişir; bir kez çözüp menü boyutunda saklamak yeterli.
public enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    public static func icon(for bundleID: String, size: CGFloat = 18) -> NSImage? {
        let key = "\(bundleID)@\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = resolve(bundleID: bundleID) else { return nil }

        let scaled = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        cache.setObject(scaled, forKey: key)
        return scaled
    }

    private static func resolve(bundleID: String) -> NSImage? {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = app.icon {
            return icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Uygulama kurulup kaldırıldığında ya da ikon değiştiğinde çağrılabilir.
    public static func clear() { cache.removeAllObjects() }
}
