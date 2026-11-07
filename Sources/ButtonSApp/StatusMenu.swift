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
            button.image = Self.trayIcon()
            button.imagePosition = .imageOnly
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

    /// Иконка для меню-бара: жёлтый логотип приложения, вырезанный на прозрачный
/// фон — так он читается и на светлой, и на тёмной теме.
    ///
    /// `tray_icon@2x.png` (44×44) ужимаем до 18×18 — стандартная высота строки
    /// меню. `isTemplate = false` намеренно: нужен цветной логотип, а не
    /// чёрный силуэт, перекрашиваемый системой под тему.
    private static func trayIcon() -> NSImage? {
        let name = NSScreen.main?.backingScaleFactor == 2 ? "tray_icon@2x.png" : "tray_icon.png"
        guard let url = Resources.icon(name),
              let source = NSImage(contentsOf: url) else { return nil }

        let side: CGFloat = 18
        let icon = NSImage(size: NSSize(width: side, height: side))
        icon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        icon.unlockFocus()

        icon.isTemplate = false
        return icon
    }

    @objc private func togglePause() {
        controller.isPaused.toggle()
        statusItem.menu?.item(at: 0)?.title = controller.isPaused ? "Продолжить" : "Пауза"
        // На паузе иконка гаснет, а не превращается в текст — так строка меню
        // остаётся одного размера и не дёргает соседние значки.
        statusItem.button?.appearsDisabled = controller.isPaused
        statusItem.button?.toolTip = controller.isPaused ? "Button-S v2 — на паузе" : "Button-S v2"
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
