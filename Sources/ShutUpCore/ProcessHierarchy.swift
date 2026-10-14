import AppKit
import Darwin
import Foundation

/// Bir ses sürecinin hangi "gerçek" uygulamaya ait olduğunu çözer.
///
/// Üç ayrı vaka var ve tek bir kural hepsini çözmüyor:
///   • Chrome/Claude/Cocos yardımcıları: bundle ID ana uygulamanın ön ekini taşır
///     (`com.google.Chrome.helper`), üst süreç de ana uygulamadır.
///   • Safari: sesi `com.apple.WebKit.GPU` süreci çalar, bundle ID Safari'ye benzemez
///     ve üst süreci Safari değil `launchd`'dır. Burada macOS'un "sorumlu süreç"
///     eşlemesi gerekir — sistemin izinleri de bu eşlemeye göre atadığı yer.
///   • Uygulamanın kendisi: Dock'ta görünen normal bir uygulamaysa sahibi kendisidir;
///     onu başlatan başka bir uygulamanın (ör. bir launcher) altına düşmemeli.
public enum ProcessHierarchy {

    // MARK: Sorumlu süreç (macOS'un TCC için kullandığı eşleme)

    private typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t

    private static let responsibleFunction: ResponsibleFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibleFunction.self)
    }()

    public static func responsiblePID(of pid: pid_t) -> pid_t? {
        guard let function = responsibleFunction else { return nil }
        let owner = function(pid)
        return (owner > 0 && owner != pid) ? owner : nil
    }

    public static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    // MARK: Sahiplik

    public static func owner(ofPID pid: pid_t, bundleID: String?) -> Owner {
        // 1) Süreç zaten Dock'ta görünen bir uygulamaysa sahibi kendisidir.
        if let app = NSRunningApplication(processIdentifier: pid),
           let identifier = app.bundleIdentifier,
           app.activationPolicy != .prohibited,
           !looksLikeHelper(identifier) {
            return Owner(bundleID: identifier, name: app.localizedName ?? identifier, pid: pid, resolvedBy: .itself)
        }

        // 2) Yardımcı süreç adını kırp: com.google.Chrome.helper -> com.google.Chrome
        //    Yalnızca o bundle ID'ye sahip çalışan bir uygulama varsa kabul edilir.
        if let bundleID, let trimmed = trimHelperSuffix(bundleID),
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: trimmed).first {
            return Owner(bundleID: trimmed, name: app.localizedName ?? trimmed, pid: app.processIdentifier,
                         resolvedBy: .bundlePrefix)
        }

        // 3) Üst süreç zinciri: yalnızca ön ek eşleşmesi varsa (Terminal'den açılan
        //    uygulamalar yanlışlıkla Terminal'in altına düşmesin).
        if let bundleID, let ancestor = ancestorSharingPrefix(of: pid, bundleID: bundleID) {
            return ancestor
        }

        // 4) macOS'un sorumlu süreç eşlemesi — Safari/WebKit vakası burada çözülür.
        if let ownerPID = responsiblePID(of: pid),
           let app = NSRunningApplication(processIdentifier: ownerPID),
           let identifier = app.bundleIdentifier {
            return Owner(bundleID: identifier, name: app.localizedName ?? identifier, pid: ownerPID,
                         resolvedBy: .responsible)
        }

        if let bundleID {
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? shortName(bundleID)
            return Owner(bundleID: bundleID, name: name, pid: pid, resolvedBy: .itself)
        }

        return Owner(bundleID: "pid:\(pid)", name: "pid \(pid)", pid: pid, resolvedBy: .unresolved)
    }

    private static func ancestorSharingPrefix(of pid: pid_t, bundleID: String) -> Owner? {
        var current = parentPID(of: pid)
        var depth = 0

        while let candidate = current, candidate > 1, depth < 8 {
            defer { current = parentPID(of: candidate); depth += 1 }
            guard let app = NSRunningApplication(processIdentifier: candidate),
                  let parentBundleID = app.bundleIdentifier else { continue }
            guard bundleID == parentBundleID || bundleID.hasPrefix(parentBundleID + ".") else { continue }
            return Owner(bundleID: parentBundleID, name: app.localizedName ?? parentBundleID,
                         pid: candidate, resolvedBy: .parentChain)
        }
        return nil
    }

    private static func looksLikeHelper(_ bundleID: String) -> Bool {
        trimHelperSuffix(bundleID) != nil
    }

    private static func trimHelperSuffix(_ bundleID: String) -> String? {
        var parts = bundleID.split(separator: ".").map(String.init)
        let noise: Set<String> = ["helper", "renderer", "gpu", "plugin", "framework",
                                  "worker", "service", "agent", "host", "node", "xpc",
                                  "webcontent", "networking"]
        var trimmed = false
        while parts.count > 2, let last = parts.last, noise.contains(last.lowercased()) {
            parts.removeLast()
            trimmed = true
        }
        return trimmed ? parts.joined(separator: ".") : nil
    }

    private static func shortName(_ identifier: String) -> String {
        identifier.split(separator: ".").last.map(String.init) ?? identifier
    }

    public struct Owner: Hashable, Sendable {
        public let bundleID: String
        public let name: String
        public let pid: pid_t?
        public let resolvedBy: Resolution

        public enum Resolution: String, Sendable {
            case itself, parentChain, bundlePrefix, responsible, unresolved
        }
    }
}
