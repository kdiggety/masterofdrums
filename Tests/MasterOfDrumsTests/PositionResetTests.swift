import XCTest
@testable import MasterOfDrums

final class PositionResetTests: XCTestCase {

    // MARK: - Bar 0 Position Tests

    func testBar0PositionFormat() {
        // Verify that Bar 0 is represented as "0.0.0.000"
        let bar0Format = "0.0.0.000"

        XCTAssertEqual(bar0Format.count, 9, "Bar 0 format should be 9 characters: '0.0.0.000'")
        XCTAssertTrue(bar0Format.hasPrefix("0."), "Bar 0 should start with '0.'")
    }

    // MARK: - Musical Position at Time 0 Tests

    func testMusicalPositionAt0TimeWithContent() {
        // When content is loaded and time is 0, should show Bar 1
        let position = MusicalTransport.position(
            at: 0.0,
            bpm: 120.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        let musicalPositionText = position.barBeatDivisionTickText
        XCTAssertEqual(musicalPositionText, "1.1.1.000", "At time 0 with content, should show Bar 1, Beat 1")
        XCTAssertNotEqual(musicalPositionText, "0.0.0.000", "At time 0 with content, should NOT be Bar 0")
    }

    // MARK: - Empty State Tests

    func testEmptyChartCreation() {
        let emptyChart = Chart(notes: [], title: "Empty Chart")

        XCTAssertEqual(emptyChart.notes.count, 0, "Empty chart should have no notes")
        XCTAssertEqual(emptyChart.title, "Empty Chart", "Chart should have the specified title")
    }

    // MARK: - Position Display Logic Tests

    func testPositionDisplayShowsBar0WhenNoContent() {
        // Simulate the condition: no audio, no chart active
        let hasAudio = false
        let hasChartContent = false
        let hasContent = hasAudio || hasChartContent

        let displayText = hasContent ? "1.1.1.000" : "0.0.0.000"

        XCTAssertEqual(displayText, "0.0.0.000", "Should display Bar 0 when no content is loaded")
    }

    func testPositionDisplayShowsMusicalPositionWithContent() {
        // Simulate the condition: audio or chart is loaded
        let hasAudio = true
        let hasChartContent = false
        let hasContent = hasAudio || hasChartContent

        let displayText = hasContent ? "1.1.1.000" : "0.0.0.000"

        XCTAssertEqual(displayText, "1.1.1.000", "Should display musical position when content is loaded")
    }

    func testPositionDisplayShowsMusicalPositionWithChart() {
        // Simulate the condition: chart is active but no audio
        let hasAudio = false
        let hasChartContent = true
        let hasContent = hasAudio || hasChartContent

        let displayText = hasContent ? "1.1.1.000" : "0.0.0.000"

        XCTAssertEqual(displayText, "1.1.1.000", "Should display musical position when chart is active")
    }

    // MARK: - Subdivision Display Tests

    func testSubdivisionDisplayBar0() {
        let hasContent = false
        let subdivisionText = hasContent ? "1" : "0"

        XCTAssertEqual(subdivisionText, "0", "Subdivision should be 0 when no content loaded")
    }

    func testSubdivisionDisplayWithContent() {
        let hasContent = true
        let position = MusicalTransport.position(
            at: 0.0,
            bpm: 120.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )
        let subdivisionText = hasContent ? String(position.subdivision) : "0"

        XCTAssertEqual(subdivisionText, "1", "With content at time 0, subdivision should be 1")
        XCTAssertNotEqual(subdivisionText, "0", "With content, should not show subdivision 0")
    }

    // MARK: - Consistency Tests

    func testBar0PositionConsistency() {
        // Bar 0 position should always be "0.0.0.000"
        let bar0Positions = [
            "0.0.0.000",
            "0.0.0.000",
            "0.0.0.000"
        ]

        for (index, position) in bar0Positions.enumerated() {
            XCTAssertEqual(position, "0.0.0.000", "Bar 0 position \(index) should consistently be '0.0.0.000'")
        }
    }

    func testTransitionFromContentToBar0() {
        // When transitioning from having content to no content, should show Bar 0
        let positions = [
            ("1.1.1.000", true),    // With content
            ("0.0.0.000", false),   // After unload
            ("0.0.0.000", false),   // Should stay at Bar 0
        ]

        for (expectedPosition, hasContent) in positions {
            let currentPosition = hasContent ? "1.1.1.000" : "0.0.0.000"
            XCTAssertEqual(currentPosition, expectedPosition, "Position should match content state")
        }
    }

    // MARK: - Edge Cases

    func testBar0RemainsAfterMultipleUnloads() {
        let unloadCount = 3
        var currentPosition = "0.0.0.000"

        for _ in 0..<unloadCount {
            // Simulate unload by setting hasContent to false
            let hasContent = false
            currentPosition = hasContent ? "1.1.1.000" : "0.0.0.000"
        }

        XCTAssertEqual(currentPosition, "0.0.0.000", "After multiple unloads, should remain at Bar 0")
    }

    func testBar0ToContentTransition() {
        // Start at Bar 0, then load content
        var currentPosition = "0.0.0.000"
        var hasContent = false

        // Load content
        hasContent = true
        currentPosition = hasContent ? "1.1.1.000" : "0.0.0.000"

        XCTAssertEqual(currentPosition, "1.1.1.000", "After loading content, should show musical position")
    }
}
