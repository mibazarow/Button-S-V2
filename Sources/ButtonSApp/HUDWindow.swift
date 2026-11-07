import AppKit
import SwiftUI

/// Индикатор диктовки — одно цветное пятно по центру экрана.
///
/// Раньше здесь была полоса-эквалайзер 240×20, которую кормил RMS
/// с микрофона 60 раз в секунду. Шкала никому не была нужна: от неё
/// требовался только ответ «идёт запись / идёт распознавание».
/// Теперь состояние читается по цвету точки, а звук в интерфейс
/// не течёт вообще — ни таймера, ни колбэка, ни аудио-данных.
@MainActor
final class HUDWindow {
    private var window: NSWindow?
    private let model = HUDModel()

    /// Круг 28 pt: заметно на любых обоях, но не лезет в работу.
    static let size: CGFloat = 28

    init() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.frame.midX - Self.size / 2,
            y: screen.frame.midY - Self.size / 2,
            width: Self.size,
            height: Self.size
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: Self.size, height: Self.size)
        panel.contentView = host

        self.window = panel
    }

    /// Показываем точку в состоянии «запись».
    func show() {
        model.state = .recording
        reposition()
        window?.orderFrontRegardless()
    }

    /// Запись закончилась, идёт распознавание.
    func showProcessing() {
        model.state = .processing
        window?.orderFrontRegardless()
    }

    /// Распознавание завершено — точка гаснет.
    func showDone() {
        hide()
    }

    func hide() {
        model.state = .idle
        window?.orderOut(nil)
    }

    /// Точка живёт по центру экрана; после смены экрана ставим заново.
    private func reposition() {
        guard let window, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.frame.midX - Self.size / 2,
            y: screen.frame.midY - Self.size / 2,
            width: Self.size,
            height: Self.size
        )
        window.setFrame(frame, display: true)
    }
}

enum HUDState {
    case idle
    case recording
    case processing
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .idle
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    /// Зелёный — микрофон слушает. Синий — идёт распознавание.
    private var color: Color {
        switch model.state {
        case .recording:
            return Color(red: 0.29, green: 0.87, blue: 0.44)
        case .processing:
            return Color(red: 0.33, green: 0.60, blue: 1)
        case .idle:
            return .clear
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: HUDWindow.size, height: HUDWindow.size)
            .overlay(
                Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 1)
            .frame(width: HUDWindow.size, height: HUDWindow.size)
            .allowsHitTesting(false)
    }
}
