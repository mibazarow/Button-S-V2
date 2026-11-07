import AppKit
import SwiftUI
import ButtonSCore
import ButtonSMac

/// Точка входа: приложение живёт в меню-баре, без окна в Dock.
///
/// Здесь намеренно нет SwiftUI-сцены `MenuBarExtra`: она создавала **второй**
/// значок в меню-баре (иконка клавиатуры) рядом с тем, что рисует `StatusMenu`.
/// Два значка на одно приложение — лишний шум, поэтому запускаем `NSApplication`
/// напрямую и держим единственный `NSStatusItem` в `StatusMenu`.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusMenu: StatusMenu?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        self.controller = controller
        statusMenu = StatusMenu(controller: controller)
        controller.start()

        if !Accessibility.isTrusted() {
            controller.requestPermissions()
        } else {
            // Микрофон — отдельное разрешение, его мог никто не спрашивать.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                controller.requestMicrophoneIfNeeded()
            }
        }

        // Отладочный запуск сразу с открытыми настройками: ButtonS --open-settings
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.statusMenu?.openSettingsForDebug()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}