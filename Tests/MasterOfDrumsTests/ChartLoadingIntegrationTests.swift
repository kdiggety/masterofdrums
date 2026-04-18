import XCTest
@testable import MasterOfDrums

@MainActor
final class ChartLoadingIntegrationTests: XCTestCase {

    // MARK: - Ken: Full Lane Coverage Test

    func testLoadKenChartHasExpectedLanes() throws {
        let url = URL(fileURLWithPath: "/Users/klewisjr/Development/MacOS/masterofdrums/Examples/im-just-ken-ryan-gosling-from-barbie.modchart.json")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: url)

        // Ken should have snare, tom, crash, and kick (no hihat in this MIDI)
        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertTrue(lanes.contains(.red), "Should have snare lane")
        XCTAssertTrue(lanes.contains(.blue), "Should have tom lane")
        XCTAssertTrue(lanes.contains(.green), "Should have crash lane")
        XCTAssertTrue(lanes.contains(.kick), "Should have kick lane")
    }

    func testKenNotesMapToCorrectLanes() throws {
        let url = URL(fileURLWithPath: "/Users/klewisjr/Development/MacOS/masterofdrums/Examples/im-just-ken-ryan-gosling-from-barbie.modchart.json")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: url)

        // Verify note distribution matches expected lanes
        let notesPerLane = Dictionary(grouping: chart.notes, by: { $0.lane })
        XCTAssertGreaterThan(notesPerLane[Lane.red, default: []].count, 0, "Snare notes should exist")
        XCTAssertGreaterThan(notesPerLane[Lane.blue, default: []].count, 0, "Tom notes should exist")
        XCTAssertGreaterThan(notesPerLane[Lane.green, default: []].count, 0, "Crash notes should exist")
        XCTAssertGreaterThan(notesPerLane[Lane.kick, default: []].count, 0, "Kick notes should exist")
    }

    // MARK: - Dragula: Rock with Full Coverage

    func testLoadDragulaChartHasExpectedLanes() throws {
        let url = URL(fileURLWithPath: "/Users/klewisjr/Development/MacOS/masterofdrums/Examples/rob-zombie-dragula.modchart.json")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: url)

        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertTrue(lanes.contains(.red), "Should have snare")
        XCTAssertTrue(lanes.contains(.yellow), "Should have hihat")
        XCTAssertTrue(lanes.contains(.kick), "Should have kick")
    }

    // MARK: - All Charts Load Correctly

    func testAllChartsLoadWithoutErrors() throws {
        let chartNames = [
            "im-just-ken-ryan-gosling-from-barbie",
            "rob-zombie-dragula",
            "killing-me-softly-arr-kaden-connell",
            "the-real-slim-shady-eminem",
            "timbaland-ft-onerepublic-apologize-committed-cover"
        ]

        let chartStore = ChartFileStore()
        for name in chartNames {
            let url = URL(fileURLWithPath: "/Users/klewisjr/Development/MacOS/masterofdrums/Examples/\(name).modchart.json")
            let (chart, _, _, _) = try chartStore.loadChart(from: url)
            XCTAssertGreaterThan(chart.notes.count, 0, "\(name) should load with notes")
        }
    }

    // MARK: - Lane Label Consistency

    func testDisplayLanesHaveValidLabels() throws {
        let url = URL(fileURLWithPath: "/Users/klewisjr/Development/MacOS/masterofdrums/Examples/im-just-ken-ryan-gosling-from-barbie.modchart.json")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: url)

        let displayLanes = chart.displayLanes()
        for lane in displayLanes {
            XCTAssertFalse(lane.label.isEmpty, "Lane label should not be empty")
            XCTAssertTrue(Lane.allCases.contains(lane.sourceLane), "Lane should have valid sourceLane")
        }
    }
}
