import Foundation
import AVFoundation
import ButtonSCore
import ButtonSMac

/// Диктовка: удержание клавиши → запись → распознавание → вставка в поле.
///
/// Удержание: пока клавиша нажата, пишем звук; отпустили — распознаём
/// и вставляем текст туда, где стоит курсор.
///
/// Класс изолирован на главном акторе: колбэки и состояние живут в одном месте,
/// а распознавание уходит в фоновую задачу и возвращает только строку.
@MainActor
public final class DictationService {
    public enum DictationError: Error, LocalizedError {
        case tooShort
        case empty
        case notReady

        public var errorDescription: String? {
            switch self {
            case .tooShort: return "Слишком короткая запись"
            case .empty: return "Ничего не распознано"
            case .notReady: return "Модель ещё не загружена"
            }
        }
    }

    private let recorder = AudioRecorder()
    /// Наружу — чтобы настройки могли качать и удалять модели.
    public let recognizer = SpeechRecognizer()

    private var isDown = false
    private var prepareTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var model: SpeechRecognizer.ModelSize = .largeV3Turbo
    private var language = "ru"

    /// Вызывается, когда текст распознан и уже вставлен.
    public var onResult: ((String) -> Void)?
    /// Вызывается с текстом ошибки.
    public var onError: ((String) -> Void)?
    /// Индикатор записи: true — пишем, второе значение — уровень 0...1.
    public var onRecordingChanged: ((Bool, Float) -> Void)?

    public init() {}

    /// Прогревает модель заранее, чтобы первая диктовка не ждала загрузку.
    public func preload(model: SpeechRecognizer.ModelSize, language: String) {
        self.model = model
        self.language = language
        prepareTask?.cancel()
        prepareTask = Task { [recognizer, model] in
            // Тихо грузим только если модель уже на диске — качать из-под диктовки нельзя.
            guard recognizer.isDownloaded(model) else { return }
            try? await recognizer.prepare(model: model)
        }
    }

    public func configure(model: SpeechRecognizer.ModelSize, language: String) {
        if self.model != model || self.language != language {
            self.model = model
            self.language = language
            preload(model: model, language: language)
        }
    }

    /// Нажатие/отпускание горячей клавиши.
    public func handleKey(down: Bool) {
        if down {
            guard !isDown else { return }
            isDown = true
            startRecording()
        } else {
            guard isDown else { return }
            isDown = false
            finishRecording()
        }
    }

    private func startRecording() {
        do {
            try recorder.start()
            onRecordingChanged?(true, 0)
            startLevelFeed()
        } catch {
            onError?(error.localizedDescription)
        }
    }

    /// Пока идёт запись, отдаём уровень 20 раз в секунду — для индикатора.
    private func startLevelFeed() {
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.recorder.isRecording else { return }
                self.onRecordingChanged?(true, self.recorder.level)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func finishRecording() {
        levelTask?.cancel()
        levelTask = nil
        let samples = recorder.stop()
        onRecordingChanged?(false, 0)

        // Меньше 0,3 с — это случайное касание, а не речь.
        guard samples.count >= 4_800 else { return }

        let model = self.model
        let language = self.language
        let recognizer = self.recognizer

        Task {
            do {
                try await recognizer.prepare(model: model)
                let text = try await recognizer.transcribe(samples: samples, language: language)
                guard !text.isEmpty else { throw DictationError.empty }
                _ = TextInjector.type(text)
                onResult?(text)
            } catch {
                onError?(error.localizedDescription)
            }
        }
    }
}
