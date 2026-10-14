import Accelerate
import CoreAudio
import Foundation
import OSLog

/// Uygulama başına ses seviyesi motoru — susturma dahil.
///
/// ÖNEMLİ: `CATapMuted` tek başına sesi kesmiyor. Başlıktaki tanım: "Audio is captured by
/// the tap but no audio is sent to the audio hardware" — yani tap'in *okunuyor* olması
/// gerekiyor. Bu yüzden susturma ayrı bir mekanizma değil, kazancı 0 olan seviyedir.
///
/// Her uygulamanın **kendi bağımsız ses yolu** vardır (kendi tap'i, kendi aggregate
/// device'ı, kendi IOProc'u). Tek bir ortak yol kullanılsaydı, bir uygulamanın sesini
/// açmak diğerlerinin yolunu da yıkıp kurardı ve hepsinde anlık ses sızardı —
/// "hepsini sustur, sonra istediğini aç" akışının tam da bozulduğu yer burasıydı.
public final class VolumeEngine {

    public struct Target: Equatable {
        public let bundleID: String
        public let name: String
        public let members: Set<AudioObjectID>
        /// Gruptaki süreçlerin bundle ID'leri. Süreç ölüp yeniden doğduğunda
        /// tap'in onu kendiliğinden geri alabilmesi için gerekiyor.
        public let processBundleIDs: Set<String>
        public let gain: Float

        public init(bundleID: String, name: String, members: Set<AudioObjectID>,
                    processBundleIDs: Set<String> = [], gain: Float) {
            self.bundleID = bundleID
            self.name = name
            self.members = members
            self.processBundleIDs = processBundleIDs
            self.gain = gain
        }
    }

    /// Tek bir uygulamanın ses yolu.
    private final class Channel {
        let bundleID: String
        let members: Set<AudioObjectID>
        /// Yolun hangi "şey"e kurulduğu. macOS 26'da tap süreçleri bundle ID ile
        /// hatırladığı için imza bundle ID kümesidir: süreç ölüp yeniden doğduğunda
        /// yol yıkılmaz, tap yeni süreci kendisi geri alır.
        var identity: Set<String> = []
        let gain = GainBox()
        var tapID = AudioObjectID(kAudioObjectUnknown)
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        var ioProcID: AudioDeviceIOProcID?
        var overloadListener: AudioObjectPropertyListenerBlock?
        /// Yolun bağlı olduğu çıkış aygıtı — kulaklık/hoparlör değişiminde
        /// yolun gerçekten yenilendiğini dışarıdan doğrulayabilmek için.
        var outputDeviceName = "?"

        init(bundleID: String, members: Set<AudioObjectID>, identity: Set<String>) {
            self.bundleID = bundleID
            self.members = members
            self.identity = identity
        }
    }

    /// Susturulmuş uygulamaların hepsi tek bir yolda toplanır.
    ///
    /// Her uygulamaya ayrı aggregate device vermek, her biri saniyede ~86 kez uyanan
    /// ayrı bir gerçek zamanlı iş parçacığı demekti; 15 susturulmuş uygulamada bu
    /// ölçülebilir dropout üretiyordu. Susturulanların çıktısı zaten aynı (sessizlik),
    /// dolayısıyla tek tap listesi yeterli. Listeye biri girip çıktığında yol yeniden
    /// kuruluyor ama bu duyulmaz: içindeki her şey zaten sessiz.
    ///
    /// Seviyesi kısılmış (0 < kazanç < 1) uygulamalar kendi yollarında kalır; onların
    /// her birinin kazancı farklı ve sesi gerçekten çalınıyor.
    private static let silentChannelKey = "\u{0000}muted"

    private var channels: [String: Channel] = [:]
    /// Kurulumu süren (ve belki takılmış) uygulamalar — aynı anda ikinci deneme açılmasın.
    private var pendingBuilds: Set<String> = []
    /// Zaman aşımına uğrayanlar bir süre yeniden denenmez; aksi hâlde her turda
    /// yeni bir iş parçacığı takılıp kalıyor.
    private var cooldown: [String: Date] = [:]
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var lastTargets: [Target] = []
    private var buildInFlight = false

