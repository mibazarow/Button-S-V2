import Foundation

/// Контекстные проверки: защищённые слова, имена, регистр.
///
/// Порт `engine/context.rs`: решаем, можно ли трогать слово, опираясь на
/// соседние символы. Домены, пути, e-mail и смешанные алфавиты не трогаем.
public enum Context {
    public static func isProtectedContext(previous: Character?, separator: Character, word: String) -> Bool {
        if word.isEmpty { return false }

        if let previous, ".@/\\-_~".contains(previous) { return true }
        if "@\\_".contains(separator) || separator == "/" { return true }

        let cyrillic = word.contains(where: isCyrillic)
        let latin = word.contains { $0.isASCII && $0.isLetter }
        let digit = word.contains { $0.isASCII && $0.isNumber }

        return (cyrillic && latin) || digit
    }

    public static func looksLikeProperNoun(_ word: String) -> Bool {
        let chars = Array(word)
        guard let first = chars.first, first.isUppercase else { return false }
        if chars.allSatisfy({ $0.isUppercase }) { return false }
        return chars.count >= 2 && chars.allSatisfy { $0.isLetter }
    }

    public static func hasInnerUppercase(_ word: String) -> Bool {
        let chars = Array(word)
        guard let first = chars.first else { return false }
        if first.isUppercase && chars.allSatisfy({ $0.isUppercase }) { return false }
        return chars.dropFirst().contains { $0.isUppercase }
    }
}

/// Автоматическая капитализация после точки.
public final class SentenceTracker {
    private var start = false
    private var pending: Character?
    private var lastWord = ""

    public init() {}

    public func onBoundary(_ word: String, separator: Character, afterColon: Bool) {
        if !word.isEmpty { lastWord = word }

        switch separator {
        case ".", "!", "?", "…":
            pending = separator
            start = false
        case ":":
            pending = ":"
            start = false
        case "\n":
            pending = nil
            start = true
        case " ":
            if let pending {
                let subject = word.isEmpty ? lastWord : word
                switch pending {
                case ".", "!", "?", "…":
                    start = !Rules.isAbbreviation(subject)
                case ":":
                    start = afterColon
                default:
                    start = false
                }
                self.pending = nil
            }
        case "\"", "'", "»", ")", "]":
            break
        default:
            pending = nil
            start = false
        }
    }

    /// Вернуть `true`, если символ надо сделать заглавным.
    public func onChar(_ ch: Character) -> Bool {
        if ch.isWhitespace { return false }
        if pending != nil {
            if ch.isLetter || ch.isNumber {
                pending = nil
                start = false
            }
            return false
        }
        let capitalize = start && ch.isLowercase && ch.isLetter
        start = false
        return capitalize
    }

    public func onBackspace() {
        start = false
        pending = nil
    }

    public func reset() {
        start = false
        pending = nil
        lastWord = ""
    }
}
