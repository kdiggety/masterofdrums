import XCTest
@testable import MasterOfDrums

final class ChartMusicalTimingTests: XCTestCase {

    // MARK: - Chart Loading Tests

    func testChartLoadsWithBPM() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 1.0, label: "Snare"),
            NoteEvent(lane: .yellow, time: 2.0, label: "Hi-Hat"),
        ]
        let chart = Chart(notes: notes, title: "BPM Test")

        // Chart should exist and notes should load
        XCTAssertEqual(chart.notes.count, 2, "Chart should load with 2 notes")
        XCTAssertEqual(chart.title, "BPM Test", "Chart should preserve title")
    }

    // MARK: - Musical Position Calculation Tests

    func testMusicalPositionAtTimeZero() {
        let bpm = 120.0
        let position = MusicalTransport.position(
            at: 0.0,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(position.bar, 1, "Bar should be 1 at time 0")
        XCTAssertEqual(position.beat, 1, "Beat should be 1 at time 0")
        XCTAssertEqual(position.subdivision, 1, "Subdivision should be 1 at time 0")
        XCTAssertEqual(position.tick, 0, "Tick should be 0 at time 0")
    }

    func testMusicalPositionAfterOneBar() {
        let bpm = 120.0
        // 120 BPM = 2 beats per second = 0.5 seconds per beat
        // 4 beats per bar = 2 seconds per bar
        let positionAfterOneBar = MusicalTransport.position(
            at: 2.0,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(positionAfterOneBar.bar, 2, "After 2 seconds at 120 BPM, should be at Bar 2")
        XCTAssertEqual(positionAfterOneBar.beat, 1, "Should be at first beat of new bar")
    }

    func testMusicalPositionAfterOneBeat() {
        let bpm = 120.0
        // 120 BPM = 2 beats per second = 0.5 seconds per beat
        let positionAfterOneBeat = MusicalTransport.position(
            at: 0.5,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(positionAfterOneBeat.bar, 1, "Should still be in Bar 1")
        XCTAssertEqual(positionAfterOneBeat.beat, 2, "Should be at Beat 2")
        XCTAssertEqual(positionAfterOneBeat.subdivision, 1, "Should be at first subdivision")
    }

    func testMusicalPositionAfterHalfBeat() {
        let bpm = 120.0
        // Half a beat = 0.25 seconds at 120 BPM
        let positionAfterHalfBeat = MusicalTransport.position(
            at: 0.25,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(positionAfterHalfBeat.bar, 1, "Should still be in Bar 1")
        XCTAssertEqual(positionAfterHalfBeat.beat, 1, "Should still be in Beat 1")
        XCTAssertEqual(positionAfterHalfBeat.subdivision, 3, "With 4 subdivisions, 0.5 beats = subdivision 3")
    }

    func testMusicalPositionTextFormatting() {
        let position = MusicalTransport.position(
            at: 0.0,
            bpm: 120.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        let formattedText = position.barBeatDivisionTickText
        XCTAssertTrue(formattedText.contains("."), "Text should contain dots as separators")
        XCTAssertEqual(formattedText, "1.1.1.000", "At time 0, should format as '1.1.1.000'")
    }

    // MARK: - BPM Variation Tests

    func testMusicalPositionDifferentBPMs() {
        let time = 1.0

        let position60BPM = MusicalTransport.position(
            at: time,
            bpm: 60.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        let position120BPM = MusicalTransport.position(
            at: time,
            bpm: 120.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        // At 60 BPM, 1 second = 1 beat
        // At 120 BPM, 1 second = 2 beats
        XCTAssertLessThan(
            position60BPM.beat,
            position120BPM.beat,
            "Higher BPM should result in higher beat count for same time"
        )
    }

    // MARK: - Song Offset Tests

    func testMusicalPositionWithSongOffset() {
        let bpm = 120.0
        let songOffset = 1.0

        // With 1 second offset, time 1.0 should be treated as time 0.0
        let positionWithOffset = MusicalTransport.position(
            at: 1.0,
            bpm: bpm,
            songOffset: songOffset,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        let positionNoOffset = MusicalTransport.position(
            at: 0.0,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(positionWithOffset.bar, positionNoOffset.bar, "Song offset should shift musical position")
        XCTAssertEqual(positionWithOffset.beat, positionNoOffset.beat, "Beat should match when offset adjusted")
    }

    // MARK: - Subdivision Tests

    func testMusicalPositionSubdivisions() {
        let bpm = 120.0
        // At 0.125 seconds (quarter of a beat), with 4 subdivisions per beat
        let position = MusicalTransport.position(
            at: 0.125,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(position.subdivision, 2, "Quarter of a beat should be at subdivision 2 with 4 subdivisions")
    }

    func testMusicalPositionWithDifferentSubdivisions() {
        let bpm = 120.0
        let time = 0.25  // Half a beat

        let position4Subdivisions = MusicalTransport.position(
            at: time,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        let position8Subdivisions = MusicalTransport.position(
            at: time,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 8,
            ticksPerBeat: 480
        )

        XCTAssertNotEqual(
            position4Subdivisions.subdivision,
            position8Subdivisions.subdivision,
            "Different subdivision counts should produce different subdivision values"
        )
    }

    // MARK: - Tick Precision Tests

    func testMusicalPositionTicksPerBeat() {
        let bpm = 120.0
        // Very small time increment to test tick precision
        let positionAtTick100 = MusicalTransport.position(
            at: 0.01042,  // Approximately 1/96 of a beat
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertGreaterThanOrEqual(positionAtTick100.tick, 0, "Tick should not be negative")
        XCTAssertLessThan(positionAtTick100.tick, 480, "Tick should be less than ticksPerBeat")
    }

    // MARK: - Common Timing Scenarios

    func testMusicalPositionAtTypicalNoteTime() {
        // Typical note at bar 2, beat 3
        let bpm = 120.0
        // Bar 2, beat 3 = 1 bar (2 seconds) + 2 beats (1 second) = 3 seconds
        let position = MusicalTransport.position(
            at: 3.0,
            bpm: bpm,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertEqual(position.bar, 2, "Should be at Bar 2")
        XCTAssertEqual(position.beat, 3, "Should be at Beat 3")
    }

    func testMusicalPositionProgressionAcrossBars() {
        let bpm = 120.0
        var positions: [MusicalPosition] = []

        // Get positions for 3 full bars
        for barIndex in 0..<3 {
            let timeForBar = Double(barIndex) * 2.0  // 2 seconds per bar
            let position = MusicalTransport.position(
                at: timeForBar,
                bpm: bpm,
                songOffset: 0.0,
                beatsPerBar: 4,
                subdivisionsPerBeat: 4,
                ticksPerBeat: 480
            )
            positions.append(position)
        }

        XCTAssertEqual(positions[0].bar, 1, "First position should be Bar 1")
        XCTAssertEqual(positions[1].bar, 2, "Second position should be Bar 2")
        XCTAssertEqual(positions[2].bar, 3, "Third position should be Bar 3")

        // All should be at beat 1 when at bar boundaries
        for position in positions {
            XCTAssertEqual(position.beat, 1, "All bar boundaries should start at Beat 1")
        }
    }

    // MARK: - Edge Cases

    func testMusicalPositionNeverNegative() {
        let position = MusicalTransport.position(
            at: -1.0,  // Negative time
            bpm: 120.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        XCTAssertGreaterThanOrEqual(position.bar, 1, "Bar should never be less than 1")
        XCTAssertGreaterThanOrEqual(position.beat, 1, "Beat should never be less than 1")
        XCTAssertGreaterThanOrEqual(position.subdivision, 1, "Subdivision should never be less than 1")
        XCTAssertGreaterThanOrEqual(position.tick, 0, "Tick should never be negative")
    }

    func testMusicalPositionZeroBPMDoesNotCrash() {
        let position = MusicalTransport.position(
            at: 1.0,
            bpm: 0.0,  // Invalid BPM
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 480
        )

        // Should not crash; behavior with zero BPM is undefined but should be safe
        XCTAssertGreaterThanOrEqual(position.bar, 1, "Should handle zero BPM gracefully")
    }

    func testMusicalPositionZeroTicksPerBeatDoesNotCrash() {
        let position = MusicalTransport.position(
            at: 1.0,
            bpm: 120.0,
            songOffset: 0.0,
            beatsPerBar: 4,
            subdivisionsPerBeat: 4,
            ticksPerBeat: 0  // Invalid
        )

        // Should not crash; implementation should handle this
        XCTAssertGreaterThanOrEqual(position.tick, 0, "Should handle zero ticksPerBeat gracefully")
    }
}
