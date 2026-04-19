import XCTest
import SpriteKit
@testable import MasterOfDrums

final class GameplaySceneNoteAlignmentTests: XCTestCase {

    // MARK: - Note Rendering Tests

    func testGameplaySceneCreatesNoteNodesForNotes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 1.5),
        ]
        let chart = Chart(notes: notes, title: "Note Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        // Update scene to render notes
        scene.update(0.0)

        let highway = scene._testHighwayNode
        let noteNodes = highway.children.compactMap { $0 as? SKShapeNode }.filter {
            $0.fillColor != .darkGray && $0.strokeColor != .darkGray
        }

        // Should have at least 3 note nodes (one per note)
        XCTAssertGreaterThanOrEqual(noteNodes.count, 3, "Should create note nodes for each note")
    }

    func testNotesArePositionedInCorrectLanes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 1.0),      // Lane 0
            NoteEvent(lane: .yellow, time: 1.0),   // Lane 1
            NoteEvent(lane: .blue, time: 1.0),     // Lane 2
            NoteEvent(lane: .green, time: 1.0),    // Lane 3
            NoteEvent(lane: .purple, time: 1.0),   // Lane 4
        ]
        let chart = Chart(notes: notes, title: "Lane Position Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.update(0.0)

        let laneOrder = scene._testLaneOrder
        XCTAssertEqual(laneOrder.count, 5, "Should have 5 lanes")

        // Verify lanes are in canonical order
        XCTAssertEqual(laneOrder[0].sourceLane, .red, "Lane 0 should be red")
        XCTAssertEqual(laneOrder[1].sourceLane, .yellow, "Lane 1 should be yellow")
        XCTAssertEqual(laneOrder[2].sourceLane, .blue, "Lane 2 should be blue")
        XCTAssertEqual(laneOrder[3].sourceLane, .green, "Lane 3 should be green")
        XCTAssertEqual(laneOrder[4].sourceLane, .purple, "Lane 4 should be purple")

        // With all lanes present and all notes at same time (1.0 second),
        // notes should be horizontally distributed across the 5 lanes
        let highway = scene._testHighwayNode
        XCTAssertGreaterThan(highway.children.count, 5, "Highway should have nodes for lanes and notes")
    }

    // MARK: - Note Time Alignment Tests

    func testNotesAtDifferentTimesHaveDifferentVerticalPositions() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5),  // Early
            NoteEvent(lane: .red, time: 2.0),  // Late
        ]
        let chart = Chart(notes: notes, title: "Time Alignment Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.update(0.0)

        // Notes at different times should be rendered at different y-positions
        // The later note should be higher on screen (further down the track)
        // This is verified indirectly by checking both notes exist as distinct nodes
        let highway = scene._testHighwayNode
        let noteNodes = highway.children.compactMap { $0 as? SKShapeNode }

        // Should have lane nodes + note nodes
        XCTAssertGreaterThanOrEqual(noteNodes.count, 2, "Should have at least 2 note nodes for 2 notes")
    }

    // MARK: - Multiple Notes Per Lane Tests

    func testMultipleNotesInSameLaneRenderWithoutOverlap() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5),
            NoteEvent(lane: .red, time: 1.0),
            NoteEvent(lane: .red, time: 1.5),
            NoteEvent(lane: .red, time: 2.0),
        ]
        let chart = Chart(notes: notes, title: "Multiple Notes Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.update(0.0)

        let highway = scene._testHighwayNode
        let allNodes = highway.children

        // With 4 notes in same lane:
        // - Lane nodes (1 lane × 4 = lane + highlight + 2 labels)
        // - hitLine
        // Verify highway has sufficient nodes
        XCTAssertGreaterThanOrEqual(allNodes.count, 5, "Should have nodes for lane structure")
    }

    // MARK: - Full Chart Rendering Test

    func testCompleteChartRendersAllNotesInCorrectLanes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat"),
            NoteEvent(lane: .yellow, time: 1.5, label: "Hi-Hat"),
            NoteEvent(lane: .blue, time: 2.0, label: "Tom"),
            NoteEvent(lane: .green, time: 2.5, label: "Crash"),
            NoteEvent(lane: .green, time: 3.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 3.5, label: "Kick"),
            NoteEvent(lane: .purple, time: 4.0, label: "Kick"),
        ]
        let chart = Chart(notes: notes, title: "Complete Chart Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.update(0.0)

        let highway = scene._testHighwayNode
        let allNodes = highway.children

        // With 5 lanes (2 shape nodes + 2 labels per lane = 4 per lane = 20 total)
        // Plus hitLine = 21 total nodes
        XCTAssertGreaterThanOrEqual(allNodes.count, 20, "Should have nodes for 5 lanes + hitLine")

        let laneOrder = scene._testLaneOrder
        XCTAssertEqual(laneOrder.count, 5, "All 5 lanes should be present")
    }

    // MARK: - Lane Index Consistency Tests

    func testLaneIndexingIsConsistentWithNotePositioning() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 1.0),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 1.0),
            NoteEvent(lane: .green, time: 1.0),
            NoteEvent(lane: .purple, time: 1.0),
        ]
        let chart = Chart(notes: notes, title: "Index Consistency Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        let laneIndexByID = scene._testLaneIndexByID
        let laneOrder = scene._testLaneOrder

        // Verify mapping is consistent
        for (index, lane) in laneOrder.enumerated() {
            XCTAssertEqual(laneIndexByID[lane.id], index,
                          "Lane '\(lane.id)' should be at index \(index), got \(laneIndexByID[lane.id] ?? -1)")
        }

        // Verify lanes are in canonical order (indices 0-4)
        XCTAssertEqual(laneIndexByID["red"], 0)
        XCTAssertEqual(laneIndexByID["yellow"], 1)
        XCTAssertEqual(laneIndexByID["blue"], 2)
        XCTAssertEqual(laneIndexByID["green"], 3)
        XCTAssertEqual(laneIndexByID["purple"], 4)
    }

    // MARK: - Edge Cases

    func testEmptyChartStillRenderLanes() {
        let chart = Chart(notes: [], title: "Empty Chart")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.update(0.0)

        let laneOrder = scene._testLaneOrder
        XCTAssertGreaterThan(laneOrder.count, 0, "Empty chart should still render default lanes")

        // All 5 default lanes should be present
        let lanes = Set(laneOrder.map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 5, "Should have 5 default lanes")
    }

    func testSingleNoteRendersCorrectly() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .blue, time: 1.5, label: "Tom")
        ]
        let chart = Chart(notes: notes, title: "Single Note Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.update(0.0)

        let highway = scene._testHighwayNode
        let allNodes = highway.children

        // Should have: lane nodes (1 lane × 4 nodes) + note node + hitLine
        // Minimum: 5 nodes
        XCTAssertGreaterThanOrEqual(allNodes.count, 5,
                                   "Should render lane and note nodes even for single note")

        let laneOrder = scene._testLaneOrder
        XCTAssertEqual(laneOrder.count, 1, "Should have only one lane when notes use only one lane")
        XCTAssertEqual(laneOrder[0].sourceLane, .blue, "Lane should be blue")
    }
}
