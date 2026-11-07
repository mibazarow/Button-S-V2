import Foundation
import SwiftUI
import AppKit
import AVFoundation
import ButtonSCore
import ButtonSMac
import ButtonSVoice

/// Живой цикл приложения: перехват ввода → конвейер → правка.
@MainActor
final class AppController: ObservableObject {
    @Published var isPaused = false
    @Published var lastChange: String = "—"
    @Published var history: [AppliedChange] = []
    @Published var permissionsOK = false
    @Published var micGranted = false
    @Published var micStatusText = "неизвестно"
    @Published var isRecording = false
    @Published var recordLevel: Float = 0
    @Published var voiceError: String?
    @Published var modelState: SpeechRecognizer.ModelState = .unknown
    @Published var downloadedBytes: Int64 = 0

    let settings = SettingsStore()
    private let platform = MacPlatform()
    private lazy var engine = CorrectionEngine(actions: platform)
    private let tap = KeyboardTap()
    private let dictation = DictationService()
    private let hud = HUDWindow()

    func start() {
        refreshPermissions()
        engine.settings = settings.engineSettings
        engine.onCorrection = { [weak self] change in
            Task { @MainActor in
                guard let self else { return }
                self.history.insert(change, at: 0)
                if self.history.count > 50 { self.history.removeLast() }
                self.lastChange = "\(change.from) → \(change.to)"
            }
        }

        setupDictation()

        tap.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        tap.onTapDisabled = { [weak self] in
            Task { @MainActor in
                self?.refreshPermissions()
            }
        }
        tap.start()
    }

    func stop() {
        tap.stop()
    }

    func refreshPermissions() {
        permissionsOK = Accessibility.isTrusted()
        refreshMicrophone()
    }

    /// Статус микрофона отдельно: это другое разрешение и другой сервис TCC.
    func refreshMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            micGranted = true
            micStatusText = "разрешён"
        case .denied:
            micGranted = false
            micStatusText = "запрещён — включите в системных настройках"
        case .restricted:
            micGranted = false
            micStatusText = "ограничен системой"
        case .notDetermined:
            micGranted = false
            micStatusText = "не запрашивался"
        @unknown default:
            micGranted = false
            micStatusText = "неизвестно"
        }
    }

    /// Спрашивает микрофон только если его ещё ни разу не спрашивали.
    func requestMicrophoneIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        requestMicrophone()
    }

    /// Запрос микрофона: сначала активируем приложение, иначе macOS молча откажет.
    func requestMicrophone() {
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            // Небольшая пауза: TCC обновляет статус не мгновенно.
            try? await Task.sleep(nanoseconds: 400_000_000)
            refreshMicrophone()
        }
    }

    /// Открывает нужную панель системных настроек.
    func openPrivacyPane(_ pane: String) {
        let url = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let link = URL(string: url) {
            NSWorkspace.shared.open(link)
        }
    }

    func requestPermissions() {
        requestMicrophoneIfNeeded()
        permissionsOK = Accessibility.isTrusted(prompt: true)
        _ = Accessibility.requestInputMonitoring()
        tap.start()
        // Промпт меняет статус асинхронно — перечитываем чуть позже.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshPermissions()
        }
    }

    private func handle(_ event: InputEvent) {
        guard !isPaused else { return }
        switch event {
        case .character(let ch):
            engine.characterTyped(ch)
        case .backspace:
            engine.backspace()
        case .boundary(let ch):
            engine.boundary(ch)
        case .reset:
            engine.reset()
        case .shortcut:
            engine.reset()
        case .dictate(let down):
            handleDictation(down: down)
        }
    }

    func convertSelection() {
        guard let selected = AXContext.selection(),
              let converted = LayoutEngine.convertText(selected) else { return }
        TextInjector.replace(deleteCount: selected.count, with: converted)
    }

    func applySettings() {
        engine.settings = settings.engineSettings
        configureDictation()
    }

    // MARK: - Диктовка

    private func setupDictation() {
        dictation.recognizer.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.modelState = state
                self?.refreshModelSize()
            }
        }
        dictation.onResult = { [weak self] text in
            Task { @MainActor in
                self?.lastChange = "🎤 \(text)"
                self?.hud.showDone()
            }
        }
        dictation.onError = { [weak self] message in
            Task { @MainActor in
                self?.voiceError = message
                self?.hud.hide()
            }
        }
        dictation.onRecordingChanged = { [weak self] recording, level in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = recording
                self.recordLevel = level
                if recording {
                    self.hud.show()
                    self.hud.updateLevel(level)
                } else if self.voiceError == nil {
                    // отпустили клавишу — идёт распознавание
                    self.hud.showProcessing()
                }
            }
        }
        configureDictation()
    }

    private func configureDictation() {
        guard settings.voiceEnabled else { return }
        tap.dictateHotkey = settings.voiceKey
        let model = currentVoiceModel
        dictation.configure(model: model, language: settings.voiceLanguage)
        dictation.recognizer.refresh(for: model)
    }

    // MARK: - Модели

    var currentVoiceModel: SpeechRecognizer.ModelSize {
        SpeechRecognizer.ModelSize(rawValue: settings.whisperModel) ?? .largeV3Turbo
    }

    func refreshModelSize() {
        downloadedBytes = dictation.recognizer.downloadedSize(currentVoiceModel)
    }

    /// Перечитать состояние после смены размера модели в настройках.
    func voiceModelChanged() {
        configureDictation()
        refreshModelSize()
    }

    func downloadVoiceModel() {
        voiceError = nil
        dictation.recognizer.download(model: currentVoiceModel)
    }

    func cancelVoiceModelDownload() {
        dictation.recognizer.cancelDownload()
    }

    func deleteVoiceModel() {
        dictation.recognizer.deleteModel(currentVoiceModel)
        refreshModelSize()
    }

    private func handleDictation(down: Bool) {
        guard settings.voiceEnabled else { return }
        dictation.handleKey(down: down)
    }
}
