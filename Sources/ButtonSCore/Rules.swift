import Foundation

/// Правила, не требующие словаря: залипший Shift, сокращения, списки.
///
/// Порт `engine/rules.rs`.
public enum Rules {
    /// `ППривет` → `Привет`. Двойная заглавная на стыке — залипший Shift.
    public static func fixStuckShift(_ word: String) -> String? {
        guard word.allSatisfy({ $0.isLetter }) else { return nil }
        let chars = Array(word)
        if chars.count < 2 { return nil }
        if chars.allSatisfy({ $0.isUppercase }) { return nil }

        for index in 1..<chars.count {
            guard chars[index].isUppercase, chars[index - 1].isUppercase else { continue }
            let duplicate = Character(String(chars[index]).lowercased())
                == Character(String(chars[index - 1]).lowercased())

            var fixed = ""
            for (position, ch) in chars.enumerated() {
                if position == index {
                    if duplicate { continue }
                    fixed.append(contentsOf: String(ch).lowercased())
                } else {
                    fixed.append(ch)
                }
            }
            return fixed
        }
        return nil
    }

    /// Сокращение после точки не завершает предложение.
    public static func isAbbreviation(_ word: String) -> Bool {
        let lower = word.lowercased()
        let list: Set<String> = [
            "т", "е", "др", "г", "гг", "ул", "им", "рис", "стр", "см", "напр",
            "etc", "e.g", "i.e", "mr", "mrs", "dr", "vs",
        ]
        if list.contains(lower) { return true }
        let chars = Array(word)
        return chars.count <= 2 && chars.allSatisfy { $0.isUppercase }
    }

    /// Продолжение списка: `1. Первый` → `2. `, `- пункт` → `- `.
    public static func listContinuation(_ previousLine: String) -> String? {
        let trimmedLeading = previousLine.drop(while: { $0 == " " || $0 == "\t" })
        let indent = String(previousLine.prefix(previousLine.count - trimmedLeading.count))
        let trimmed = trimmedLeading.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        guard let first = trimmed.first else { return nil }

        if "-*•+—".contains(first) {
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return nil }
            return "\(indent)\(first) "
        }

        guard let spaceIndex = trimmed.firstIndex(of: " ") else { return nil }
        let marker = String(trimmed[trimmed.startIndex..<spaceIndex])
        let rest = String(trimmed[spaceIndex...]).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return nil }

        guard let delimiter = marker.last, delimiter == "." || delimiter == ")" else { return nil }
        let body = String(marker.dropLast())

        if let number = UInt32(body) {
            return "\(indent)\(number + 1)\(delimiter) "
        }

        let bodyChars = Array(body)
        guard bodyChars.count == 1, bodyChars[0].isLetter else { return nil }
        guard let scalar = bodyChars[0].unicodeScalars.first,
              let next = Unicode.Scalar(scalar.value + 1),
              Character(next).isLetter else { return nil }

        return "\(indent)\(Character(next))\(delimiter) "
    }
}