    private let log = Logger(subsystem: Settings.suiteName, category: "volume")

    /// Ses yolu kurulamadı; sebebi büyük olasılıkla sistem sesi okuma izninin olmaması.
    public private(set) var needsPermission = false

    /// Uygulama izni almış mı? İzin varken yaşanan zaman aşımları geçici sayılır,
    /// motor kalıcı olarak kilitlenmez (tek yavaş kurulum her şeyi durduruyordu).
    public var permissionGranted = false

    public static var trace = false
    /// Ses donanımının takvimini kaçırdığımız durumların sayısı (dropout).
    public nonisolated(unsafe) static var overloads: UInt64 = 0
    public private(set) static var meters = Meters()

    public init() {
        var address = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            audioQueue.async {
                guard !self.channels.isEmpty else { return }
                self.log.info("çıkış aygıtı değişti, ses yolları yeniden kuruluyor")
                let targets = self.lastTargets
                self.tearDownOnAudioQueue()
                self.applyOnAudioQueue(targets)
            }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),
                                            &address, audioListenerQueue, listener)
    }

    deinit { tearDownOnAudioQueue() }

    public var isRunning: Bool { !channels.isEmpty }
    public var activeTapCount: Int { channels.count }

    /// Kurulu yolların hangi çıkış aygıtına bağlı olduğu.
    public var boundOutputDevices: [String: String] {
        channels.mapValues(\.outputDeviceName)
    }

    // MARK: Uygulama

    public func apply(targets: [Target]) {
        audioQueue.async { [weak self] in self?.applyOnAudioQueue(targets) }
    }

    private func applyOnAudioQueue(_ targets: [Target]) {
        let valid = targets.filter { !$0.members.isEmpty || !$0.processBundleIDs.isEmpty }
        lastTargets = valid

        let silent = valid.filter { $0.gain <= 0 }
        let attenuated = valid.filter { $0.gain > 0 }

        // Susturulanları tek bir hedefte birleştir.
        let merged: Target? = silent.isEmpty ? nil : Target(
            bundleID: Self.silentChannelKey,
            name: "susturulanlar (\(silent.count))",
            members: silent.reduce(into: Set<AudioObjectID>()) { $0.formUnion($1.members) },
            processBundleIDs: silent.reduce(into: Set<String>()) { $0.formUnion($1.processBundleIDs) },
            gain: 0)

        let effective = attenuated + (merged.map { [$0] } ?? [])
        let wanted = Set(effective.map(\.bundleID))

        // Artık ayarı olmayan uygulamaların yolunu kapat — diğerlerine dokunmadan.
        for bundleID in channels.keys where !wanted.contains(bundleID) {
            closeChannel(bundleID)
        }

        for target in effective {
            if let channel = channels[target.bundleID] {
                if channel.identity == identity(of: target) {
                    channel.gain.value = target.gain      // yalnızca seviye değişti
                    continue
                }
                closeChannel(target.bundleID)             // kapsam değişti, tazele
            }

            guard !needsPermission else { continue }
            guard !pendingBuilds.contains(target.bundleID) else { continue }
            if let until = cooldown[target.bundleID], until > Date() { continue }

            do {
                try openChannelWithWatchdog(for: target)
            } catch {
                trace("HATA — \(target.name): \(error)")
            }
        }
    }

    /// İzin verilmediğinde Core Audio çağrısı süresiz bekliyor; 4 saniyede bitmezse
    /// izin sorunu kabul edilir ve uygulama donmadan devam eder.
    private func openChannelWithWatchdog(for target: Target) throws {
        guard !buildInFlight else { throw CAError(status: -3, what: "kurulum sırada") }
        buildInFlight = true
        pendingBuilds.insert(target.bundleID)
        defer { buildInFlight = false }

        var result: Result<Channel, Error>?
        let finished = DispatchSemaphore(value: 0)
        let bundleID = target.bundleID

        DispatchQueue(label: "com.oguzkaan.shutupthemac.audio.build").async { [weak self] in
            guard let self else { finished.signal(); return }
            do { result = .success(try openChannel(for: target)) } catch { result = .failure(error) }
            finished.signal()
            // Geç de olsa döndüyse kaydı temizle; takılı kalan iş parçacığı buraya hiç gelmez.
            audioQueue.async { [weak self] in self?.pendingBuilds.remove(bundleID) }
        }

        if finished.wait(timeout: .now() + 4) == .timedOut {
            cooldown[bundleID] = Date().addingTimeInterval(60)
            if permissionGranted {
                trace("zaman aşımı (izin var) — 60 sn yeniden denenmeyecek: \(target.name)")
                log.error("ses yolu kurulumu gecikti: \(target.name, privacy: .public)")
            } else {
                needsPermission = true
                trace("zaman aşımı — sistem sesi okuma izni yok görünüyor")
                log.error("ses yolu kurulamadı: izin bekleniyor")
            }
            throw CAError(status: -2, what: "zaman aşımı")
        }

        pendingBuilds.remove(bundleID)
        switch result {
        case .success(let channel): channels[target.bundleID] = channel
        case .failure(let error): throw error
        case .none: break
        }
    }

    public func clearPermissionBlock() {
        audioQueue.async { [weak self] in self?.needsPermission = false }
    }

    // MARK: Tek uygulamanın yolu

    /// Yolun kimliği: macOS 26'da bundle ID kümesi (süreç yenilenmesi yolu bozmaz),
    /// daha eskisinde süreç nesneleri.
    private func identity(of target: Target) -> Set<String> {
        if #available(macOS 26.0, *), !target.processBundleIDs.isEmpty {
            return target.processBundleIDs
        }
        return Set(target.members.map(String.init))
    }

    private func openChannel(for target: Target) throws -> Channel {
        let channel = Channel(bundleID: target.bundleID, members: target.members,
                              identity: identity(of: target))
        channel.gain.value = target.gain

        let description: CATapDescription

        // macOS 26: tap'i süreç nesnelerine değil bundle ID'lere kur.
        //
        // Neden şart: `systemsoundserverd` boştayken Core Audio'nun süreç listesinden
        // tamamen düşüyor; süreç nesnesine bağlı bir yol o anda kapanıyor ve ses çalacağı
        // anda yeniden kurmaya yetişilemiyor. Bundle ID'ye kurulan tap, süreç var olmasa
        // bile ayakta kalıyor ve süreç doğduğu anda onu kapsıyor. Aynı şey kapalı bir
        // uygulamayı önceden susturmayı da mümkün kılıyor.
        if #available(macOS 26.0, *), !target.processBundleIDs.isEmpty {
            description = CATapDescription()
            description.bundleIDs = Array(target.processBundleIDs)
            description.processes = []
            description.isMixdown = true
            description.isMono = false
            description.isExclusive = false
            description.isProcessRestoreEnabled = true
        } else {
            description = CATapDescription(stereoMixdownOfProcesses: Array(target.members))
        }

        description.name = "Shut Up The Mac — \(target.name)"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped   // biz okurken doğrudan ses çıkmasın

        try check(AudioHardwareCreateProcessTap(description, &channel.tapID), "tap oluşturma")
        guard let tapUID = stringProperty(channel.tapID, kAudioTapPropertyUID) else {
            AudioHardwareDestroyProcessTap(channel.tapID)
            throw CAError(status: -1, what: "tap UID")
        }

        // Çıkış aygıtı aggregate'in içinde olmak zorunda: IO döngüsünü süren saat kaynağı o.
        // Tap-only aggregate denedim, IOProc hiç tetiklenmedi (çağrı sayısı 0) ve
        // dolayısıyla tap okunmadığı için susturma da gerçekleşmedi.
        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Shut Up The Mac — \(target.name)",
            kAudioAggregateDeviceUIDKey: "com.oguzkaan.shutupthemac.\(target.bundleID).\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID,
                                               kAudioSubTapDriftCompensationKey: 1]],
        ]

        let outputID = try defaultOutputDevice()
        guard let outputUID = stringProperty(outputID, kAudioDevicePropertyDeviceUID) else {
            AudioHardwareDestroyProcessTap(channel.tapID)
            throw CAError(status: -1, what: "çıkış aygıtı UID")
        }
        aggregate[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
        aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        channel.outputDeviceName = stringProperty(outputID, kAudioObjectPropertyName) ?? outputUID
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &channel.aggregateID),
                  "aggregate device")

        let gain = channel.gain
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, channel.aggregateID, nil) {
            _, inputData, _, outputData, _ in
            Self.render(input: inputData, output: outputData, gain: gain.value)
        }, "IOProc")

        guard let procID else { throw CAError(status: -1, what: "IOProc kimliği") }
        channel.ioProcID = procID

        // Core Audio, IOProc zamanında yetişemediğinde bunu bildiriyor. Sesteki
        // takılmaların objektif ölçüsü bu: sayaç artıyorsa gerçekten dropout var.
        var overloadAddress = propertyAddress(kAudioDeviceProcessorOverload)
        let overloadListener: AudioObjectPropertyListenerBlock = { _, _ in
            Self.overloads &+= 1
        }
        channel.overloadListener = overloadListener
        AudioObjectAddPropertyListenerBlock(channel.aggregateID, &overloadAddress,
                                            audioListenerQueue, overloadListener)

        try check(AudioDeviceStart(channel.aggregateID, procID), "IOProc başlatma")

        trace("yol açıldı: \(target.name) · süreç=\(target.members.count) · kazanç=\(target.gain)")
        return channel
    }

    private func closeChannel(_ bundleID: String) {
        guard let channel = channels.removeValue(forKey: bundleID) else { return }
        if let listener = channel.overloadListener, channel.aggregateID != AudioObjectID(kAudioObjectUnknown) {
            var address = propertyAddress(kAudioDeviceProcessorOverload)
            AudioObjectRemovePropertyListenerBlock(channel.aggregateID, &address, audioListenerQueue, listener)
        }
        if let procID = channel.ioProcID {
            AudioDeviceStop(channel.aggregateID, procID)
            AudioDeviceDestroyIOProcID(channel.aggregateID, procID)
        }
        if channel.aggregateID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(channel.aggregateID)
        }
        if channel.tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(channel.tapID)
        }
        trace("yol kapandı: \(bundleID)")
    }

    /// Gerçek zamanlı geri çağırım: tap girdisini kazançla çıkışa yazar.
    /// Bellek ayırma, kilit ve log yok — aksi hâlde ses kesilir.
    /// Gerçek zamanlı geri çağırım. Burada yapılan her fazladan iş, ses kesilmesi
    /// (dropout) riski demek: bu blok her ~6 milisaniyede bir, ses donanımının
    /// takviminde çalışıyor ve geç kalırsa Core Audio "overload" sayıyor.
    ///
    /// İki şey önemli:
    ///  • Tam susturmada girdiye hiç bakmıyoruz — çıkışı sıfırlayıp çıkıyoruz.
    ///    En sık kullanılan durum bu ve neredeyse bedava.
    ///  • Seviye kısmada örnek örnek Swift döngüsü yerine vDSP kullanılıyor (SIMD).
    ///  • Ölçerler her çağrıda değil, seyrek güncelleniyor; tanı içindir, sesten önemli değil.
    private static func render(input: UnsafePointer<AudioBufferList>,
                               output: UnsafeMutablePointer<AudioBufferList>,
                               gain: Float) {
        let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
        for outputBuffer in outputBuffers {
            memset(outputBuffer.mData, 0, Int(outputBuffer.mDataByteSize))
        }

        guard gain > 0 else {
            // Susturma: çıkış sıfırlandı, girdiyi işlemeye gerek yok.
            // Yalnızca tanı için, 32 çağrıda bir girdinin tepe değerini ölçüyoruz —
            // "gerçekten ses yakalanıyor mu" sorusunun tek dışarıdan görünür kanıtı bu.
            meterTick &+= 1
            guard meterTick % 32 == 0,
                  let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first,
                  let sourceData = source.mData?.assumingMemoryBound(to: Float32.self) else { return }
            var peak: Float = 0
            vDSP_maxmgv(sourceData, 1, &peak, vDSP_Length(Int(source.mDataByteSize) / MemoryLayout<Float32>.size))
            meters.record(input: peak, output: 0)
            return
        }

        guard let destination = outputBuffers.first,
              let destinationData = destination.mData?.assumingMemoryBound(to: Float32.self) else { return }
        let frameCount = vDSP_Length(Int(destination.mDataByteSize) / MemoryLayout<Float32>.size)

        let inputBuffers = UnsafeBufferPointer(start: &UnsafeMutablePointer(mutating: input).pointee.mBuffers,
                                               count: Int(input.pointee.mNumberBuffers))
        var scale = gain
        var inputPeak: Float = 0

        for index in 0..<inputBuffers.count {
            let buffer = inputBuffers[index]
            guard let sourceData = buffer.mData?.assumingMemoryBound(to: Float32.self) else { continue }
            let count = min(frameCount, vDSP_Length(Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size))

            // çıkış = giriş * kazanç + çıkış
            vDSP_vsma(sourceData, 1, &scale, destinationData, 1, destinationData, 1, count)

            if meterTick % 32 == 0 {
                var peak: Float = 0
                vDSP_maxmgv(sourceData, 1, &peak, count)
                if peak > inputPeak { inputPeak = peak }
            }
        }

        meterTick &+= 1
        if meterTick % 32 == 0 {
            var outputPeak: Float = 0
            vDSP_maxmgv(destinationData, 1, &outputPeak, frameCount)
            meters.record(input: inputPeak, output: outputPeak)
        }
    }

    private nonisolated(unsafe) static var meterTick: UInt64 = 0

    private func defaultOutputDevice() throws -> AudioObjectID {
        guard let deviceID = scalar(AudioObjectID(kAudioObjectSystemObject),
                                    kAudioHardwarePropertyDefaultOutputDevice,
                                    AudioObjectID(0)), deviceID != 0 else {
            throw CAError(status: -1, what: "varsayılan çıkış aygıtı")
        }
        return deviceID
    }

    // MARK: Yıkım

    public func tearDown() {
        audioQueue.sync { tearDownOnAudioQueue() }
    }

    private func tearDownOnAudioQueue() {
        for bundleID in channels.keys { closeChannel(bundleID) }
    }

    private func trace(_ message: String) {
        guard Self.trace else { return }
        FileHandle.standardError.write("  [iz] \(message)\n".data(using: .utf8)!)
    }
}

/// IOProc'un kilitsiz okuduğu tek kazanç değeri.
final class GainBox: @unchecked Sendable {
    var value: Float = 1.0
}

/// Ses yolundan geçen sinyalin tepe değerleri (tanı amaçlı).
public final class Meters: @unchecked Sendable {
    public private(set) var inputPeak: Float = 0
    public private(set) var outputPeak: Float = 0
    public private(set) var callbacks: Int = 0

    @inline(__always)
    func record(input: Float, output: Float) {
        if input > inputPeak { inputPeak = input }
        if output > outputPeak { outputPeak = output }
        callbacks += 1
    }

    public func reset() { inputPeak = 0; outputPeak = 0; callbacks = 0 }
}
