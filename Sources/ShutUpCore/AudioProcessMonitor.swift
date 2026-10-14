import CoreAudio
import Foundation

/// Ses süreçlerinin canlı listesini tutar.
///
/// Yoklama (polling) yok: hem süreç listesi hem de "şu an ses çalıyor mu" bilgisi
/// Core Audio'nun kendi property listener'larıyla izlenir, böylece liste
/// uygulama açılır açılmaz tazelenir.
public final class AudioProcessMonitor {
    public private(set) var processes: [AudioProcess] = []
    public var onChange: (([AudioProcess]) -> Void)?

    private var listListener: AudioObjectPropertyListenerBlock?
    private var playbackListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    public init() {}

    deinit { stop() }

    public func start() {
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        // Dinleyici ses kuyruğunda tetiklenir; liste güncellemesi ana kuyruğa taşınır.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        listListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, audioListenerQueue, listener
        )
        refresh()
    }

    public func stop() {
        if let listListener {
            var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, audioQueue, listListener
            )
        }
        listListener = nil
        for (objectID, listener) in playbackListeners {
            removePlaybackListener(listener, from: objectID)
        }
        playbackListeners.removeAll()
    }

    public func refresh() {
        let current = (try? AudioProcessList.current()) ?? []
        syncPlaybackListeners(for: current)

        processes = current.sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        onChange?(processes)
    }

    /// Her süreç için "ses çalıyor mu" dinleyicisi kurar, kapananlarınkini söker.
    private func syncPlaybackListeners(for processes: [AudioProcess]) {
        let live = Set(processes.map(\.id))

        for (objectID, listener) in playbackListeners where !live.contains(objectID) {
            removePlaybackListener(listener, from: objectID)
            playbackListeners.removeValue(forKey: objectID)
        }

        for process in processes where playbackListeners[process.id] == nil {
            var address = propertyAddress(kAudioProcessPropertyIsRunningOutput)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(process.id, &address, audioListenerQueue, listener) == noErr {
                playbackListeners[process.id] = listener
            }
        }
    }

    private func removePlaybackListener(_ listener: @escaping AudioObjectPropertyListenerBlock,
                                        from objectID: AudioObjectID) {
        var address = propertyAddress(kAudioProcessPropertyIsRunningOutput)
        AudioObjectRemovePropertyListenerBlock(objectID, &address, audioListenerQueue, listener)
    }
}
