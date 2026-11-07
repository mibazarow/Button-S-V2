import Foundation

/// Частотные списки слов и морфологический словарь русского.
///
/// В оригинале (Rust) морфология лежала в fst-автомате на 4,7 МБ.
/// В Swift fst-крейта нет, поэтому автомат разворачивается в `Set<String>`
/// при первом обращении. Память дешёвая, загрузка мгновенная.
public final class Dictionary: @unchecked Sendable {
    public static let shared = Dictionary()

    public struct WordList: Sendable {
        public let words: [String]
        public let chars: [[Character]]
        public let scores: [String: Float]
        /// Веса параллельно `words` — чтобы горячий цикл не хешировал строки.
        public let scoreValues: [Float]
        /// Кодпоинты параллельно `words`.
        ///
        /// Расстояние Дамерау считаем по ним, а не по `[Character]`:
        /// сравнение графемных кластеров в Swift дорогое, а сравнение
        /// целых чисел — одна инструкция. На замерах это дало разницу
        /// в разы на одном и том же алгоритме.
        public let codepoints: [[UInt32]]
        /// Индексы слов по первому кодпоинту.
        public let indicesByFirst: [UInt32: [Int]]

        public init(words: [String],
                    chars: [[Character]],
                    scores: [String: Float],
                    scoreValues: [Float],
                    codepoints: [[UInt32]],
                    indicesByFirst: [UInt32: [Int]]) {
            self.words = words
            self.chars = chars
            self.scores = scores
            self.scoreValues = scoreValues
            self.codepoints = codepoints
            self.indicesByFirst = indicesByFirst
        }
    }

    public let ru: WordList
    public let en: WordList
    private let ruForms: Set<String>

    private init() {
        let ruRaw = Self.loadText("ru_30k")
        let enRaw = Self.loadText("en_30k")
        self.ru = Self.build(ruRaw)
        self.en = Self.build(enRaw)
        self.ruForms = Self.loadForms()
    }

    // MARK: - Загрузка ресурсов

    private static func resourceDirectory() -> URL? {
        let fm = FileManager.default

        // 1) SPM-бандл модуля: Data лежит внутри него как каталог-ресурс.
        if let bundleURL = Bundle.module.resourceURL {
            let data = bundleURL.appendingPathComponent("Data")
            if fm.fileExists(atPath: data.path) { return data }
            let nested = bundleURL.appendingPathComponent("Contents/Resources/Data")
            if fm.fileExists(atPath: nested.path) { return nested }
        }

        // 2) установленное приложение: ресурсы рядом с бинарником.
        if let bundleURL = Bundle.main.resourceURL {
            let data = bundleURL.appendingPathComponent("Data")
            if fm.fileExists(atPath: data.path) { return data }
        }

        // 3) запуск из исходников (swift run / отладка).
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Data")
        if fm.fileExists(atPath: source.path) { return source }

        return nil
    }

    private static func loadText(_ name: String) -> String {
        guard let dir = resourceDirectory() else { return "" }
        let url = dir.appendingPathComponent("\(name).txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Загружает морфологический словарь русского.
    ///
    /// В оригинале формы лежали в `fst::Set` (4,7 МБ). Отдельного читателя
    /// fst в Swift нет, поэтому автомат развёрнут утилитой на Rust-крейте
    /// `fst` в плоский список — `ru_words.txt`.
    private static func loadForms() -> Set<String> {
        guard let dir = resourceDirectory() else { return [] }
        let url = dir.appendingPathComponent("ru_words.txt")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
    }

    // MARK: - Поиск

    public func list(_ language: String) -> WordList? {
        switch language {
        case "ru": return ru
        case "en": return en
        default: return nil
        }
    }

    public func score(_ language: String, _ word: String) -> Float {
        let key = Self.normalize(word)
        return list(language)?.scores[key] ?? 0
    }

    public func known(_ language: String, _ word: String) -> Bool {
        switch language {
        case "ru": return ruForms.contains(Self.normalize(word))
        case "en": return score("en", word) > 0
        default: return false
        }
    }

    // MARK: - Построение

    private static func build(_ raw: String) -> WordList {
        var words: [String] = []
        words.reserveCapacity(32_000)
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            words.append(String(line))
        }

        let total = Float(max(words.count, 1))
        var scores: [String: Float] = [:]
        scores.reserveCapacity(words.count)
        var chars: [[Character]] = []
        chars.reserveCapacity(words.count)
        var scoreValues: [Float] = []
        scoreValues.reserveCapacity(words.count)
        var codepoints: [[UInt32]] = []
        codepoints.reserveCapacity(words.count)
        var indicesByFirst: [UInt32: [Int]] = [:]
        indicesByFirst.reserveCapacity(128)

        for (rank, word) in words.enumerated() {
            // Тот же вес, что в Rust: чем выше слово в списке, тем больше score.
            let value = log10((total + 1) / (Float(rank) + 1)) + 2
            scores[word] = value
            chars.append(Array(word))
            scoreValues.append(value)
            let points = word.unicodeScalars.map(\.value)
            codepoints.append(points)
            if let first = points.first {
                indicesByFirst[first, default: []].append(rank)
            }
        }

        return WordList(words: words,
                        chars: chars,
                        scores: scores,
                        scoreValues: scoreValues,
                        codepoints: codepoints,
                        indicesByFirst: indicesByFirst)
    }

    public static func normalize(_ word: String) -> String {
        var result = ""
        result.reserveCapacity(word.count)
        for scalar in word.lowercased() {
            result.append(scalar == "ё" ? "е" : scalar)
        }
        return result
    }
}
