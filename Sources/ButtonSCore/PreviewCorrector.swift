import Foundation

/// Прогон текста через те же правила, что работают при наборе, но за один
/// проход и с отчётом «что сработало». Нужен вкладке «Проверка» в настройках.
///
/// Отличается от `CorrectionEngine` намеренно: там правки применяются к уже
/// набранному тексту по одному слову на границе, здесь — пересчёт строки
/// целиком, чтобы показать результат до того, как пользователь начал печатать.
public enum PreviewCorrector {
    public struct Result: Sendable {
        public let text: String
        public let details: [String]
    }

    public static func run(
        _ input: String,
        layoutEnabled: Bool,
        typosEnabled: Bool,
        typoMode: String,
        typoMaxDistance: Int,
        dictionary: Dictionary = .shared
    ) -> Result {
        var details: [String] = []
        let words = input.split(separator: " ", omittingEmptySubsequences: false).map(String.init)

        let converted = words.map { word -> String in
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            let suffix = String(word.dropFirst(trimmed.count))
            guard !trimmed.isEmpty else { return word }

            if layoutEnabled,
               let decision = LayoutEngine.decide(trimmed, dictionary: dictionary) {
                details.append("раскладка   \(trimmed) → \(decision.text)")
                return decision.text + suffix
            }
            if typosEnabled, typoMode != "off",
               let language = languageOf(trimmed),
               let suggestion = TypoEngine.suggest(trimmed,
                                                   language: language,
                                                   maxDistance: typoMaxDistance,
                                                   dictionary: dictionary) {
                let confidence = String(format: "%.2f", suggestion.confidence)
                details.append("опечатка    \(trimmed) → \(suggestion.text)  (уверенность \(confidence))")
                return suggestion.text + suffix
            }
            return word
        }

        return Result(text: converted.joined(separator: " "), details: details)
    }
}
