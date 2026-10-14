import AppKit
import ShutUpCore

/// "⋯" menüsü AppKit menüsü olarak kurulur.
///
/// Neden SwiftUI `Menu` değil: panel arka planda canlı (ses çalma durumu değiştikçe
/// liste tazeleniyor). SwiftUI menüsü, içinde bulunduğu görünüm yeniden çizildiğinde
/// kapanıyordu — dil listesi açılıp hemen kayboluyordu. AppKit menüsü açıkken
/// kendi döngüsünü çalıştırır, arkadaki tazelemelerden etkilenmez.
@MainActor
final class OptionsMenu: NSObject {
    private let model: ShutUpModel

    init(model: ShutUpModel) {
        self.model = model
    }

    func show() {
        let menu = NSMenu()
        menu.addItem(languageItem())
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem())
        menu.addItem(systemProcessesItem())
        menu.addItem(.separator())
        menu.addItem(quitItem())

        // Görünüm referansı vermeden fare konumunda açılır (ekran koordinatı).
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: Öğeler

    private func languageItem() -> NSMenuItem {
        let item = NSMenuItem(title: L.t("language"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for entry in L.languages {
            let option = NSMenuItem(title: entry.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = entry.code
            option.state = entry.code == model.languageCode ? .on : .off
            submenu.addItem(option)
        }
        item.submenu = submenu
        return item
    }

    private func launchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(title: L.t("launchAtLogin"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self
        item.state = model.launchesAtLogin ? .on : .off
        return item
    }

    private func systemProcessesItem() -> NSMenuItem {
        let item = NSMenuItem(title: L.t("showSystemProcesses", model.hiddenSystemCount),
                              action: #selector(toggleSystemProcesses), keyEquivalent: "")
        item.target = self
        item.state = model.showsSystemProcesses ? .on : .off
        return item
    }

    private func quitItem() -> NSMenuItem {
        let item = NSMenuItem(title: L.t("quit"), action: #selector(quit), keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Eylemler

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        model.setLanguage(code)
    }

    @objc private func toggleLaunchAtLogin() {
        model.launchesAtLogin.toggle()
    }

    @objc private func toggleSystemProcesses() {
        model.showsSystemProcesses.toggle()
    }

    @objc private func quit() {
        model.quit()
    }
}
