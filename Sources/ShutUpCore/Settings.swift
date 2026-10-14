import Darwin
import Foundation

/// Uygulama ile CLI'ın paylaştığı kalıcı ayarlar.
/// Tek doğruluk kaynağı burasıdır: CLI yazar, uygulama okuyup uygular.
///
/// Model: her uygulamanın 0...1 arası bir seviyesi vardır.
///   1.0 → tam ses, hiçbir müdahale yok (kayıt tutulmaz)
///   0.0 → susturulmuş (ucuz yol: yalnızca tap, ses yolu kurulmaz)
///   arası → kazanç uygulanır (ses yolu gerekir)
public final class Settings {
    public static let suiteName = "com.oguzkaan.shutupthemac.settings"
    public static let changedNotification = Notification.Name("com.oguzkaan.shutupthemac.settingsChanged")

    public static let shared = Settings()

    private let defaults: UserDefaults
    private let volumesKey = "volumes"
    private let preMuteKey = "preMuteVolumes"
    private let snapshotKey = "volumesSnapshot"
    private let usageKey = "usageCounts"
    private let knownMembersKey = "knownMemberBundleIDs"
    private let languageKey = "languageCode"

    private init() {
        defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    // MARK: Seviyeler

    public var volumes: [String: Float] {
        get { (defaults.dictionary(forKey: volumesKey) as? [String: Double])?.mapValues(Float.init) ?? [:] }
        set { defaults.set(newValue.mapValues(Double.init), forKey: volumesKey) }
    }

    public func volume(for key: String) -> Float { volumes[key] ?? 1.0 }

    public func setVolume(_ volume: Float, for key: String) {
        var current = volumes
        let clamped = max(0, min(1, volume))
        if clamped >= 1.0 { current.removeValue(forKey: key) } else { current[key] = clamped }
        volumes = current
    }

    /// Ses yolu gerektiren her şey: susturulmuşlar (0) ve kısılmışlar.
    /// Tam sesteki uygulamalar kayıtta tutulmaz, dolayısıyla burada da yer almaz.
    public var attenuatedVolumes: [String: Float] {
        volumes.filter { $0.value < 1 }
    }

    // MARK: Arayüz dili

    public var languageCode: String {
        get { defaults.string(forKey: languageKey) ?? "tr" }
        set { defaults.set(newValue, forKey: languageKey) }
    }

    // MARK: Öğrenilen süreç kimlikleri
    //
    // Bir uygulamanın hangi süreçlerden ses çaldığını (Safari → WebKit.GPU gibi)
    // çalışırken öğreniyoruz. Uygulama ya da süreç kapandığında bile susturmayı
    // sürdürebilmek için bu bilgi saklanıyor: tap bundle ID'ye kuruluyor.
    public func knownMembers(of bundleID: String) -> [String] {
        (defaults.dictionary(forKey: knownMembersKey) as? [String: [String]])?[bundleID] ?? []
    }

    public func learnMembers(_ members: [String], for bundleID: String) {
        guard !members.isEmpty else { return }
        var store = (defaults.dictionary(forKey: knownMembersKey) as? [String: [String]]) ?? [:]
        let merged = Set(store[bundleID] ?? []).union(members).sorted()
        guard merged != store[bundleID] else { return }
        store[bundleID] = merged
        defaults.set(store, forKey: knownMembersKey)
    }

    // MARK: Kullanım sıklığı
    //
    // Sık aç-kapa yapılan uygulamalar listede yukarı çıksın: 30 uygulamalık listede
    // her seferinde aynı üç-beş uygulamayı aramak zorunda kalmamak için.

    public func usageCount(_ key: String) -> Int {
        (defaults.dictionary(forKey: usageKey) as? [String: Int])?[key] ?? 0
    }

    public func recordUsage(_ key: String) {
        var counts = (defaults.dictionary(forKey: usageKey) as? [String: Int]) ?? [:]
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: usageKey)
    }

    public func resetUsage() { defaults.removeObject(forKey: usageKey) }

