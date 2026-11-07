import XCTest
@testable import ButtonSCore

final class DictionaryTests: XCTestCase {
    func testFrequencyListsLoad() {
        let dict = Dictionary.shared
        XCTAssertGreaterThan(dict.ru.words.count, 10_000, "ru_30k не загрузился")
        XCTAssertGreaterThan(dict.en.words.count, 10_000, "en_30k не загрузился")
    }

    func testFSTExpands() {
        let dict = Dictionary.shared
        XCTAssertTrue(dict.known("ru", "привет"), "привет должно быть в морфологии")
        XCTAssertTrue(dict.known("ru", "привета"), "падежная форма должна быть в морфологии")
        XCTAssertTrue(dict.known("ru", "здравствуйте"))
        XCTAssertFalse(dict.known("ru", "привт"), "опечатки не должно быть")
    }

    func testScoresOrdered() {
        let dict = Dictionary.shared
        let common = dict.score("ru", "не")
        let rare = dict.score("ru", "контрабандист")
        XCTAssertGreaterThan(common, rare, "частые слова должны весить больше")
    }

    func testNormalize() {
        XCTAssertEqual(Dictionary.normalize("Ёлка"), "елка")
        XCTAssertEqual(Dictionary.normalize("ПРИВЕТ"), "привет")
    }
}
