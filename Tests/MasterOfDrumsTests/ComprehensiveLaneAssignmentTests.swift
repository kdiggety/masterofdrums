import XCTest
@testable import MasterOfDrums

final class ComprehensiveLaneAssignmentTests: XCTestCase {

    // MARK: - Lane Enum Comprehensive Assignment

    func testLaneEnumHasFiveColorCases() {
        let allLanes = Lane.allCases
        XCTAssertEqual(allLanes.count, 5, "Must have exactly 5 lanes")
    }

    func testLaneEnumOrderIsCanonical() {
        let lanes = Lane.allCases
        XCTAssertEqual(lanes[0], .red, "Lane 0 must be red")
        XCTAssertEqual(lanes[1], .yellow, "Lane 1 must be yellow")
        XCTAssertEqual(lanes[2], .blue, "Lane 2 must be blue")
        XCTAssertEqual(lanes[3], .green, "Lane 3 must be green")
        XCTAssertEqual(lanes[4], .purple, "Lane 4 must be purple")
    }

    func testLaneRawValuesAreSequential() {
        XCTAssertEqual(Lane.red.rawValue, 0)
        XCTAssertEqual(Lane.yellow.rawValue, 1)
        XCTAssertEqual(Lane.blue.rawValue, 2)
        XCTAssertEqual(Lane.green.rawValue, 3)
        XCTAssertEqual(Lane.purple.rawValue, 4)
    }

    // MARK: - Lane Display Names

    func testLaneDisplayNamesAreColors() {
        XCTAssertEqual(Lane.red.displayName, "Red")
        XCTAssertEqual(Lane.yellow.displayName, "Yellow")
        XCTAssertEqual(Lane.blue.displayName, "Blue")
        XCTAssertEqual(Lane.green.displayName, "Green")
        XCTAssertEqual(Lane.purple.displayName, "Purple")
    }

    // MARK: - Lane Key Labels (Keyboard)

    func testLaneKeyLabels() {
        XCTAssertEqual(Lane.red.keyLabel, "D", "Red (snare) uses D key")
        XCTAssertEqual(Lane.yellow.keyLabel, "F", "Yellow (hihat) uses F key")
        XCTAssertEqual(Lane.blue.keyLabel, "J", "Blue (tom) uses J key")
        XCTAssertEqual(Lane.green.keyLabel, "K", "Green (crash) uses K key")
        XCTAssertEqual(Lane.purple.keyLabel, "␣", "Purple (kick) uses Space key")
    }

    // MARK: - Lane Instrument Labels

    func testLaneInstrumentLabels() {
        XCTAssertEqual(Lane.red.laneLabel, "Snare", "Red lane labeled for snare")
        XCTAssertEqual(Lane.yellow.laneLabel, "Hi-Hat", "Yellow lane labeled for hihat")
        XCTAssertEqual(Lane.blue.laneLabel, "Tom", "Blue lane labeled for tom")
        XCTAssertEqual(Lane.green.laneLabel, "Crash", "Green lane labeled for crash/cymbals")
        XCTAssertEqual(Lane.purple.laneLabel, "Kick", "Purple lane labeled for kick")
    }

    // MARK: - Pipeline Lane to Swift Lane Mapping

