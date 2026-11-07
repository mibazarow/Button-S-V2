import XCTest
@testable import ButtonSCore

/// Проверяет ту же логику, что показывает вкладка «Проверка» в настройках.
final class PreviewLogicTests: XCTestCase {
    private func run(_ input: String) -> PreviewCorrector.Result {
        PreviewCorrector.run(input,
                             layoutEnabled: true,
                             typosEnabled: true,
                             typoMode: "auto",
                             typoMaxDistance: 1)
    }

    func testPreviewConvertsLayoutAndTypo() {
        let result = run("ghbdtn, превет")
        XCTAssertEqual(result.text, "привет, привет")
        XCTAssertEqual(result.details.count, 2, "должны сработать и раскладка, и опечатка")
    }

    func testPreviewKeepsNormalWords() {
        let words = ["нормальный", "текст", "без", "ошибок"]
        for w in words {
            XCTAssertNil(LayoutEngine.decide(w), "\(w) не должно конвертироваться")
        }
    }

    func testPreviewRespectsDisabledLayout() {
        let result = PreviewCorrector.run("ghbdtn",
                                          layoutEnabled: false,
                                          typosEnabled: true,
                                          typoMode: "auto",
                                          typoMaxDistance: 1)
        XCTAssertEqual(result.text, "ghbdtn")
        XCTAssertTrue(result.details.isEmpty)
    }

    func testPreviewKeepsPunctuation() {
        XCTAssertEqual(run("ghbdtn,").text, "привет,")
    }
}
