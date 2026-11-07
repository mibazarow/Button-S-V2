import AppKit
import SwiftUI
import ButtonSCore

/// Меню в статус-баре: пауза, конвертация выделения, настройки, выход.
@MainActor
final class StatusMenu: NSObject {
    private let controller: AppController
    private let statusItem: NSStatusItem
    private var settingsWindow: NSWindow?

    init(controller: AppController) {
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
    }

    private func buildMenu() {
        if let button = statusItem.button {
            button.title = "BS"
            button.toolTip = "Button-S v2"
        }

        let menu = NSMenu()

        let pause = NSMenuItem(title: "Пауза", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self
        menu.addItem(pause)

        let convert = NSMenuItem(title: "Сменить раскладку выделенного", action: #selector(convertSelection), keyEquivalent: "l")
        convert.target = self
        menu.addItem(convert)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let permissions = NSMenuItem(title: "Запросить разрешения", action: #selector(requestPermissions), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func togglePause() {
        controller.isPaused.toggle()
        statusItem.menu?.item(at: 0)?.title = controller.isPaused ? "Продолжить" : "Пауза"
        statusItem.button?.title = controller.isPaused ? "BS⏸" : "BS"
    }

    @objc private func convertSelection() {
        controller.convertSelection()
    }

    @objc private func requestPermissions() {
        controller.requestPermissions()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(controller: controller)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Button-S — настройки"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Открыть настройки из кода — для отладки и предпросмотра.
    func openSettingsForDebug() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
