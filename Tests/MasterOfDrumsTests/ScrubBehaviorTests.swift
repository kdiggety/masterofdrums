import XCTest
@testable import MasterOfDrums

@MainActor
final class ScrubBehaviorTests: XCTestCase {
    let duration = 120.0
    let multiplier = 4.0

    // MARK: - Direction Tests

    func testDragUpScrubbsForward() {
        let startTime = 30.0
        let translationHeight = -100.0
        let availableHeight = 500.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertGreaterThan(result, startTime, "Dragging up (negative translation) should move forward in time")
    }

    func testDragDownScrubbsBackward() {
        let startTime = 30.0
        let translationHeight = 100.0
        let availableHeight = 500.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertLessThan(result, startTime, "Dragging down (positive translation) should move backward in time")
    }

    func testNoDragNoChange() {
        let startTime = 30.0
        let translationHeight = 0.0
        let availableHeight = 500.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertEqual(result, startTime, accuracy: 0.001, "No drag should not change time")
    }

    // MARK: - Clamping Tests

    func testScrubClampedAtZero() {
        let startTime = 5.0
        let translationHeight = 100.0
        let availableHeight = 100.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertGreaterThanOrEqual(result, 0, "Result should never be negative")
        XCTAssertEqual(result, 0, accuracy: 0.001, "Large drag down from start should clamp at 0")
    }

    func testScrubClampedAtDuration() {
        let startTime = 115.0
        let translationHeight = -100.0
        let availableHeight = 100.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertLessThanOrEqual(result, duration, "Result should never exceed duration")
        XCTAssertEqual(result, duration, accuracy: 0.001, "Large drag up from end should clamp at duration")
    }

    // MARK: - Scale Tests

    func testLargerAvailableHeightReducesSensitivity() {
        let startTime = 60.0
        let translationHeight = 10.0

        let resultSmallHeight = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: 100.0,
            totalDuration: duration,
            multiplier: multiplier
        )

        let resultLargeHeight = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: 200.0,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertGreaterThan(
            abs(resultSmallHeight - startTime),
            abs(resultLargeHeight - startTime),
            "Larger available height should reduce sensitivity (smaller magnitude delta for same translation)"
        )
    }

    func testMultiplierScalesDelta() {
        let startTime = 60.0
        let translationHeight = 100.0
        let availableHeight = 500.0

        let resultLowMultiplier = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: 2.0
        )

        let resultHighMultiplier = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: 4.0
        )

        XCTAssertGreaterThan(
            abs(resultHighMultiplier - startTime),
            abs(resultLowMultiplier - startTime),
            "Higher multiplier should increase magnitude of delta"
        )
    }

    // MARK: - Edge Cases

    func testZeroHeightDoesNotCrash() {
        let startTime = 30.0
        let translationHeight = 100.0
        let availableHeight = 0.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: multiplier
        )

        XCTAssertEqual(result, startTime, accuracy: 0.001, "Zero height should be treated as height of 1 (no movement)")
    }

    func testZeroDurationNeverCrashes() {
        let startTime = 0.0
        let translationHeight = 100.0
        let availableHeight = 500.0

        let result = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: 0,
            multiplier: multiplier
        )

        XCTAssertEqual(result, 0, accuracy: 0.001, "Zero duration should result in zero target time")
    }

    // MARK: - Default Multiplier

    func testDefaultMultiplierUsed() {
        let startTime = 60.0
        let translationHeight = 100.0
        let availableHeight = 500.0

        let resultDefault = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration
        )

        let resultExplicit = PrototypeGameController.computeScrubTime(
            from: startTime,
            translationHeight: translationHeight,
            availableHeight: availableHeight,
            totalDuration: duration,
            multiplier: 4.0
        )

        XCTAssertEqual(
            resultDefault,
            resultExplicit,
            accuracy: 0.001,
            "Default multiplier (4.0) should match explicit multiplier"
        )
    }
}
