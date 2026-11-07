import XCTest
@testable import ButtonSCore

/// Проверяет ту же логику, что показывает вкладка «Проверка» в настройках.
final class PreviewLogicTests: XCTestCase {
    func testPreviewConvertsLayoutAndTypo() {
        let words = "ghbdtn, превет".split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let converted = words.map { word -> String in
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            let suffix = String(word.dropFirst(trimmed.count))
            guard !trimmed.isEmpty else { return word }
            if let d = LayoutEngine.decide(trimmed) { return d.text + suffix }
            if let lang = languageOf(trimmed),
               let s = TypoEngine.suggest(trimmed, language: lang, maxDistance: 1) {
                return s.text + suffix
            }
            return word
        }
        XCTAssertEqual(converted.joined(separator: " "), "привет, привет")
    }

    func testPreviewKeepsNormalWords() {
        let words = ["нормальный", "текст", "без", "ошибок"]
        for w in words {
            XCTAssertNil(LayoutEngine.decide(w), "\(w) не должно конвертироваться")
        }
    }
}