    func testPipelineKickMapsToLanePurple() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "kick"), Lane.purple.rawValue)
    }

    func testPipelineSnareClapMapToLaneRed() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "snare"), Lane.red.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "clap"), Lane.red.rawValue)
    }

    func testPipelineHihatClosedMapsToLaneYellow() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihat_closed"), Lane.yellow.rawValue)
    }

    func testPipelineHihatOpenMapsToLaneGreen() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "hihat_open"), Lane.green.rawValue)
    }

    func testPipelineTomHighMapsToLaneBlue() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_high"), Lane.blue.rawValue)
    }

    func testPipelineTomLowMidMapToLaneGreen() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_low"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_mid"), Lane.green.rawValue)
    }

    func testPipelineCymbalsCrashRideMapToLaneGreen() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "crash"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "ride"), Lane.green.rawValue)
    }

    func testPipelinePercussionMapsToLaneGreen() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "percussion"), Lane.green.rawValue)
    }

    // MARK: - Comprehensive Assignment Validation

    func testComprehensiveAssignment() {
        // Validate the complete mapping matrix
        let assignments: [(String, Lane)] = [
            // Lane 0 - Red (Snare/Clap)
            ("snare", .red),
            ("clap", .red),
            // Lane 1 - Yellow (Hi-Hat Closed)
            ("hihat_closed", .yellow),
            // Lane 2 - Blue (Tom High)
            ("tom_high", .blue),
            // Lane 3 - Green (Tom Low/Mid, Hi-Hat Open, Crash, Ride, Percussion)
            ("tom_low", .green),
            ("tom_mid", .green),
            ("hihat_open", .green),
            ("crash", .green),
            ("ride", .green),
            ("percussion", .green),
            // Lane 4 - Purple (Kick)
            ("kick", .purple),
        ]

        for (pipelineLane, expectedSwiftLane) in assignments {
            let actualIndex = ChartDocument.laneIndex(forPipelineLane: pipelineLane)
            XCTAssertEqual(
                actualIndex,
                expectedSwiftLane.rawValue,
                "Pipeline lane '\(pipelineLane)' should map to \(expectedSwiftLane.displayName) (\(expectedSwiftLane.rawValue))"
            )
        }
    }

    // MARK: - Lane Deduplication Rules

    func testHihatClosedAndOpenAreDistinct() {
        let closedIndex = ChartDocument.laneIndex(forPipelineLane: "hihat_closed")
        let openIndex = ChartDocument.laneIndex(forPipelineLane: "hihat_open")
        XCTAssertNotEqual(closedIndex, openIndex, "Closed and open hihats must be on different lanes")
        XCTAssertEqual(closedIndex, Lane.yellow.rawValue, "Closed hihat on yellow")
        XCTAssertEqual(openIndex, Lane.green.rawValue, "Open hihat on green with cymbals")
    }

    func testTomVariantsMapCorrectly() {
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_high"), Lane.blue.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_mid"), Lane.green.rawValue)
        XCTAssertEqual(ChartDocument.laneIndex(forPipelineLane: "tom_low"), Lane.green.rawValue)

        // Verify tom_high is alone on blue
        XCTAssertNotEqual(
            ChartDocument.laneIndex(forPipelineLane: "tom_high"),
            ChartDocument.laneIndex(forPipelineLane: "tom_mid"),
            "Tom high should not map to same lane as tom mid"
        )
    }

    func testSnareClapAreGrouped() {
        let snareIndex = ChartDocument.laneIndex(forPipelineLane: "snare")
        let clapIndex = ChartDocument.laneIndex(forPipelineLane: "clap")
        XCTAssertEqual(snareIndex, clapIndex, "Snare and clap should map to same lane")
        XCTAssertEqual(snareIndex, Lane.red.rawValue, "Both on red lane")
    }

    func testCymbalFamilyIsGrouped() {
        let crashIndex = ChartDocument.laneIndex(forPipelineLane: "crash")
        let rideIndex = ChartDocument.laneIndex(forPipelineLane: "ride")
        XCTAssertEqual(crashIndex, rideIndex, "Crash and ride should map to same lane")
        XCTAssertEqual(crashIndex, Lane.green.rawValue, "Cymbals on green lane")
    }

    // MARK: - All Lanes Accounted For

    func testAllPipelineLanesHaveMapping() {
        let pipelineLanes = [
            "kick", "snare", "clap",
            "hihat_closed", "hihat_open",
            "tom_low", "tom_mid", "tom_high",
            "crash", "ride", "percussion"
        ]

        for lane in pipelineLanes {
            let index = ChartDocument.laneIndex(forPipelineLane: lane)
            XCTAssertNotNil(index, "Pipeline lane '\(lane)' must have a Swift lane mapping")
            XCTAssertGreaterThanOrEqual(index!, 0, "Lane index must be >= 0")
            XCTAssertLessThan(index!, 5, "Lane index must be < 5 (0-4 valid)")
        }
    }

    func testNoMissingLaneNumbers() {
        var usedLanes = Set<Int>()
        let pipelineLanes = [
            "kick", "snare", "clap", "hihat_closed", "hihat_open",
            "tom_low", "tom_mid", "tom_high", "crash", "ride", "percussion"
        ]

        for lane in pipelineLanes {
            if let index = ChartDocument.laneIndex(forPipelineLane: lane) {
                usedLanes.insert(index)
            }
        }

        // All lanes 0-4 should be used
        XCTAssertEqual(usedLanes, Set([0, 1, 2, 3, 4]), "All 5 lanes must be used")
    }
}
