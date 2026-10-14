import Foundation
import CoreAudio
import ShutUpCore

/// Otomasyon yüzü: Shortcuts, Alfred, Terminal ya da başka betiklerden sürülebilir.
/// Ayarları yazar ve çalışan uygulamaya "uygula" sinyali gönderir.

let settings = Settings.shared
let arguments = Array(CommandLine.arguments.dropFirst())

func printList(verbose: Bool) throws {
    // Panelle aynı sıralama: sık dokunulanlar üstte, sonra alfabetik.
    let groups = try AppGroup.current(settings: settings).sorted { lhs, rhs in
        if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
        let lhsCount = settings.usageCount(lhs.bundleID)
        let rhsCount = settings.usageCount(rhs.bundleID)
        if lhsCount != rhsCount { return lhsCount > rhsCount }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    for group in groups where verbose || group.isUserFacing {
        let level = settings.volume(for: group.bundleID)
        let state: String
        switch level {
        case 0: state = "sustur"
        case 1: state = "tam"
        default: state = "%\(Int(level * 100))"
        }
        let marker = group.isPlaying ? "▶︎" : " ·"
        print("\(marker) \(group.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(state.padding(toLength: 8, withPad: " ", startingAt: 0)) \(group.bundleID)")
        if verbose {
            for member in group.members {
                print("       \(member.isPlaying ? "▶︎" : "·") \(member.name) · pid \(member.pid)")
            }
        }
    }
}

/// Kullanıcı tam bundle ID yazmak zorunda kalmasın: isimle de eşleşsin.
func resolve(_ query: String) throws -> String {
    let groups = try AppGroup.current(settings: settings)
    if query.hasPrefix("pid:"), let pid = pid_t(query.dropFirst(4)) {
        if let match = groups.first(where: { $0.members.contains { $0.pid == pid } }) {
            return match.bundleID
        }
    }
    if let exact = groups.first(where: { $0.bundleID.caseInsensitiveCompare(query) == .orderedSame }) {
        return exact.bundleID
    }
    if let byName = groups.first(where: { $0.name.localizedCaseInsensitiveContains(query) }) {
        return byName.bundleID
    }
    throw NSError(domain: "shutup", code: 1,
                  userInfo: [NSLocalizedDescriptionKey: "'\(query)' eşleşmedi. 'shutup list' ile bak."])
}

do {
    switch arguments.first {
    case "list", nil:
        try printList(verbose: arguments.contains("--all"))

    case "mute", "sustur":
        guard arguments.count >= 2 else { throw NSError(domain: "shutup", code: 2, userInfo: [NSLocalizedDescriptionKey: "kullanım: shutup mute <uygulama>"]) }
        let bundleID = try resolve(arguments[1])
        settings.recordUsage(bundleID)
        settings.setMuted(true, for: bundleID)
        settings.broadcastChange()
        print("🔇 \(bundleID)")

    case "unmute", "ac":
        guard arguments.count >= 2 else { throw NSError(domain: "shutup", code: 2, userInfo: [NSLocalizedDescriptionKey: "kullanım: shutup unmute <uygulama>"]) }
        let bundleID = try resolve(arguments[1])
        settings.recordUsage(bundleID)
        settings.setMuted(false, for: bundleID)
        settings.broadcastChange()
        print("🔊 \(bundleID)")

    case "volume", "seviye":
        guard arguments.count >= 3, let percent = Float(arguments[2]) else {
            throw NSError(domain: "shutup", code: 2, userInfo: [NSLocalizedDescriptionKey: "kullanım: shutup volume <uygulama> <0-100>"])
        }
        let bundleID = try resolve(arguments[1])
        settings.recordUsage(bundleID)
        settings.setVolume(percent / 100, for: bundleID)
        settings.broadcastChange()
        print("🎚  \(bundleID) → %\(Int(percent))")

    case "selftest":
        // Motoru bu süreçte kurar: hata varsa IPC'ye değil motora bakmak için.
        guard arguments.count >= 3, let percent = Float(arguments[2]) else {
            throw NSError(domain: "shutup", code: 2, userInfo: [NSLocalizedDescriptionKey: "kullanım: shutup selftest <uygulama> <0-100>"])
        }
        let bundleID = try resolve(arguments[1])
        let groups = try AppGroup.current(settings: settings)
        VolumeEngine.trace = true
        let engine = VolumeEngine()
        guard let group = groups.first(where: { $0.bundleID == bundleID }) else { break }
        engine.apply(targets: [VolumeEngine.Target(bundleID: bundleID, name: group.name,
                                                   members: Set(group.members.map(\.id)),
                                                   gain: percent / 100)])
        print("motor çalışıyor mu: \(engine.isRunning)")
        for line in Diagnostics.audioObjects() { print("  " + line) }
        print("8 saniye bu seviyede kalıyor, dinle...")
        for second in 1...8 {
            VolumeEngine.meters.reset()
            Thread.sleep(forTimeInterval: 1)
            let m = VolumeEngine.meters
            let ratio = m.inputPeak > 0 ? m.outputPeak / m.inputPeak : 0
            print(String(format: "  %d. sn — çağrı:%d  giriş tepe:%.5f  çıkış tepe:%.5f  oran:%.3f",
                         second, m.callbacks, m.inputPeak, m.outputPeak, ratio))
            fflush(stdout)
        }
        engine.tearDown()
        print("motor kapatıldı, ses normale döndü")

    case "status", "durum":
        if let data = try? Data(contentsOf: Settings.statusFileURL),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        } else {
            print("Durum dosyası yok — uygulama çalışmıyor olabilir.")
        }

    case "debug":
        print("Çalışan tap'ler ve aggregate aygıtlar:")
        for line in Diagnostics.audioObjects() { print("  " + line) }

    case "solo", "yalniz":
        // Paneldeki satır düğmesiyle aynı davranış: bu hariç hepsini sustur,
        // ikinci çağrıda önceki duruma dön.
        guard arguments.count >= 2 else { throw NSError(domain: "shutup", code: 2, userInfo: [NSLocalizedDescriptionKey: "kullanım: shutup solo <uygulama>"]) }
        let bundleID = try resolve(arguments[1])
        let groups = try AppGroup.current(settings: settings).filter(\.isUserFacing)
        let others = groups.filter { $0.bundleID != bundleID }
        let alreadySolo = settings.hasSnapshot
            && settings.volume(for: bundleID) >= 1
            && !others.isEmpty
            && others.allSatisfy { settings.isMuted($0.bundleID) }

        if alreadySolo, let snapshot = settings.snapshot {
            settings.volumes = snapshot
            settings.snapshot = nil
            print("↩︎ solo kapatıldı, önceki duruma dönüldü")
        } else {
            if settings.snapshot == nil { settings.snapshot = settings.volumes }
            var volumes = settings.volumes
            for other in others { volumes[other.bundleID] = 0 }
            volumes.removeValue(forKey: bundleID)
            settings.volumes = volumes
            print("🎧 yalnız \(bundleID) duyuluyor")
        }
        settings.recordUsage(bundleID)
        settings.broadcastChange()

    case "muteall", "hepsi":
        // Panel düğmesiyle aynı davranış: ikinci çağrıda önceki duruma döner.
        if let snapshot = settings.snapshot {
            settings.volumes = snapshot
            settings.snapshot = nil
            settings.broadcastChange()
            print("↩︎ önceki duruma dönüldü")
        } else {
            settings.snapshot = settings.volumes
            var volumes = settings.volumes
            for group in try AppGroup.current(settings: settings) where group.isUserFacing {
                volumes[group.bundleID] = 0
            }
            settings.volumes = volumes
            settings.broadcastChange()
            print("🔇 hepsi susturuldu (geri almak için tekrar çalıştır)")
        }

    case "forget", "sirala-sifirla":
        settings.resetUsage()
        print("kullanım sıklığı sıfırlandı, sıralama alfabetiğe döndü")

    case "reset":
        settings.snapshot = nil
        settings.volumes = [:]
        settings.broadcastChange()
        print("tüm ayarlar sıfırlandı")

    default:
        print("""
        Shut Up The Mac — komut satırı

          shutup list [--all]            uygulamaları ve seviyelerini listele
          shutup mute <uygulama>         sustur
          shutup unmute <uygulama>       sesi geri aç
          shutup volume <uygulama> <0-100>  seviye ayarla
          shutup solo <uygulama>         bu hariç hepsini sustur / tekrar çalıştırınca geri al
          shutup muteall                 hepsini sustur / tekrar çalıştırınca geri al
          shutup status                  uygulamanın o anki durumu
          shutup reset                   hepsini tam sese döndür

        <uygulama> yerine isim parçası da yazabilirsin: shutup volume chrome 30
        """)
    }
} catch {
    print("Hata: \(error.localizedDescription)")
    exit(1)
}
