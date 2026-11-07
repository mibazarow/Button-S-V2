import Foundation

/// Клавиатурные раскладки и перевод слова «не в той раскладке».
///
/// Порт `engine/layout.rs` из v1 один-в-один: те же таблицы, тот же порог
/// уверенности, то же требование знать слово в целевой раскладке.
public struct Keymap: Sendable {
    public static let enToRu: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г",
        "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о",
        "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": ".", "`": "ё",
    ]

    public static let ruToEn: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (en, ru) in enToRu { map[ru] = en }
        return map
    }()

    public static func map(_ language: String) -> [Character: Character] {
        language == "ru" ? enToRu : ruToEn
    }
}

/// Язык слова по алфавиту. `nil` — смешанный текст, цифры, пунктуация.
public func languageOf(_ text: String) -> String? {
    var cyrillic = false
    var latin = false
    var other = false

    for ch in text {
        if isCyrillic(ch) {
            cyrillic = true
        } else if ch.isASCII && ch.isLetter {
            latin = true
        } else if ch.isLetter {
            other = true
        } else {
            return nil
        }
    }

    if other || (cyrillic && latin) { return nil }
    if cyrillic { return "ru" }
    if latin { return "en" }
    return nil
}

public func isCyrillic(_ ch: Character) -> Bool {
    guard let value = ch.unicodeScalars.first?.value else { return false }
    return value >= 0x0400 && value <= 0x04FF
}

public struct LayoutDecision: Sendable, Equatable {
    public let text: String
    public let confidence: Float

    public init(text: String, confidence: Float) {
        self.text = text
        self.confidence = confidence
    }
}

public func convertWord(_ word: String, target: String) -> String {
    let table = Keymap.map(target)
    var result = ""
    result.reserveCapacity(word.count)

    for ch in word {
        let lower = Character(ch.lowercased())
        if let mapped = table[lower] {
            if ch.isUppercase {
                result.append(contentsOf: mapped.uppercased())
            } else {
                result.append(mapped)
            }
        } else {
            result.append(ch)
        }
    }
    return result
}

/// Регистр не выглядит сломанным: всё нижнее, всё верхнее или Capitalized.
private func caseIsSane(_ word: String) -> Bool {
    let chars = Array(word)
    guard !chars.isEmpty else { return true }
    let upper = chars.filter { $0.isUppercase }.count
    if upper == 0 || upper == chars.count { return true }
    return chars[0].isUppercase && !chars[1...].contains(where: { $0.isUppercase })
}

public struct LayoutSettings: Sendable {
    public var minWordLength: Int
    public var confidenceThreshold: Float
    public var pairs: [(String, String)]

    public init(minWordLength: Int = 3, confidenceThreshold: Float = 0.5,
                pairs: [(String, String)] = [("ru", "en")]) {
        self.minWordLength = minWordLength
        self.confidenceThreshold = confidenceThreshold
        self.pairs = pairs
    }

    public static let `default` = LayoutSettings()
}

public enum LayoutEngine {
    /// Решение о смене раскладки для одного слова.
    public static func decide(_ word: String,
                              settings: LayoutSettings = .default,
                              dictionary: Dictionary = .shared) -> LayoutDecision? {
        if word.count < settings.minWordLength { return nil }
        if !word.allSatisfy({ $0.isLetter }) { return nil }
        if !caseIsSane(word) { return nil }

        guard let source = languageOf(word) else { return nil }
        let target = source == "ru" ? "en" : "ru"

        let allowed = settings.pairs.contains { a, b in
            (a.lowercased() == source && b.lowercased() == target)
                || (b.lowercased() == source && a.lowercased() == target)
        }
        if !allowed { return nil }

        let converted = convertWord(word, target: target)
        if languageOf(converted) != target { return nil }

        if dictionary.known(source, word) { return nil }

        let targetScore = dictionary.score(target, converted)
        let knownFallback = target == "ru" && dictionary.known(target, converted)
        if targetScore < 3.0 && !knownFallback { return nil }

        let margin = 0.5 + settings.confidenceThreshold * 1.5
        let confidence: Float
        if targetScore >= margin {
            let base: Float = 1.0 / (1.0 + exp(-(targetScore - margin)))
            confidence = knownFallback ? max(base, 0.8) : base
        } else if knownFallback {
            confidence = 0.8
        } else {
            return nil
        }

        return LayoutDecision(text: converted, confidence: confidence)
    }

    /// Принудительный перевод, без словаря — для хоткея «сменить раскладку».
    public static func forceConvert(_ word: String) -> LayoutDecision? {
        guard let source = languageOf(word) else { return nil }
        let target = source == "ru" ? "en" : "ru"
        let converted = convertWord(word, target: target)
        if languageOf(converted) != target { return nil }
        return LayoutDecision(text: converted, confidence: 1.0)
    }

    /// Переводит весь текст, сохраняя пунктуацию. Для выделения.
    public static func convertText(_ text: String) -> String? {
        guard let first = text.first(where: { $0.isLetter }) else { return nil }
        let target: String
        if isCyrillic(first) {
            target = "en"
        } else if first.isASCII && first.isLetter {
            target = "ru"
        } else {
            return nil
        }

        let table = Keymap.map(target)
        var changed = false
        var result = ""
        result.reserveCapacity(text.count)

        for ch in text {
            guard ch.isLetter else {
                result.append(ch)
                continue
            }
            if let mapped = table[Character(ch.lowercased())] {
                changed = true
                if ch.isUppercase {
                    result.append(contentsOf: mapped.uppercased())
                } else {
                    result.append(mapped)
                }
            } else {
                result.append(ch)
            }
        }

        return changed ? result : nil
    }
}