    // MARK: Toplu işlem öncesi durum
    //
    // "Hepsini sustur" geri alınabilir olmalı: basıldığı andaki tüm seviyeler
    // saklanır, tekrar basıldığında aynen geri yüklenir. Diskte tutuluyor ki
    // uygulama yeniden başlasa da geri dönüş hakkı kaybolmasın.
    public var snapshot: [String: Float]? {
        get {
            guard let stored = defaults.dictionary(forKey: snapshotKey) as? [String: Double] else { return nil }
            return stored.mapValues(Float.init)
        }
        set {
            guard let newValue else { defaults.removeObject(forKey: snapshotKey); return }
            defaults.set(newValue.mapValues(Double.init), forKey: snapshotKey)
        }
    }

    public var hasSnapshot: Bool { defaults.dictionary(forKey: snapshotKey) != nil }

    // MARK: Susturma (seviye 0 demektir)

    public var mutedApps: Set<String> {
        get { Set(volumes.filter { $0.value == 0 }.keys) }
        set {
            var current = volumes
            for key in current.filter({ $0.value == 0 }).keys where !newValue.contains(key) {
                current.removeValue(forKey: key)
            }
            for key in newValue { current[key] = 0 }
            volumes = current
        }
    }

    public func isMuted(_ key: String) -> Bool { volume(for: key) == 0 }

    public func setMuted(_ muted: Bool, for key: String) {
        if muted {
            let current = volume(for: key)
            if current > 0 { rememberPreMute(current, for: key) }   // seviyeyi geri getirebilmek için
            setVolume(0, for: key)
        } else {
            setVolume(preMuteVolume(for: key), for: key)
            forgetPreMute(for: key)
        }
    }

    public func toggleMuted(for key: String) -> Bool {
        let muted = !isMuted(key)
        setMuted(muted, for: key)
        return muted
    }

    private func rememberPreMute(_ volume: Float, for key: String) {
        var stored = (defaults.dictionary(forKey: preMuteKey) as? [String: Double]) ?? [:]
        stored[key] = Double(volume)
        defaults.set(stored, forKey: preMuteKey)
    }

    private func preMuteVolume(for key: String) -> Float {
        let stored = (defaults.dictionary(forKey: preMuteKey) as? [String: Double]) ?? [:]
        return stored[key].map(Float.init) ?? 1.0
    }

    private func forgetPreMute(for key: String) {
        var stored = (defaults.dictionary(forKey: preMuteKey) as? [String: Double]) ?? [:]
        stored.removeValue(forKey: key)
        defaults.set(stored, forKey: preMuteKey)
    }

    /// Çalışan uygulamaya "ayarlar değişti, uygula" sinyali gönderir.
    ///
    /// DistributedNotificationCenter bu senaryoda sessizce düşüyordu (CLI süreci
    /// bildirimi postalıyor ama uygulamaya ulaşmıyordu). Darwin notify çekirdek
    /// seviyesinde çalışır ve süreç türünden bağımsızdır.
    public func broadcastChange() {
        defaults.synchronize()
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.darwinNotification as CFString),
            nil, nil, true
        )
    }

    public static let darwinNotification = "com.oguzkaan.shutupthemac.changed"

    /// Uygulamanın yazdığı, CLI'ın okuduğu durum dosyası.
    public static var statusFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShutUpTheMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("status.json")
    }

    /// Ayar değişikliklerini dinler.
    /// Darwin bildirim merkezi C geri çağırımı istediği için işleyici statik kutuda tutulur.
    public static func observeChanges(_ handler: @escaping () -> Void) {
        NotificationBox.shared.handler = handler
        // Gözlemci işaretçisi nil bırakılırsa kayıt sessizce düşebiliyor.
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(NotificationBox.shared).toOpaque(),
            { _, _, _, _, _ in NotificationBox.shared.fire() },
            darwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// Başka süreç yazmış olabilir; önbelleği tazeler.
    public func reload() {
        defaults.synchronize()
    }
}


/// Darwin bildiriminin C geri çağırımı bağlam taşıyamadığı için işleyiciyi burada tutuyoruz.
final class NotificationBox: @unchecked Sendable {
    static let shared = NotificationBox()
    var handler: (() -> Void)?

    func fire() {
        guard let handler else { return }
        DispatchQueue.main.async { handler() }
    }
}
