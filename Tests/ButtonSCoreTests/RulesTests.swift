import XCTest
@testable import ButtonSCore

final class RulesTests: XCTestCase {
    func testFixStuckShift() {
        XCTAssertEqual(Rules.fixStuckShift("ППривет"), "Привет")
        XCTAssertNil(Rules.fixStuckShift("ПРИВЕТ"))
        XCTAssertNil(Rules.fixStuckShift("iPhone"))
    }

    func testAbbreviations() {
        XCTAssertTrue(Rules.isAbbreviation("т"))
        XCTAssertTrue(Rules.isAbbreviation("др"))
        XCTAssertTrue(Rules.isAbbreviation("см"))
        XCTAssertFalse(Rules.isAbbreviation("привет"))
    }

    func testListContinuation() {
        XCTAssertEqual(Rules.listContinuation("1. Первый"), "2. ")
        XCTAssertEqual(Rules.listContinuation("a) пункт"), "b) ")
        XCTAssertEqual(Rules.listContinuation("- пункт"), "- ")
        XCTAssertEqual(Rules.listContinuation("  - вложенный"), "  - ")
        XCTAssertNil(Rules.listContinuation("просто текст"))
        XCTAssertNil(Rules.listContinuation("1. "))
    }
}

final class ContextTests: XCTestCase {
    func testProtectedContext() {
        XCTAssertTrue(Context.isProtectedContext(previous: ".", separator: " ", word: "ру"))
        XCTAssertTrue(Context.isProtectedContext(previous: " ", separator: "@", word: "user"))
        XCTAssertTrue(Context.isProtectedContext(previous: "/", separator: " ", word: "path"))
        XCTAssertFalse(Context.isProtectedContext(previous: " ", separator: " ", word: "привет"))
    }

    func testMixedScriptAndDigitsProtected() {
        XCTAssertTrue(Context.isProtectedContext(previous: " ", separator: " ", word: "приветhello"))
        XCTAssertTrue(Context.isProtectedContext(previous: " ", separator: " ", word: "user123"))
    }

    func testProperNounsAndInnerCase() {
        XCTAssertTrue(Context.looksLikeProperNoun("Михаил"))
        XCTAssertFalse(Context.looksLikeProperNoun("михаил"))
        XCTAssertTrue(Context.hasInnerUppercase("iPhone"))
        XCTAssertTrue(Context.hasInnerUppercase("МакДональдс"))
        XCTAssertFalse(Context.hasInnerUppercase("Привет"))
    }

    func testSentenceCapitalization() {
        let tracker = SentenceTracker()
        tracker.onBoundary("Привет", separator: ".", afterColon: true)
        tracker.onBoundary("", separator: " ", afterColon: true)
        XCTAssertTrue(tracker.onChar("к"))
    }

    func testDomainNotCapitalized() {
        let tracker = SentenceTracker()
        tracker.onBoundary("яндекс", separator: ".", afterColon: true)
        XCTAssertFalse(tracker.onChar("р"))
    }
}

final class TypoTests: XCTestCase {
    func testFixesRussianTypo() {
        let s = TypoEngine.suggest("превет", language: "ru", maxDistance: 1)
        XCTAssertEqual(s?.text, "привет")
    }

    func testFixesTranspositionEnglish() {
        let s = TypoEngine.suggest("teh", language: "en", maxDistance: 1)
        XCTAssertEqual(s?.text, "the")
    }

    func testLeavesCorrectWords() {
        XCTAssertNil(TypoEngine.suggest("привет", language: "ru", maxDistance: 1))
        XCTAssertNil(TypoEngine.suggest("hello", language: "en", maxDistance: 1))
    }

    func testDoesNotTouchSymbolsOrInnerCase() {
        XCTAssertNil(TypoEngine.suggest("a1b2", language: "en", maxDistance: 1))
        XCTAssertNil(TypoEngine.suggest("iPhone", language: "en", maxDistance: 1))
    }

    func testConfidenceGate() {
        XCTAssertTrue(TypoEngine.isConfident(distance: 1, confidence: 0.7))
        XCTAssertFalse(TypoEngine.isConfident(distance: 1, confidence: 0.69))
        XCTAssertFalse(TypoEngine.isConfident(distance: 2, confidence: 0.99))
    }

    func testKeyboardPenalty() {
        XCTAssertTrue(TypoEngine.keysAdjacent("s", "d"))
        XCTAssertTrue(TypoEngine.keysAdjacent("ф", "ы"))
        XCTAssertFalse(TypoEngine.keysAdjacent("s", "o"))
    }
}
