import XCTest
@testable import ButtonSCore

final class LevelMeterTests: XCTestCase {
    /// Тишина должна давать ноль, а не «полную шкалу», как было с пиком ×4.
    func testSilenceIsZero() {
        XCTAssertEqual(LevelMeter.normalize(rms: 0), 0)
        XCTAssertEqual(LevelMeter.normalize(rms: 0.0001), 0)
    }

    /// Громкая речь не упирается в 100% — должен быть запас.
    func testNormalSpeechDoesNotMaxOut() {
        let level = LevelMeter.normalize(rms: 0.05)
        XCTAssertGreaterThan(level, 0.5)
        XCTAssertLessThan(level, 0.85)
    }

    /// Крик доходит почти до верха, но не выше единицы.
    func testLoudClipStaysInRange() {
        XCTAssertEqual(LevelMeter.normalize(rms: 0.9), 1, accuracy: 0.001)
    }

    /// Тихая речь должна быть заметно ниже обычной — иначе индикатор бесполезен.
    func testQuietIsLowerThanNormal() {
        let quiet = LevelMeter.normalize(rms: 0.01)
        let normal = LevelMeter.normalize(rms: 0.05)
        XCTAssertLessThan(quiet, normal)
        XCTAssertGreaterThan(quiet, 0.1)
    }

    /// RMS синусоиды амплитуды A равен A/√2.
    func testRMSOfSine() {
        let period = 100
        let samples = (0..<period).map { Float(sin(2 * Double.pi * Double($0) / Double(period))) }
        XCTAssertEqual(LevelMeter.rms(samples), Float(1.0 / sqrt(2.0)), accuracy: 0.01)
    }

    func testRMSOfSilenceIsZero() {
        XCTAssertEqual(LevelMeter.rms([Float](repeating: 0, count: 100)), 0)
        XCTAssertEqual(LevelMeter.rms([]), 0)
    }

    /// Сглаживание: вверх идёт быстрее, чем вниз.
    func testSmoothingIsAsymmetric() {
        let rising = LevelMeter.smooth(previous: 0, target: 1)
        let falling = LevelMeter.smooth(previous: 1, target: 0)
        XCTAssertGreaterThan(rising, 1 - falling)
        XCTAssertGreaterThan(rising, 0.5)
        XCTAssertLessThan(falling, 1)
    }

    /// Ширина полосы: минимум виден, максимум не выходит за 100%.
    func testFillPercentBounds() {
        XCTAssertEqual(LevelMeter.fillPercent(level: 0), 4)
        XCTAssertEqual(LevelMeter.fillPercent(level: 1), 100)
        XCTAssertEqual(LevelMeter.fillPercent(level: 0.5), 50)
        XCTAssertEqual(LevelMeter.fillPercent(level: 2), 100)
    }

    /// Децибелы считаются от RMS: 0.1 → -20 дБ.
    func testDecibels() {
        XCTAssertEqual(LevelMeter.decibels(rms: 0.1), -20, accuracy: 0.01)
        XCTAssertEqual(LevelMeter.decibels(rms: 1.0), 0, accuracy: 0.01)
    }
}