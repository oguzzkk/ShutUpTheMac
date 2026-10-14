import AppKit
import Foundation

/// Bir uygulamanın tüm ses süreçleri — ana süreç ve yardımcıları — tek kalem olarak.
///
/// Kullanıcı "Chrome'u sustur" dediğinde Chrome Helper'ların da susması,
/// sonradan açılan yeni bir helper'ın da susturulmuş gelmesi bu gruplama sayesinde olur.
public struct AppGroup: Identifiable, Hashable, Sendable {
    public let bundleID: String
    public let name: String
    public let members: [AudioProcess]
    public let isMuted: Bool

    public var id: String { bundleID }
    public var isPlaying: Bool { members.contains(where: \.isPlaying) }
    public var playingCount: Int { members.filter(\.isPlaying).count }

    public var icon: NSImage? {
        // Önce uygulamanın kendi kimliğinden: Safari'nin sesini çalan WebKit süreçlerinin
        // ikonu yok, grubun ilk üyesine bakınca boş kutu çıkıyordu.
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = app.icon {
            return icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return members.compactMap(\.icon).first
    }


    /// Teknik süreç adı yerine insanın tanıyacağı ad.
    /// macOS'un uyarı ve bildirim sesleri `systemsoundserverd` adlı daemon'dan çıkar;
    /// kullanıcı bunu "sistem sesleri" olarak arar.
    static var friendlyNames: [String: String] {
        ["systemsoundserverd": L.t("systemSounds")]
    }

    /// Sistem süreci olsa da listede görünmesi gerekenler.
    static let alwaysVisible: Set<String> = ["systemsoundserverd"]

    /// Menüde ilk sırada gösterilmeye değer mi?
    ///
    /// Sistem daemon'ları (audiomxd, corespeechd, callservicesd...) teknik olarak
    /// ses süreci sayılır ama kullanıcı için gürültüdür. Ses çalan ya da susturulmuş
    /// olanlar her hâlükârda görünür — "ses çalıyor ama bulamıyorum" durumu olmasın.
    public var isUserFacing: Bool {
        if isPlaying || isMuted || Self.alwaysVisible.contains(bundleID) { return true }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        switch app.activationPolicy {
        case .regular: return true
        case .accessory: return !bundleID.hasPrefix("com.apple.")
        default: return false
        }
    }

    /// O anki süreç listesini uygulamalara göre gruplar.
    public static func group(_ processes: [AudioProcess], settings: Settings = .shared) -> [AppGroup] {
        let buckets = Dictionary(grouping: processes, by: { $0.owner.bundleID })

        return buckets.map { bundleID, members in
            let name = friendlyNames[bundleID]
                ?? members.first(where: { $0.owner.resolvedBy != .unresolved })?.owner.name
                ?? members.first?.name
                ?? bundleID
            return AppGroup(
                bundleID: bundleID,
                name: name,
                members: members.sorted { lhs, rhs in
                    if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                },
                isMuted: settings.isMuted(bundleID)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public static func current(settings: Settings = .shared) throws -> [AppGroup] {
        let own = Bundle.main.bundleIdentifier ?? "com.oguzkaan.shutupthemac"
        return group(try AudioProcessList.current(), settings: settings)
            .filter { $0.bundleID != own && $0.bundleID != "com.oguzkaan.shutupthemac" }
    }
}
