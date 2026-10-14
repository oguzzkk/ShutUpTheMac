import AppKit
import Combine
import ShutUpCore
import SwiftUI

@MainActor
final class ShutUpDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = ShutUpModel()
    private var cancellables = Set<AnyCancellable>()
    /// App Nap, menü çubuğu uygulamasını uyutup Darwin bildirimlerini askıya alıyor.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        VolumeEngine.trace = ProcessInfo.processInfo.environment["SHUTUP_TRACE"] != nil
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Ses yolunu ve uygulama dinleyicilerini canlı tutar"
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIcon.image(muted: false)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PanelView().environmentObject(model))

        model.startListening()
        model.ensureLaunchAtLogin()

        // Simge, susturulmuş uygulama var mı bilgisini yansıtsın.
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.releaseAll()
    }

    @objc private func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        model.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func refreshIcon() {
        statusItem.button?.image = StatusIcon.image(muted: model.mutedCount > 0)
    }
}

/// NSApplication.delegate zayıf referans tuttuğu için delegate burada canlı tutulur.
@MainActor
private enum Launcher {
    static var delegate: ShutUpDelegate?

    static func run() {
        let app = NSApplication.shared
        let delegate = ShutUpDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

MainActor.assumeIsolated { Launcher.run() }
