import AppKit
import SwiftUI
import ButtonSCore
import ButtonSMac

/// Точка входа: приложение живёт в статус-баре, без окна в Dock по умолчанию.
@main
struct ButtonSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // Окно настроек создаётся вручную в StatusMenu: служебная сцена `Settings`
    // здесь не нужна и перехватывает ⌘, своим пустым окном.
    var body: some Scene {
        MenuBarExtra("Button-S", systemImage: "keyboard") {
            EmptyView()
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var statusMenu: StatusMenu?

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

        // Отладочный запуск сразу с открытыми настройками: ButtonS --open-settings
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
