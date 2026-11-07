import Foundation

/// Исправление опечаток без ИИ.
///
/// Порт `engine/typo.rs`: расстояние Дамерау (вставка/удаление/замена/
/// транспозиция) с полосой отсечения по `max_distance`, штраф за «далёкие»
/// клавиши и частотный вес слова из списка.
public struct TypoSuggestion: Sendable, Equatable {
    public let text: String
    public let distance: Int
    public let confidence: Float

    public init(text: String, distance: Int, confidence: Float) {
        self.text = text
        self.distance = distance
        self.confidence = confidence
    }
}

public enum TypoEngine {
    public static func suggest(_ word: String,
                               language: String,
                               maxDistance: Int,
                               dictionary: Dictionary = .shared) -> TypoSuggestion? {
        let chars = Array(word)
        if chars.count < 3 { return nil }
        if !chars.allSatisfy({ $0.isLetter }) { return nil }
        if chars.filter({ $0.isUppercase }).count == chars.count { return nil }
        if Context.hasInnerUppercase(word) { return nil }
        if dictionary.known(language, word) { return nil }

        guard let list = dictionary.list(language) else { return nil }
        let source = Array(Dictionary.normalize(word))
        var best: (word: String, distance: Int, penalty: Float, score: Float)?
        var matrix = DamerauMatrix(width: source.count)

        for (index, candidate) in list.words.enumerated() {
            let candidateChars = list.chars[index]
            if abs(candidateChars.count - source.count) > maxDistance { continue }
            if candidateChars.first != source.first { continue }
            guard let distance = matrix.distance(source, candidateChars, maxDistance) else { continue }
            let score = list.scores[candidate] ?? 0
            if score < 3.0 { continue }
            let penalty = keyboardPenalty(source, candidateChars)

            let better: Bool
            if let current = best {
                better = distance < current.distance
                    || (distance == current.distance
                        && (penalty < current.penalty
                            || (penalty == current.penalty && score > current.score)))
            } else {
                better = true
            }
            if better {
                best = (candidate, distance, penalty, score)
            }
        }

        guard let match = best else { return nil }
        let confidence: Float
        if match.distance == 1 {
            confidence = min(max(match.score / 7.0, 0.6), 0.99)
        } else {
            confidence = min(max(match.score / 9.0, 0.5), 0.9)
        }

        return TypoSuggestion(text: restoreCase(original: word, replacement: match.word),
                              distance: match.distance,
                              confidence: confidence)
    }

    /// Автозамена только при одной правке и высокой уверенности.
    public static func isConfident(distance: Int, confidence: Float) -> Bool {
        distance == 1 && confidence >= 0.7
    }

    // MARK: - Регистр

    static func restoreCase(original: String, replacement: String) -> String {
        let chars = Array(original)
        let upper = chars.filter { $0.isUppercase }.count
        if upper == chars.count && !chars.isEmpty {
            return replacement.uppercased()
        }
        if let first = chars.first, first.isUppercase,
           !chars[1...].contains(where: { $0.isUppercase }) {
            var result = ""
            for (index, ch) in replacement.enumerated() {
                result.append(index == 0 ? Character(String(ch).uppercased()) : ch)
            }
            return result
        }
        return replacement
    }

    // MARK: - Клавиатура

    static let keyRows: [(String, String)] = [
        ("qwertyuiop", "йцукенгшщзхъ"),
        ("asdfghjkl", "фывапролджэ"),
        ("zxcvbnm", "ячсмитьбюё"),
    ]

    static func keyPosition(_ ch: Character) -> (row: Int, col: Int)? {
        let lower = Character(String(ch).lowercased())
        for (row, pair) in keyRows.enumerated() {
            if let col = pair.0.firstIndex(of: lower) {
                return (row, pair.0.distance(from: pair.0.startIndex, to: col))
            }
            if let col = pair.1.firstIndex(of: lower) {
                return (row, pair.1.distance(from: pair.1.startIndex, to: col))
            }
        }
        return nil
    }

    static func keysAdjacent(_ left: Character, _ right: Character) -> Bool {
        guard let a = keyPosition(left), let b = keyPosition(right) else { return false }
        if a.row == b.row { return abs(a.col - b.col) == 1 }
        return abs(a.row - b.row) == 1 && abs(a.col - b.col) <= 1
    }

    static func isSingleTransposition(_ source: [Character], _ target: [Character]) -> Bool {
        guard source.count == target.count else { return false }
        var mismatches: [Int] = []
        for index in source.indices where source[index] != target[index] {
            mismatches.append(index)
        }
        return mismatches.count == 2
            && mismatches[1] == mismatches[0] + 1
            && source[mismatches[0]] == target[mismatches[1]]
            && source[mismatches[1]] == target[mismatches[0]]
    }

    static func keyboardPenalty(_ source: [Character], _ target: [Character]) -> Float {
        guard source.count == target.count else { return 0 }
        if isSingleTransposition(source, target) { return 0 }
        var total: Float = 0
        for index in source.indices {
            let left = source[index]
            let right = target[index]
            if left == right { continue }
            total += keysAdjacent(left, right) ? 0.3 : 0.6
        }
        return total
    }
}

/// Расстояние Дамерау с полосой отсечения. Память под три строки, не под всю матрицу.
struct DamerauMatrix {
    private var prevPrev: [Int]
    private var prev: [Int]
    private var current: [Int]

    init(width: Int) {
        prevPrev = [Int](repeating: 0, count: width + 2)
        prev = [Int](repeating: 0, count: width + 2)
        current = [Int](repeating: 0, count: width + 2)
    }

    mutating func distance(_ source: [Character], _ target: [Character], _ max: Int) -> Int? {
        let n = source.count
        let m = target.count
        if abs(n - m) > max { return nil }

        for index in 0...m { prev[index] = index }
        for index in 0...m { prevPrev[index] = prev[index] }

        for i in 1...n {
            current[0] = i
            var rowMin = i

            for j in 1...m {
                let cost = source[i - 1] == target[j - 1] ? 0 : 1
                var value = min(prev[j] + 1, current[j - 1] + 1, prev[j - 1] + cost)

                if i > 1 && j > 1,
                   source[i - 1] == target[j - 2],
                   source[i - 2] == target[j - 1] {
                    value = min(value, prevPrev[j - 2] + 1)
                }

                current[j] = value
                rowMin = min(rowMin, value)
            }

            if rowMin > max { return nil }

            swap(&prevPrev, &prev)
            swap(&prev, &current)
        }

        return prev[m] <= max ? prev[m] : nil
    }
}
