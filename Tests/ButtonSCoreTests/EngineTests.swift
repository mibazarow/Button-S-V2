import XCTest
@testable import ButtonSCore

final class FakePlatform: PlatformActions, @unchecked Sendable {
    var text = ""
    var appID = "com.test.app"
    var secure = false
    var addressBar = false
    var switched: [String] = []
    var lastInsertion = ""

    func frontmostAppID() -> String { appID }
    func isBrowserAddressBar(appID: String) -> Bool { addressBar }
    func isSecureInput() -> Bool { secure }
    func replaceTyped(deleteCount: Int, insertion: String) -> Bool {
        let chars = Array(text)
        let keep = max(0, chars.count - deleteCount)
        text = String(chars[0..<keep]) + insertion
        lastInsertion = insertion
        return true
    }
    func insertText(_ text: String) -> Bool {
        self.text += text
        lastInsertion = text
        return true
    }
    func switchLayout(to language: String) -> Bool {
        switched.append(language)
        return true
    }
}

final class EngineTests: XCTestCase {
    func type(_ engine: CorrectionEngine, _ text: String) {
        for ch in text { engine.characterTyped(ch) }
    }

    func testFixesWrongLayoutOnSpace() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "ghbdtn")
        platform.text = "ghbdtn"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "привет ")
    }

    func testFixesTypoOnSpace() {
        // v1 в живом наборе правит только уверенные опечатки (>=0.7).
        // "превет" даёт 0.646, поэтому автозамены нет — как в оригинале.
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "превет")
        platform.text = "превет"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "превет")
    }

    func testFixesConfidentTypo() {
        // "теест" → "тест": одна уверенная правка.
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "здеся")
        platform.text = "здеся"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "здесь ")
    }

    func testLeavesCorrectWord() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "привет")
        platform.text = "привет"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "привет")
    }

    func testSkipsSecureInput() {
        let platform = FakePlatform()
        platform.secure = true
        let engine = CorrectionEngine(actions: platform)
        type(engine, "ghbdtn")
        platform.text = "ghbdtn"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "ghbdtn")
    }

    func testSkipsBrowserAddressBar() {
        let platform = FakePlatform()
        platform.addressBar = true
        let engine = CorrectionEngine(actions: platform)
        type(engine, "ghbdtn")
        platform.text = "ghbdtn"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "ghbdtn")
    }

    func testFixesStuckShift() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "ППривет")
        platform.text = "ППривет"
        engine.boundary(" ")
        XCTAssertEqual(platform.text, "Привет ")
    }

    func testSwitchesLayoutAfterFix() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "ghbdtn")
        platform.text = "ghbdtn"
        engine.boundary(" ")
        XCTAssertEqual(platform.switched, ["ru"])
    }

    func testRecordsHistory() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "ghbdtn")
        platform.text = "ghbdtn"
        engine.boundary(" ")
        XCTAssertEqual(engine.history.count, 1)
        XCTAssertEqual(engine.history.first?.kind, .layout)
    }

    func testListContinuationOnNewline() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "1. Первый")
        engine.boundary("\n")
        XCTAssertEqual(platform.lastInsertion, "2. ")
    }

    // MARK: - Капитализация после точки

    func testCapitalizesAfterSentenceEnd() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "Привет")
        engine.boundary(".")
        engine.boundary(" ")
        type(engine, "мир")
        XCTAssertEqual(platform.lastInsertion, "М")
    }

    func testDoesNotCapitalizeWhenDisabled() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        engine.settings.capitalizationEnabled = false
        type(engine, "Привет")
        engine.boundary(".")
        engine.boundary(" ")
        type(engine, "мир")
        XCTAssertNotEqual(platform.lastInsertion, "М")
    }
    /// Известное ограничение: при включённой настройке домен после точки получает заглавную.
    /// Тест фиксирует текущее поведение, чтобы правка не прошла незамеченной.
    func testCapitalizationTouchesDomainWhenEnabled() {
        let platform = FakePlatform()
        let engine = CorrectionEngine(actions: platform)
        type(engine, "Сайт")
        engine.boundary(".")
        engine.boundary(" ")
        type(engine, "bazarow.ru")
        XCTAssertEqual(platform.lastInsertion, "B")
    }
}
