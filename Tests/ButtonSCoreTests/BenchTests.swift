import XCTest
@testable import ButtonSCore

/// Замеры горячего пути. Не проверяет корректность — печатает тайминги,
/// чтобы оптимизации опирались на числа, а не на ощущения.
final class BenchTests: XCTestCase {
    private func time(_ label: String, iterations: Int, _ body: () -> Void) {
        // прогрев
        for _ in 0..<3 { body() }
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { body() }
        let end = DispatchTime.now().uptimeNanoseconds
        let perCall = Double(end - start) / Double(iterations) / 1_000_000
        print(String(format: "BENCH %@: %.3f ms/вызов (%d итераций)", label, perCall, iterations))
    }

    func testBenchTypoSuggest() {
        let dict = Dictionary.shared
        // слово с опечаткой, которого нет в словаре
        time("TypoEngine.suggest привет", iterations: 20) {
            _ = TypoEngine.suggest("превет", language: "ru", maxDistance: 2, dictionary: dict)
        }
    }

    func testBenchTypoSuggestMany() {
        let dict = Dictionary.shared
        let words = ["превет", "какждай", "программированние", "серверов", "андройд", "компютер"]
        let start = DispatchTime.now().uptimeNanoseconds
        for w in words {
            _ = TypoEngine.suggest(w, language: "ru", maxDistance: 2, dictionary: dict)
        }
        let end = DispatchTime.now().uptimeNanoseconds
        print(String(format: "BENCH %d слов: %.2f ms всего, %.2f ms/слово",
                     words.count,
                     Double(end - start) / 1_000_000,
                     Double(end - start) / Double(words.count) / 1_000_000))
    }

    func testBenchDictionaryLoad() {
        let start = DispatchTime.now().uptimeNanoseconds
        _ = Dictionary.shared
        let end = DispatchTime.now().uptimeNanoseconds
        print(String(format: "BENCH загрузка словаря: %.1f ms", Double(end - start) / 1_000_000))
    }

    func testBenchLayoutDecide() {
        let dict = Dictionary.shared
        let s = LayoutSettings.default
        time("LayoutEngine.decide ghbdtn", iterations: 20) {
            _ = LayoutEngine.decide("ghbdtn", settings: s, dictionary: dict)
        }
    }
}