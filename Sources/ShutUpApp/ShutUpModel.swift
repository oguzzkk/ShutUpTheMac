import AVFoundation
import AppKit
import CoreAudio
import Combine
import ServiceManagement
import ShutUpCore

/// Panelin arkasındaki tek durum kaynağı.
@MainActor
final class ShutUpModel: ObservableObject {
    @Published private(set) var groups: [AppGroup] = []
    @Published var searchText: String = ""
    @Published var showsSystemProcesses = false

    /// Tek tek susturulmuş yardımcı süreçler. Süreç kimlikleri her açılışta
    /// değiştiği için bu bilgi kalıcı değildir — oturum boyunca geçerlidir.
    @Published private(set) var mutedProcesses: Set<pid_t> = []

    /// Ses *kısma* sistem sesini okumayı gerektirir ve bu izne tabidir.
    /// Susturma izin istemez; bu uyarı yalnızca seviye ayarını etkiler.
    @Published private(set) var needsAudioPermission = false

    private let monitor = AudioProcessMonitor()
    private let volumeEngine = VolumeEngine()
    private let settings = Settings.shared
    private var pendingApply: DispatchWorkItem?

    var mutedCount: Int { settings.mutedApps.count }

    init() {
        monitor.onChange = { [weak self] processes in
            guard let self else { return }
            groups = Self.excludingSelf(AppGroup.group(processes, settings: settings))
            scheduleApply()
        }
        monitor.start()

        // kayıt artık startListening() içinde, uygulama çalışmaya başladıktan sonra
    }

    /// Darwin bildirim kaydı NSApplication'ın çalışma döngüsü kurulduktan sonra yapılır;
    /// daha erken yapıldığında geri çağırım hiç tetiklenmiyordu.
    private var pollTimer: DispatchSourceTimer?
    private var lastSeenVolumes: [String: Float] = [:]

