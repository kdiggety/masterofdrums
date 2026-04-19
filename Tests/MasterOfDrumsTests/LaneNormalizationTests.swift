import XCTest
@testable import MasterOfDrums

final class LaneNormalizationTests: XCTestCase {

    // MARK: - Kick Mappings

    func testKickMappings() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "kick"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "Kick"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "KICK"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: " kick "), Lane.purple.rawValue)
    }

    func testDrumMachineKickMappings() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "808"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "909"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "bass drum"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "kick drum"), Lane.purple.rawValue)
    }

    // MARK: - Snare Mappings

    func testSnareMappings() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "snare"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "Snare"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "SNARE"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: " snare "), Lane.red.rawValue)
    }

    func testSnareVariations() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "clap"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hand clap"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hand drum"), Lane.red.rawValue)
    }

    // MARK: - Hi-Hat and Cymbal Family (Yellow)

    func testHiHatClosedMappings() {
        // camelCase variants from pipeline
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihatClosed"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihatclosed"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "HihatClosed"), Lane.yellow.rawValue)

        // Various text forms
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihat"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hi hat"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "closed hat"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "closed hihat"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihat pedal"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hi hat pedal"), Lane.yellow.rawValue)
    }

    func testHiHatOpenMappings() {
        // camelCase variants from pipeline
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihatOpen"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihatopen"), Lane.green.rawValue)

        // Various text forms
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "open hat"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "open hihat"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihat open"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hi hat open"), Lane.green.rawValue)
    }

    func testCymbalMappings() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "crash"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "ride"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "cymbal"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "gong"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "bell"), Lane.green.rawValue)
    }

    // MARK: - Tom High Mappings (Blue)

    func testTomHighMappings() {
        // camelCase variants from pipeline
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tomHigh"), Lane.blue.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tomhigh"), Lane.blue.rawValue)

        // snake_case variants for backwards compatibility
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_high"), Lane.blue.rawValue)

        // Various text forms
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom high"), Lane.blue.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "high tom"), Lane.blue.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom1"), Lane.blue.rawValue)
    }

    // MARK: - Tom Mid/Low and Percussion Mappings (Green)

    func testTomMidMappings() {
        // camelCase variants from pipeline
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tomMid"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tommid"), Lane.green.rawValue)

        // snake_case variants for backwards compatibility
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_mid"), Lane.green.rawValue)

        // Various text forms
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom mid"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "mid tom"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom2"), Lane.green.rawValue)
    }

    func testTomLowMappings() {
        // camelCase variants from pipeline
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tomLow"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tomlow"), Lane.green.rawValue)

        // snake_case variants for backwards compatibility
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_low"), Lane.green.rawValue)

        // Various text forms
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom low"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "low tom"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "floor tom"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom3"), Lane.green.rawValue)
    }

    func testPercussionMappings() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "percussion"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "timpani"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "bongo"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "conga"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "woodblock"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "cowbell"), Lane.green.rawValue)
    }

    // MARK: - Edge Cases

    func testWhitespaceHandling() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "  kick  "), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "\tsnare\n"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: " crash "), Lane.green.rawValue)
    }

    func testMixedCaseHandling() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "KiCk"), Lane.purple.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "SNARE"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "HiHatClosed"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "TomHigh"), Lane.blue.rawValue)
    }

    func testExplicitLaneNames() {
        // Explicit lane names for fallback/debugging
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "red"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "yellow"), Lane.yellow.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "blue"), Lane.blue.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "green"), Lane.green.rawValue)
    }

    func testUnmappedLanesReturnNil() {
        XCTAssertNil(ChartDocument.laneIndex(forPipelineLane: "unknown"))
        XCTAssertNil(ChartDocument.laneIndex(forPipelineLane: "undefined"))
        XCTAssertNil(ChartDocument.laneIndex(forPipelineLane: "xyz"))
        XCTAssertNil(ChartDocument.laneIndex(forPipelineLane: ""))
    }

    // MARK: - Integration: Chart Loading with Pipeline Format

    func testChartLoadingWithCamelCaseLanes() {
        // Simulates loading a chart generated by the pipeline with camelCase lane names
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .purple, time: 0.0, label: "Kick"),
            NoteEvent(id: UUID(), lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(id: UUID(), lane: .yellow, time: 1.0, label: "HiHat Closed"),
            NoteEvent(id: UUID(), lane: .blue, time: 1.5, label: "Tom High"),
            NoteEvent(id: UUID(), lane: .green, time: 2.0, label: "Crash"),
        ]
        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes()

        // Verify correct lanes in order of appearance
        XCTAssertEqual(displayLanes.count, 5)
        XCTAssertEqual(displayLanes.map { $0.sourceLane }, [.purple, .red, .yellow, .blue, .green])
    }

    func testMixedLaneNamesInChart() {
        // Some notes might have explicit labels, others use lane defaults
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .purple, time: 0.0, label: "808 Bass"),
            NoteEvent(id: UUID(), lane: .red, time: 0.5, label: nil), // Should use "Snare" as default
            NoteEvent(id: UUID(), lane: .yellow, time: 1.0, label: "Crash Cymbal"),
        ]
        let chart = Chart(notes: notes, title: "Mixed")

        XCTAssertEqual(chart.notes[0].displayLabel, "808 Bass")
        XCTAssertEqual(chart.notes[1].displayLabel, "Snare") // Fallback to lane label
        XCTAssertEqual(chart.notes[2].displayLabel, "Crash Cymbal")
    }
}
