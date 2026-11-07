import Foundation

/// Расчёт уровня записи для индикатора диктовки.
///
/// Отделён от `AudioRecorder` намеренно: это чистая математика без AVFoundation,
/// поэтому её можно проверить тестом, а не на слух.
///
/// Раньше уровень считался по пику с множителем ×4 — любой голос упирался в
/// единицу, и полоска стояла заполненной целиком. Теперь берём RMS, переводим
/// в децибелы и раскладываем по рабочему диапазону микрофона.
public enum LevelMeter {
    /// Тишина: ниже этого уровня считаем за ноль.
    public static let floorDB: Float = -60
    /// Громкая речь упирается сюда.
    public static let ceilingDB: Float = -10

    /// Среднеквадратичная громкость буфера.
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sumSquares: Float = 0
        for value in samples { sumSquares += value * value }
        return sqrt(sumSquares / Float(samples.count))
    }

    /// RMS → децибелы. Нижняя граница -140 дБ, чтобы log10 не ушёл в минус
    /// бесконечность на полной тишине.
    public static func decibels(rms: Float) -> Float {
        20 * log10(max(rms, 1e-7))
    }

    /// Итоговый уровень 0…1 для индикатора.
    public static func normalize(rms: Float) -> Float {
        let db = decibels(rms: rms)
        let span = ceilingDB - floorDB
        return min(max((db - floorDB) / span, 0), 1)
    }

    /// Сглаживание между кадрами: атака быстрая, спад медленный.
    ///
    /// Без этого полоска дёргается на каждом слоге и выглядит как случайный шум.
    public static func smooth(previous: Float, target: Float) -> Float {
        let coeff: Float = target > previous ? 0.55 : 0.12
        return previous + (target - previous) * coeff
    }

    /// Ширина заполнения полосы в процентах, с минимумом, чтобы она не исчезала.
    public static func fillPercent(level: Float, minimum: Float = 4) -> Float {
        min(100, max(minimum, level * 100))
    }
}