    func startListening() {
        Self.trace("startListening çağrıldı")
        lastSeenVolumes = settings.volumes

        // Yedek yol: ayarları düzenli olarak oku.
        //
        // RunLoop zamanlayıcısı kullanılamıyor: menü çubuğu uygulaması `open` ile
        // başlatıldığında App Nap ana döngüyü uyutuyor ve zamanlayıcı hiç tetiklenmiyor
        // (Terminal'den doğrudan başlatınca çalıştığı için uzun süre fark edilmedi).
        // DispatchSource zamanlayıcı kendi kuyruğunda çalışır, bu uykuya takılmaz.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.5, repeating: 1.5)
        timer.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.settings.reload()
                    let current = self.settings.volumes
                    self.needsAudioPermission = self.volumeEngine.needsPermission
                    self.writeStatus()   // ses yolu arka planda kurulduğu için durumu burada tazeliyoruz
                    guard current != self.lastSeenVolumes else { return }
                    self.lastSeenVolumes = current
                    self.reapply()
                }
            }
        }
        timer.resume()
        pollTimer = timer

        Settings.observeChanges { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.settings.reload()
                self.lastSeenVolumes = self.settings.volumes
                self.reapply()
            }
        }
    }

    // MARK: Görünen liste

    /// Kullanıcıya dönük gruplar: arama filtresi uygulanmış, ses çalanlar üstte.
    var visibleGroups: [AppGroup] {
        let base = groups.filter { showsSystemProcesses || $0.isUserFacing }
        guard !searchText.isEmpty else { return base }
        return base.filter { group in
            group.name.localizedCaseInsensitiveContains(searchText)
                || group.members.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var playingGroups: [AppGroup] { sortedByUsage(visibleGroups.filter(\.isPlaying)) }
    var quietGroups: [AppGroup] { sortedByUsage(visibleGroups.filter { !$0.isPlaying }) }

    /// Sık dokunulan uygulamalar üstte. Eşitlikte alfabetik — sıralama
    /// her açılışta zıplamasın, tahmin edilebilir kalsın.
    private func sortedByUsage(_ groups: [AppGroup]) -> [AppGroup] {
        groups.sorted { lhs, rhs in
            let lhsCount = settings.usageCount(lhs.bundleID)
            let rhsCount = settings.usageCount(rhs.bundleID)
            if lhsCount != rhsCount { return lhsCount > rhsCount }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Kullanıcı bu uygulamaya dokundu — sıralamada yukarı çıkmasını sağlar.
    func recordUsage(_ bundleID: String) { settings.recordUsage(bundleID) }
    var hiddenSystemCount: Int { groups.filter { !$0.isUserFacing }.count }

    /// Kapalı olduğu hâlde susturulmuş kalanlar — "sesim neden yok" tuzağına karşı.
    var offlineMuted: [String] {
        let live = Set(groups.map(\.bundleID))
        return settings.mutedApps.subtracting(live).sorted()
    }

    // MARK: Eylemler

    func refresh() { monitor.refresh() }

    /// Süreç listesi saniyede birkaç kez değişebiliyor. Ses yolunu her seferinde
    /// yıkıp kurmak Core Audio'yu kilitliyordu; değişiklikler kısa bir pencerede toplanır.
    private func scheduleApply() {
        pendingApply?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Self.trace("uygula — grup: \(groups.count) · kısık: \(settings.attenuatedVolumes)")
            let targets = audioTargets()
            requestPermissionIfNeeded(hasTargets: !targets.isEmpty)
            volumeEngine.permissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            volumeEngine.apply(targets: targets)
            writeStatus()
        }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func toggle(_ group: AppGroup) {
        settings.recordUsage(group.bundleID)
        _ = settings.toggleMuted(for: group.bundleID)
        reapply()
    }

    func setMuted(_ muted: Bool, bundleID: String) {
        settings.setMuted(muted, for: bundleID)
        reapply()
    }

    /// Toplu işlem etkin mi? Etkinse düğme "geri al" görevi görür.
    var bulkActive: Bool { settings.hasSnapshot }

    /// "Hepsini sustur" ↔ "geri al". İkinci basışta, ilk basıştan önceki
    /// seviyelerin tamamı (kısılmışlar dahil) aynen geri gelir.
    func toggleMuteAll() {
        if let snapshot = settings.snapshot {
            settings.volumes = snapshot
            settings.snapshot = nil
        } else {
            settings.snapshot = settings.volumes
            var volumes = settings.volumes
            for group in visibleGroups { volumes[group.bundleID] = 0 }
            settings.volumes = volumes
        }
        reapply()
    }

    /// Öndeki uygulama hariç her şeyi sustur. Bu da geri alınabilir:
    /// ilk basışta önceki durum saklanır.
    func soloFrontmost() {
        if settings.snapshot == nil { settings.snapshot = settings.volumes }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        var volumes = settings.volumes
        for group in visibleGroups where group.bundleID != frontmost {
            volumes[group.bundleID] = 0
        }
        volumes.removeValue(forKey: frontmost ?? "")
        settings.volumes = volumes
        reapply()
    }

    func unmuteAll() {
        settings.volumes = [:]
        settings.snapshot = nil      // artık geri dönülecek bir durum kalmadı
        reapply()
    }

    func isMuted(_ bundleID: String) -> Bool { settings.isMuted(bundleID) }

    /// Yardımcı süreç, ya kendi başına ya da bağlı olduğu uygulama üzerinden susturulmuş olabilir.
    func isMuted(process: AudioProcess) -> Bool {
        settings.isMuted(process.owner.bundleID) || mutedProcesses.contains(process.pid)
    }

    func toggleProcess(_ process: AudioProcess) {
        settings.recordUsage(process.owner.bundleID)
        if mutedProcesses.contains(process.pid) {
            mutedProcesses.remove(process.pid)
        } else {
            mutedProcesses.insert(process.pid)
        }
        reapply()
    }

    /// Grup ve süreç seviyesindeki susturmaları tek bir istek hâline getirir.
    /// Uygulamanın o anki durumunu diske yazar; `shutup status` bunu okur.
    /// Private tap'ler yalnızca onları yaratan sürece göründüğü için dışarıdan
    /// doğrulamanın başka yolu yok.
    private var lastStatusPayload: Data?

    private func writeStatus() {
        let status: [String: Any] = [
            "guncelleme": ISO8601DateFormatter().string(from: Date()),
            "susturulmus": settings.mutedApps.sorted(),
            "kisilmis": settings.attenuatedVolumes.mapValues { Int($0 * 100) },
            "sureclerSusturulmus": mutedProcesses.sorted().map(Int.init),
            "sesYoluCalisiyor": volumeEngine.isRunning,
            "izlenenUygulama": groups.count,
            "izinGerekiyor": volumeEngine.needsPermission,
            "kuruluTap": volumeEngine.activeTapCount,
            "yolunCikisAygiti": volumeEngine.boundOutputDevices,
            "olcer": ["giris": VolumeEngine.meters.inputPeak,
                      "cikis": VolumeEngine.meters.outputPeak,
                      "cagri": VolumeEngine.meters.callbacks],
            "mikrofonIzni": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
        ]
        // Zaman damgası dışındaki içerik aynıysa diske yazma (yoklama her 1,5 sn çalışıyor).
        var comparable = status
        comparable.removeValue(forKey: "guncelleme")
        guard let fingerprint = try? JSONSerialization.data(withJSONObject: comparable, options: [.sortedKeys]) else { return }
        guard fingerprint != lastStatusPayload else { return }
        lastStatusPayload = fingerprint

        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: Settings.statusFileURL)
    }

    /// Ses yolunun kuracağı hedefler: hangi uygulamanın hangi süreçleri, hangi kazançla.
    /// Susturma ayrı bir mekanizma değil, kazancı 0 olan seviyedir.
    /// Ayarı olan her uygulama için ses yolu kurulur — o an sessiz olsa bile.
    ///
    /// Önce yalnızca ses çalanlara kuruyordum; yanlıştı: susturmanın anlamı
    /// uygulama *çalmaya başladığında* sessiz olması. Geç kurulan yol, her sesin
    /// ilk yarım saniyesini kaçırıyordu (bildirim sesleri gibi kısa seslerde hepsini).
    private func audioTargets() -> [VolumeEngine.Target] {
        let livePIDs = Set(groups.flatMap { $0.members.map(\.pid) })
        mutedProcesses.formIntersection(livePIDs)   // kapanan süreçlerin kaydını bırak

        // Gördüğümüz süreçleri öğren: uygulama kapanınca da susturmayı sürdürebilmek için.
        for group in groups {
            settings.learnMembers(group.members.compactMap(\.bundleID) + [group.bundleID],
                                  for: group.bundleID)
        }

        var targets = groups.compactMap { group -> VolumeEngine.Target? in
            let groupVolume = settings.volume(for: group.bundleID)

            if groupVolume < 1 {
                return VolumeEngine.Target(bundleID: group.bundleID, name: group.name,
                                           members: Set(group.members.map(\.id)),
                                           processBundleIDs: Set(group.members.compactMap(\.bundleID)),
                                           gain: groupVolume)
            }

            let individual = group.members.filter { mutedProcesses.contains($0.pid) }
            guard !individual.isEmpty else { return nil }
            return VolumeEngine.Target(bundleID: group.bundleID, name: group.name,
                                       members: Set(individual.map(\.id)),
                                       processBundleIDs: Set(individual.compactMap(\.bundleID)),
                                       gain: 0)
        }

        // Ayarı olup da şu an listede görünmeyen uygulamalar: süreçleri uykuda ya da
        // uygulama kapalı. Öğrenilmiş bundle ID'lerle yolu ayakta tutuyoruz ki
        // ses çaldıkları ilk anda sessiz olsunlar.
        let covered = Set(targets.map(\.bundleID))
        for (bundleID, gain) in settings.attenuatedVolumes where !covered.contains(bundleID) {
            let known = settings.knownMembers(of: bundleID)
            guard !known.isEmpty else { continue }
            targets.append(VolumeEngine.Target(bundleID: bundleID,
                                               name: bundleID.split(separator: ".").last.map(String.init) ?? bundleID,
                                               members: [],
                                               processBundleIDs: Set(known),
                                               gain: gain))
        }

        return targets
    }

    /// Girişte otomatik başlatma. SMAppService, kullanıcının Sistem Ayarları →
    /// Giriş Öğeleri listesinde görünür ve oradan da kapatılabilir.
    var launchesAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Self.trace("girişte başlatma değiştirilemedi: \(error)")
            }
            UserDefaults.standard.set(!newValue, forKey: Self.optedOutKey)
            objectWillChange.send()
        }
    }

    private static let optedOutKey = "userDisabledLaunchAtLogin"

    /// Girişte başlatmayı garanti eder. Uygulama başka bir klasöre taşınınca
    /// eski kayıt geçersiz kalıyor; bu yüzden her açılışta durum denetlenir.
    /// Kullanıcı seçeneği kapattıysa bir daha kendiliğinden açılmaz.
    func ensureLaunchAtLogin() {
        guard !UserDefaults.standard.bool(forKey: Self.optedOutKey) else { return }
        guard SMAppService.mainApp.status != .enabled else { return }
        do { try SMAppService.mainApp.register() } catch { Self.trace("girişte başlatma kurulamadı: \(error)") }
    }

    /// Sistem sesi okuma iznini ister ve ardından ses yolunu yeniden dener.
    func requestAudioPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Self.trace("izin sonucu: \(granted)")
                    self.volumeEngine.clearPermissionBlock()
                    self.needsAudioPermission = false
                    self.reapply()
                }
            }
        }
    }

    func openPrivacySettings() {
        // macOS, tap ile sistem sesi okuyan uygulamaları bu panelde listeliyor.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    func quit() {
        volumeEngine.tearDown()   // çıkarken kimsenin sesi kısılı kalmasın
        NSApp.terminate(nil)
    }

    /// Uygulama kendi kendini listelemesin.
    private static func excludingSelf(_ groups: [AppGroup]) -> [AppGroup] {
        let own = Bundle.main.bundleIdentifier
        return groups.filter { $0.bundleID != own }
    }

    func releaseAll() {
        volumeEngine.tearDown()
    }

    func volume(_ bundleID: String) -> Float { settings.volume(for: bundleID) }

    /// Kaydırıcı sürüklenirken `live` kullanılır: yalnızca kazanç güncellenir,
    /// süreç listesi yeniden taranmaz — aksi hâlde her piksel için tam tarama olurdu.
    func setVolume(_ volume: Float, bundleID: String, live: Bool = false) {
        if !live { settings.recordUsage(bundleID) }   // sürükleme bitince bir kez say
        settings.setVolume(volume, for: bundleID)
        if live {
            volumeEngine.apply(targets: audioTargets())
            objectWillChange.send()
        } else {
            reapply()
        }
    }

    static func trace(_ message: String) {
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        if let data = line.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: "/tmp/shutup-app.log") {
                handle.seekToEndOfFile(); handle.write(data); try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/shutup-app.log"))
            }
        }
    }

    private var didAskForPermission = false

    /// İlk kez bir şey susturulduğunda/kısıldığında izni iste.
    /// İzin olmadan ses yolu kurulamıyor, dolayısıyla susturma da çalışmıyor.
    private func requestPermissionIfNeeded(hasTargets: Bool) {
        guard hasTargets, !didAskForPermission else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        didAskForPermission = true
        Self.trace("izin isteniyor")
        requestAudioPermission()
    }

    private func reapply() {
        monitor.refresh()
        groups = Self.excludingSelf(AppGroup.group(monitor.processes, settings: settings))
        let targets = audioTargets()
        requestPermissionIfNeeded(hasTargets: !targets.isEmpty)
        volumeEngine.permissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        volumeEngine.apply(targets: targets)
        writeStatus()
        objectWillChange.send()
    }
}
