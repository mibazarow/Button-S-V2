import Foundation
import Combine
import WhisperKit
import ButtonSMac

/// Распознавание речи через WhisperKit — локально, без сети после загрузки модели.
///
/// В v1 ASR шёл через whisper.cpp и ggml-модели. Здесь те же веса Whisper,
/// но в CoreML-виде: быстрее на Apple Silicon и не требует Python.
///
/// Этот класс держит и саму загрузку моделей: прогресс, статус, удаление.
public final class SpeechRecognizer: @unchecked Sendable {
    public enum RecognizerError: Error, LocalizedError {
        case modelMissing
        case emptyAudio
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .modelMissing: return "Модель распознавания не скачана"
            case .emptyAudio: return "Пустая запись"
            case .failed(let reason): return reason
            }
        }
    }

    /// Доступные размеры. Имена совпадают с v1, чтобы настройки переносились.
    public enum ModelSize: String, CaseIterable, Sendable {
        case small
        case medium
        case largeV3Turbo = "large-v3-turbo"

        /// Идентификатор модели в репозитории WhisperKit.
        public var whisperKitID: String {
            switch self {
            case .small: return "openai_whisper-small"
            case .medium: return "openai_whisper-medium"
            case .largeV3Turbo: return "openai_whisper-large-v3-v20240930_turbo"
            }
        }

        public var title: String {
            switch self {
            case .small: return "small"
            case .medium: return "medium"
            case .largeV3Turbo: return "large-v3-turbo"
            }
        }

        /// Примерный вес на диске — показывается в настройках до скачивания.
        public var approxSize: String {
            switch self {
            case .small: return "~480 МБ"
            case .medium: return "~1.5 ГБ"
            case .largeV3Turbo: return "~1.6 ГБ"
            }
        }
    }

    /// Состояние модели для UI.
    public enum ModelState: Equatable, Sendable {
        case unknown
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    /// Куда кладутся модели. Отдельная папка приложения, а не общий кэш HuggingFace.
    public static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("com.button.v2", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: Состояние для UI

    private let stateLock = NSLock()
    private var _state: ModelState = .unknown
    private var _variant: ModelSize = .largeV3Turbo

    public var onStateChange: ((ModelState) -> Void)?

    public var state: ModelState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    private func setState(_ new: ModelState) {
        stateLock.lock()
        _state = new
        stateLock.unlock()
        let value = new
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(value)
        }
    }

    // MARK: Внутреннее

    private var whisper: WhisperKit?
    private var loadedModel: ModelSize?
    private var downloadTask: Task<Void, Never>?

    public init() {
        try? FileManager.default.createDirectory(at: Self.modelsDirectory,
                                                 withIntermediateDirectories: true)
    }

    // MARK: Проверка наличия

    /// Папка конкретной модели на диске.
    public func modelFolder(for model: ModelSize) -> URL {
        Self.modelsDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(model.whisperKitID, isDirectory: true)
    }

    /// Скачана ли модель целиком: ищем CoreML-бандл внутри папки.
    public func isDownloaded(_ model: ModelSize) -> Bool {
        let folder = modelFolder(for: model)
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return false }

        // У готовой модели есть папка с mlmodelc внутри.
        guard let items = try? fm.contentsOfDirectory(atPath: folder.path) else { return false }
        return items.contains { $0.hasSuffix(".mlmodelc") || $0 == "MelSpectrogram.mlmodelc" }
    }

    /// Размер скачанного на диске, в байтах.
    public func downloadedSize(_ model: ModelSize) -> Int64 {
        let folder = modelFolder(for: model)
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                              includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: Скачивание

    /// Скачивает модель с прогрессом. Безопасно вызывать повторно.
    public func download(model: ModelSize) {
        guard model != loadedModel else { return }
        downloadTask?.cancel()
        setState(.downloading(0))

        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let folder = try await WhisperKit.download(
                    variant: model.whisperKitID,
                    downloadBase: Self.modelsDirectory,
                    progressCallback: { progress in
                        self.setState(.downloading(progress.fractionCompleted))
                    }
                )
                if Task.isCancelled { return }
                let _ = folder
                self.setState(.ready)
            } catch {
                if Task.isCancelled {
                    self.setState(self.isDownloaded(model) ? .ready : .notDownloaded)
                    return
                }
                self.setState(.failed(error.localizedDescription))
            }
        }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        setState(isDownloaded(_variant) ? .ready : .notDownloaded)
    }

    /// Удаляет скачанную модель с диска.
    public func deleteModel(_ model: ModelSize) {
        downloadTask?.cancel()
        downloadTask = nil
        if loadedModel == model {
            whisper = nil
            loadedModel = nil
        }
        try? FileManager.default.removeItem(at: modelFolder(for: model))
        setState(.notDownloaded)
    }

    /// Обновляет состояние под выбранный размер модели.
    public func refresh(for model: ModelSize) {
        _variant = model
        if isDownloaded(model) {
            setState(.ready)
        } else if case .downloading = state {
            // Не сбиваем идущую загрузку.
        } else {
            setState(.notDownloaded)
        }
    }

    // MARK: Загрузка в память

    /// Грузит модель в память. Без скачивания: если файла нет — ошибка, а не тихая загрузка.
    public func prepare(model: ModelSize) async throws {
        if loadedModel == model, whisper != nil { return }
        guard isDownloaded(model) else { throw RecognizerError.modelMissing }

        do {
            let config = WhisperKitConfig(
                model: model.whisperKitID,
                downloadBase: Self.modelsDirectory,
                modelFolder: modelFolder(for: model).path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            whisper = kit
            loadedModel = model
            setState(.ready)
        } catch {
            throw RecognizerError.failed(error.localizedDescription)
        }
    }

    /// Распознаёт сэмплы 16 кГц моно.
    public func transcribe(samples: [Float], language: String) async throws -> String {
        guard !samples.isEmpty else { throw RecognizerError.emptyAudio }
        guard let whisper else { throw RecognizerError.modelMissing }
        var options = DecodingOptions()
        options.language = language == "auto" ? nil : language
        options.task = .transcribe
        options.skipSpecialTokens = true
        options.withoutTimestamps = true

        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results
            .map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return postProcess(text)
    }

    /// Убирает служебные метки и повторяющиеся пробелы.
    private func postProcess(_ text: String) -> String {
        var result = text
        let patterns = [
            "<\\|[^>]*\\|>",
            "\\[BLANK_AUDIO\\]",
            "\\(.*?music.*?\\)",
            "\\(.*?аплодис.*?\\)",
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern,
                                                 with: "",
                                                 options: [.regularExpression, .caseInsensitive])
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
