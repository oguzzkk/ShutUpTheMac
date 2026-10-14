import Foundation

/// Core Audio HAL kurulum/yıkım işleri (tap, aggregate device, IOProc) bu seri kuyrukta yapılır.
///
/// Neden ana iş parçacığı değil: aggregate device kurulumu HAL'in bizim sürecimize geri
/// dönmesini bekleyebiliyor; ana kuyrukta yapılınca uygulama tamamen kilitleniyordu.
public let audioQueue = DispatchQueue(label: "com.oguzkaan.shutupthemac.audio")

/// Property dinleyicileri ayrı kuyrukta çalışır.
///
/// Neden ayrı: kurulum `audioQueue` üzerinde sürerken HAL aynı kuyruğa bildirim
/// göndermeye çalışırsa IOProc başlatma adımında kilitleniyor.
public let audioListenerQueue = DispatchQueue(label: "com.oguzkaan.shutupthemac.audio.listeners")
