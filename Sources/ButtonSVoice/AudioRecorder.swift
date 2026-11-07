import Foundation
import AVFoundation
import ButtonSCore
import ButtonSMac

/// Запись с микрофона в память, без файлов.
///
/// Порт голосовой части v1 без whisper-rs: пишем float-сэмплы 16 кГц,
/// дальше их отдаёт распознавателю.
public final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private let targetRate: Double = 16_000

    public private(set) var isRecording = false
    /// Текущая громкость 0...1 для индикатора.
    public private(set) var level: Float = 0

    public init() {}

    public func start() throws {
        guard !isRecording else { return }
        guard awaitMicrophone() else {
            throw RecorderError.noMicrophone
        }

        samples.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecorderError.noInput }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: targetRate,
                                         channels: 1,
                                         interleaved: false)
        guard let targetFormat,
              let converter = AVAudioConverter(from: format, to: targetFormat) else {
            throw RecorderError.converter
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.consume(buffer: buffer, target: targetFormat)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    @discardableResult
    public func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false

        lock.lock()
        let result = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        return result
    }

    public func cancel() {
        _ = stop()
        level = 0
    }

    private func consume(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        if error != nil { return }
        guard let channel = output.floatChannelData?[0], output.frameLength > 0 else { return }

        let frames = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))

        lock.lock()
        if samples.count < 16_000 * 400 {
            samples.append(contentsOf: frames)
        }
        lock.unlock()

        var peak: Float = 0
        for value in frames { peak = max(peak, abs(value)) }
        level = min(peak * 4, 1)
    }

    private func awaitMicrophone() -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return granted
        default:
            return false
        }
    }

    public enum RecorderError: Error, LocalizedError {
        case noMicrophone
        case noInput
        case converter

        public var errorDescription: String? {
            switch self {
            case .noMicrophone: return "Нет доступа к микрофону"
            case .noInput: return "Микрофон не найден"
            case .converter: return "Не удалось подготовить форматы звука"
            }
        }
    }
}
