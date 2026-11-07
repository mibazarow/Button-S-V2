import AppKit
import SwiftUI
import ButtonSCore

/// Индикатор диктовки — то же поведение, что было в первой версии:
/// отдельное прозрачное окно 240×20 без рамки и тени, поверх всех окон,
/// по центру верхнего края экрана (отступ 54 pt от верхней кромки).
/// Внутри — тонкая полоска 4 pt: уровень записи, бегущая полоса при
/// распознавании, заливка на всю ширину при готовности.
@MainActor
final class HUDWindow {
    private var window: NSWindow?
    private var hosting: NSHostingView<HUDView>?
    private let model = HUDModel()

    static let width: CGFloat = 240
    static let height: CGFloat = 20
    /// Отступ от верхнего края экрана. Было 14 — упиралось в меню-бар и
    /// терялось на светлых обоях, поэтому опущено на 40 pt.
    static let topInset: CGFloat = 54

    init() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = NSRect(
            x: screen.frame.midX - Self.width / 2,
            y: screen.frame.maxY - Self.topInset - Self.height,
            width: Self.width,
            height: Self.height
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

        let view = HUDView(model: model)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        panel.contentView = host

        self.hosting = host
        self.window = panel
    }

    /// Показать и перевести в состояние «запись».
    /// Вызывается на каждом кадре уровня, поэтому повторный вызов — no-op:
    /// иначе окно перепозиционировалось бы 30 раз в секунду.
    func show() {
        guard let window else { return }
        if model.state == .recording, window.isVisible { return }
        reposition()
        model.state = .recording
        model.level = 0
        window.orderFrontRegardless()
    }

    /// Обновить уровень записи (0…1).
    func updateLevel(_ level: Float) {
        guard model.state == .recording else { return }
        model.level = level
    }

    /// Запись закончилась, идёт распознавание.
    func showProcessing() {
        model.state = .processing
        window?.orderFrontRegardless()
    }

    /// Всё готово: полоса заполняется и окно уходит.
    func showDone() {
        model.state = .done
        window?.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.model.state = .idle
            self?.window?.orderOut(nil)
        }
    }

    func hide() {
        model.state = .idle
        window?.orderOut(nil)
    }

    /// HUD может пережить смену экрана — ставим заново по центру верхнего края.
    private func reposition() {
        guard let window, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let x = screen.frame.midX - Self.width / 2
        let y = screen.frame.maxY - Self.topInset - Self.height
        window.setFrame(NSRect(x: x, y: y, width: Self.width, height: Self.height), display: true)
    }
}

enum HUDState {
    case idle
    case recording
    case processing
    case done
}

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDState = .idle
    @Published var level: Float = 0
}

struct HUDView: View {
    @ObservedObject var model: HUDModel

    private var fillWidth: CGFloat {
        switch model.state {
        case .recording:
            // level приходит из LevelMeter: RMS → дБ → шкала → сглаживание.
            return CGFloat(LevelMeter.fillPercent(level: model.level))
        case .processing:
            return 35
        case .done:
            return 100
        case .idle:
            return 4
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 18 / 255, green: 19 / 255, blue: 23 / 255).opacity(0.62))
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 1)
                    .frame(height: 4)

                fill(in: geo.size.width)
                    .frame(height: 4)
                    .clipShape(Capsule())
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: HUDWindow.width, height: HUDWindow.height)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func fill(in total: CGFloat) -> some View {
        switch model.state {
        case .recording:
            linear(colors: Self.recordingColors)
                .frame(width: max(4, total * fillWidth / 100))
                .animation(.linear(duration: 0.12), value: fillWidth)
        case .processing:
            // Бегущая полоса: 35% ширины, полный проход за 1.1 с.
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                let period: Double = 1.1
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = (t.truncatingRemainder(dividingBy: period)) / period
                let band = total * 0.35
                let travel = total + band
                let x = CGFloat(phase) * travel - band
                linear(colors: [
                    Color(red: 0.36, green: 0.58, blue: 1),
                    Color(red: 0.56, green: 0.71, blue: 1),
                ])
                .frame(width: band)
                .offset(x: x)
                .frame(width: total, alignment: .leading)
                .clipped()
            }
        case .done:
            Color(red: 0.43, green: 0.86, blue: 0.65)
                .frame(width: total)
        case .idle:
            linear(colors: Self.recordingColors)
                .frame(width: 4)
        }
    }

    private static let recordingColors = [
        Color(red: 1, green: 0.42, blue: 0.38),
        Color(red: 1, green: 0.62, blue: 0.04),
    ]

    private func linear(colors: [Color]) -> some View {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
