import CoreAudio
import Foundation

/// Ses yolunun gerçekten kurulup kurulmadığını dışarıdan görebilmek için.
public enum Diagnostics {

    /// Motorun adımlarını çekirdek modülün içinden, sınıf durumu olmadan tekrarlar.
    public static func inlineInCore(group: AppGroup) -> String {
        let description = CATapDescription(stereoMixdownOfProcesses: group.members.map(\.id))
        description.name = "Shut Up The Mac — \(group.name) (seviye)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        let uid = stringProperty(tapID, kAudioTapPropertyUID)
        if status == noErr { AudioHardwareDestroyProcessTap(tapID) }
        return "çekirdek içi: status=\(status) tapID=\(tapID) uid=\(uid ?? "OKUNAMADI")"
    }


    /// Tap oluşturmanın hangi parametre bileşiminde sağlam nesne verdiğini ölçer.
    public static func tapExperiment(group: AppGroup) -> [String] {
        var lines: [String] = []
        let playing = group.members.filter(\.isPlaying).map(\.id)
        let all = group.members.map(\.id)

        let cases: [(String, [AudioObjectID], CATapMuteBehavior)] = [
            ("tek süreç (çalan) / unmuted", Array(playing.prefix(1)), .unmuted),
            ("tek süreç (çalan) / mutedWhenTapped", Array(playing.prefix(1)), .mutedWhenTapped),
            ("tüm üyeler / unmuted", all, .unmuted),
            ("tüm üyeler / mutedWhenTapped", all, .mutedWhenTapped),
        ]

        // İsim etkisi: ASCII olmayan karakter tap'i bozuyor mu?
        for (label, name) in [("ascii isim", "ShutUp Unity level"), ("em dash isim", "Shut Up The Mac — Unity (seviye)")] {
            let description = CATapDescription(stereoMixdownOfProcesses: all)
            description.name = name
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            lines.append("\(label): status=\(status) tapID=\(tapID) uid=\(stringProperty(tapID, kAudioTapPropertyUID) ?? "OKUNAMADI")")
            if status == noErr { AudioHardwareDestroyProcessTap(tapID) }
        }

        for (label, processes, behavior) in cases {
            guard !processes.isEmpty else { lines.append("\(label): süreç yok, atlandı"); continue }
            let description = CATapDescription(stereoMixdownOfProcesses: processes)
            description.name = "deney"
            description.isPrivate = true
            description.muteBehavior = behavior

            var tapID = AudioObjectID(kAudioObjectUnknown)
            let status = AudioHardwareCreateProcessTap(description, &tapID)
            let uid = stringProperty(tapID, kAudioTapPropertyUID)
            lines.append("\(label): status=\(status) tapID=\(tapID) uid=\(uid ?? "OKUNAMADI")")
            if status == noErr { AudioHardwareDestroyProcessTap(tapID) }
        }
        return lines
    }

    public static func audioObjects() -> [String] {
        var lines: [String] = []

        let taps = (try? objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTapList)) ?? []
        lines.append("tap sayısı: \(taps.count)")
        for tap in taps {
            let uid = stringProperty(tap, kAudioTapPropertyUID) ?? "—"
            lines.append("  tap \(tap)  \(uid)")
        }

        // UID okuma hatasını çıplak OSStatus ile göster
        for tap in taps {
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyUID,
                                                     mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            let sizeStatus = AudioObjectGetPropertyDataSize(tap, &address, 0, nil, &size)
            var cf: Unmanaged<CFString>?
            var dataSize = UInt32(MemoryLayout<CFString?>.size)
            let dataStatus = withUnsafeMutablePointer(to: &cf) {
                AudioObjectGetPropertyData(tap, &address, 0, nil, &dataSize, $0)
            }
            let resolved = cf?.takeUnretainedValue() as String? ?? "nil"
            lines.append("  tanı: tap \(tap) sizeStatus=\(sizeStatus) size=\(size) dataStatus=\(dataStatus) uid=\(resolved)")
        }

        let devices = (try? objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)) ?? []
        for device in devices {
            let name = stringProperty(device, kAudioObjectPropertyName) ?? "?"
            let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) ?? "?"
            if uid.contains("shutupthemac") || name.contains("Shut Up") {
                lines.append("aggregate: \(name)  (\(uid))")
            }
        }
        return lines
    }
}
