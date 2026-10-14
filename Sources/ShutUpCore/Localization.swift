import Foundation

/// Arayüz metinleri. Çeviriler koda gömülü değil, paket içindeki `translations.json`
/// dosyasından okunuyor — yeni dil eklemek ya da bir çeviriyi düzeltmek için
/// yeniden derlemeye gerek kalmasın.
public enum L {

    /// Desteklenen diller: kod + kendi dilindeki adı. Varsayılan Türkçe.
    public static let languages: [(code: String, name: String)] = [
        ("tr", "Türkçe"),
        ("en", "English"),
        ("zh", "中文（简体）"),
        ("hi", "हिन्दी"),
        ("es", "Español"),
        ("fr", "Français"),
        ("ar", "العربية"),
        ("bn", "বাংলা"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("ur", "اردو"),
        ("id", "Bahasa Indonesia"),
        ("de", "Deutsch"),
        ("ja", "日本語"),
        ("mr", "मराठी"),
        ("te", "తెలుగు"),
        ("ta", "தமிழ்"),
        ("vi", "Tiếng Việt"),
        ("ko", "한국어"),
        ("fa", "فارسی"),
        ("sw", "Kiswahili"),
        ("it", "Italiano"),
        ("pa", "ਪੰਜਾਬੀ"),
        ("gu", "ગુજરાતી"),
        ("th", "ไทย"),
        ("kn", "ಕನ್ನಡ"),
        ("uk", "Українська"),
        ("pl", "Polski"),
        ("ms", "Bahasa Melayu"),
        ("nl", "Nederlands"),
        ("ro", "Română"),
        ("el", "Ελληνικά"),
        ("cs", "Čeština"),
        ("hu", "Magyar"),
        ("sv", "Svenska"),
        ("he", "עברית"),
    ]

    public static let defaultCode = "tr"

    /// Sağdan sola yazılan diller — arayüz hizalaması için.
    public static let rightToLeft: Set<String> = ["ar", "ur", "fa", "he"]

    private static var tables: [String: [String: String]] = loadTables()

    private static func loadTables() -> [String: [String: String]] {
        // Uygulama paketi, CLI'ın yanı ve kurulu uygulama — hangisi bulunursa.
        var candidates: [URL] = []
        if let bundled = Bundle.main.url(forResource: "translations", withExtension: "json") {
            candidates.append(bundled)
        }
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("translations.json"))
        candidates.append(URL(fileURLWithPath:
            "/Applications/Shut Up The Mac.app/Contents/Resources/translations.json"))

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
            else { continue }
            return decoded
        }
        return [:]
    }

    /// Seçili dilde metni döndürür. Eksikse Türkçeye, o da yoksa anahtara düşer.
    public static func t(_ key: String) -> String {
        let code = Settings.shared.languageCode
        if let value = tables[code]?[key], !value.isEmpty { return value }
        if let fallback = tables[defaultCode]?[key], !fallback.isEmpty { return fallback }
        return key
    }

    /// Sayı içeren metinler: "%d süreç" gibi.
    public static func t(_ key: String, _ numbers: CVarArg...) -> String {
        String(format: t(key), arguments: numbers)
    }

    public static var isRightToLeft: Bool {
        rightToLeft.contains(Settings.shared.languageCode)
    }
}
