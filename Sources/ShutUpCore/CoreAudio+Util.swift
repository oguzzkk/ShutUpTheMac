import CoreAudio
import Foundation

public struct CAError: Error, CustomStringConvertible {
    public let status: OSStatus
    public let what: String

    public var description: String {
        let code = withUnsafeBytes(of: status.bigEndian) { String(bytes: $0, encoding: .ascii) ?? "" }
        return "\(what) başarısız (OSStatus \(status) '\(code)')"
    }
}

func check(_ status: OSStatus, _ what: String) throws {
    guard status == noErr else { throw CAError(status: status, what: what) }
}

func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector,
                               mScope: kAudioObjectPropertyScopeGlobal,
                               mElement: kAudioObjectPropertyElementMain)
}

public func objectList(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
    var address = propertyAddress(selector)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size), "liste boyutu")
    let count = Int(size) / MemoryLayout<AudioObjectID>.size
    guard count > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: count)
    try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &ids), "liste okuma")
    return ids
}

func scalar<T>(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T? {
    var address = propertyAddress(selector)
    var size = UInt32(MemoryLayout<T>.size)
    var result = fallback
    let status = withUnsafeMutablePointer(to: &result) {
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
    }
    return status == noErr ? result : nil
}

public func stringProperty(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = propertyAddress(selector)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var cf: CFString?
    let status = withUnsafeMutablePointer(to: &cf) {
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
    }
    guard status == noErr else { return nil }
    return cf as String?
}
