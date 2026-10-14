import AppKit
import CoreAudio
import Darwin
import Foundation

/// Core Audio'nun tanıdığı, ses üretebilen tek bir süreç (ana uygulama ya da yardımcı süreç).
public struct AudioProcess: Identifiable, Hashable, Sendable {
    public let id: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?
    public let isPlaying: Bool
    public let name: String
    public let owner: ProcessHierarchy.Owner

    public var resolution: ProcessHierarchy.Owner.Resolution { owner.resolvedBy }

    init(objectID: AudioObjectID) {
        let pid = scalar(objectID, kAudioProcessPropertyPID, pid_t(-1)) ?? -1
        let rawBundleID = stringProperty(objectID, kAudioProcessPropertyBundleID)
        let bundleID = (rawBundleID?.isEmpty ?? true) ? nil : rawBundleID
        self.id = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isPlaying = (scalar(objectID, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) == 1
        self.name = Self.resolveName(pid: pid, bundleID: bundleID)
        self.owner = ProcessHierarchy.owner(ofPID: pid, bundleID: bundleID)
    }

    public var icon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    private static func resolveName(pid: pid_t, bundleID: String?) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName, !name.isEmpty {
            return name
        }
        if let executable = executableName(pid: pid) { return executable }
        if let bundleID, let last = bundleID.split(separator: ".").last { return String(last) }
        return "pid \(pid)"
    }

    /// NSRunningApplication tanımayan yardımcı süreçler için çalıştırılabilir dosya adı.
    private static func executableName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : (path as NSString).lastPathComponent
    }
}

public enum AudioProcessList {
    public static func current() throws -> [AudioProcess] {
        try objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
            .map(AudioProcess.init(objectID:))
            .filter { $0.pid > 0 }
    }
}
