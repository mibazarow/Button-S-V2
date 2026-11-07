import XCTest
@testable import ButtonSCore

final class LayoutTests: XCTestCase {
    func testConvertWord() {
        XCTAssertEqual(convertWord("ghbdtn", target: "ru"), "привет")
        XCTAssertEqual(convertWord("Ghbdtn", target: "ru"), "Привет")
        XCTAssertEqual(convertWord("GHBDTN", target: "ru"), "ПРИВЕТ")
        XCTAssertEqual(convertWord("привет", target: "en"), "ghbdtn")
    }

    func testDecideReplacesUnknownEnglish() {
        let d = LayoutEngine.decide("ghbdtn")
        XCTAssertEqual(d?.text, "привет")
        XCTAssertGreaterThan(d?.confidence ?? 0, 0.5)
    }

    func testDecideCapitalized() {
        XCTAssertEqual(LayoutEngine.decide("Ghbdtn")?.text, "Привет")
    }

    func testKeepsValidWords() {
        XCTAssertNil(LayoutEngine.decide("привет"))
        XCTAssertNil(LayoutEngine.decide("hello"))
    }

    func testKeepsShortWords() {
        XCTAssertNil(LayoutEngine.decide("ру"))
        XCTAssertNil(LayoutEngine.decide("gh"))
    }

    func testSkipsProtectedWords() {
        XCTAssertNil(LayoutEngine.decide("ghbdtn@"))
        XCTAssertNil(LayoutEngine.decide("http://ghbdtn"))
    }

    func testConvertText() {
        XCTAssertEqual(LayoutEngine.convertText("ghbdtn, vbh!"), "привет, мир!")
    }

    func testForceConvert() {
        XCTAssertEqual(LayoutEngine.forceConvert("ghbdtn")?.text, "привет")
    }
}
