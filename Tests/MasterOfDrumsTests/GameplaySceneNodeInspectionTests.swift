import XCTest
import SpriteKit
@testable import MasterOfDrums

final class GameplaySceneNodeInspectionTests: XCTestCase {

    // MARK: - Scene Structure Tests

    func testGameplaySceneCreatesHighwayNode() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5),
            NoteEvent(lane: .yellow, time: 1.0),
        ]
        let chart = Chart(notes: notes, title: "Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        XCTAssertNotNil(highway, "Scene should have a highway node")
        XCTAssertGreaterThan(highway.children.count, 0, "Highway should have child nodes")
    }

    // MARK: - Lane Node Tests

    func testGameplaySceneCreatesLaneNodesForEachLane() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 2.0),
            NoteEvent(lane: .green, time: 3.0),
            NoteEvent(lane: .purple, time: 4.0),
        ]
        let chart = Chart(notes: notes, title: "All Lanes")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        let shapeNodes = highway.children.compactMap { $0 as? SKShapeNode }

        // Each lane creates a laneNode and a highlightNode = 2 SKShapeNodes per lane
        // So with 5 lanes, we expect at least 10 SKShapeNodes
        XCTAssertGreaterThanOrEqual(shapeNodes.count, 10, "Should have at least 10 shape nodes (5 lanes × 2 nodes)")
    }

    func testLaneNodesHaveCorrectColors() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 2.0),
            NoteEvent(lane: .green, time: 3.0),
            NoteEvent(lane: .purple, time: 4.0),
        ]
        let chart = Chart(notes: notes, title: "Color Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        let shapeNodes = highway.children.compactMap { $0 as? SKShapeNode }

        // Expected colors with 0.17 alpha (lane nodes) and 0.35 alpha (highlight nodes)
        let expectedColors = [
            NSColor.systemRed.withAlphaComponent(0.17),
            NSColor.systemRed.withAlphaComponent(0.35),
            NSColor.systemYellow.withAlphaComponent(0.17),
            NSColor.systemYellow.withAlphaComponent(0.35),
            NSColor.systemBlue.withAlphaComponent(0.17),
            NSColor.systemBlue.withAlphaComponent(0.35),
            NSColor.systemGreen.withAlphaComponent(0.17),
            NSColor.systemGreen.withAlphaComponent(0.35),
            NSColor.systemPurple.withAlphaComponent(0.17),
            NSColor.systemPurple.withAlphaComponent(0.35),
        ]

        for (index, expectedColor) in expectedColors.enumerated() {
            guard index < shapeNodes.count else {
                XCTFail("Not enough shape nodes created")
                return
            }
            let actualColor = shapeNodes[index].fillColor
            XCTAssertEqual(actualColor, expectedColor,
                          "Shape node \(index) should have color \(expectedColor), got \(actualColor)")
        }
    }

    // MARK: - Label Node Tests

    func testGameplaySceneCreatesKeyLabelsForEachLane() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 2.0),
            NoteEvent(lane: .green, time: 3.0),
            NoteEvent(lane: .purple, time: 4.0),
        ]
        let chart = Chart(notes: notes, title: "Key Labels")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        let labelNodes = highway.children.compactMap { $0 as? SKLabelNode }

        // Each lane creates a keyLabel and a drumLabel = 2 labels per lane
        // So with 5 lanes, we expect 10 labels
        XCTAssertGreaterThanOrEqual(labelNodes.count, 10, "Should have at least 10 label nodes (5 lanes × 2 labels)")
    }

    func testKeyLabelsDisplayCorrectText() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat Closed"),
            NoteEvent(lane: .blue, time: 2.0, label: "Tom High"),
            NoteEvent(lane: .green, time: 3.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 4.0, label: "Kick"),
        ]
        let chart = Chart(notes: notes, title: "Label Text")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        let labelNodes = highway.children.compactMap { $0 as? SKLabelNode }

        // Expected text patterns: D, Snare, F, Hi-Hat Closed, J, Tom High, K, Crash, ␣, Kick
        let expectedTexts = ["D", "Snare", "F", "Hi-Hat Closed", "J", "Tom High", "K", "Crash", "␣", "Kick"]

        for (index, expected) in expectedTexts.enumerated() {
            guard index < labelNodes.count else {
                XCTFail("Not enough label nodes created")
                return
            }
            let actual = labelNodes[index].text ?? ""
            XCTAssertEqual(actual, expected,
                          "Label node \(index) should show '\(expected)', got '\(actual)'")
        }
    }

    // MARK: - Node Hierarchy Tests

    func testNodesAreAddedToHighwayInCorrectOrder() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0),
            NoteEvent(lane: .yellow, time: 1.0),
        ]
        let chart = Chart(notes: notes, title: "Order Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        let allNodes = highway.children

        // With 2 lanes, we expect:
        // - laneNode (red)
        // - highlightNode (red)
        // - keyLabel (D)
        // - drumLabel (Snare)
        // - laneNode (yellow)
        // - highlightNode (yellow)
        // - keyLabel (F)
        // - drumLabel (Hi-Hat)
        // + hitLine at the end
        // Total: at least 9 nodes

        XCTAssertGreaterThanOrEqual(allNodes.count, 9,
                                   "Should have nodes for 2 lanes (2 lanes × 4 nodes each + hitLine)")
    }

    // MARK: - Full Pipeline Rendering Test

    func testFullRenderingPipelineCreatesCorrectNodeHierarchy() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat"),
            NoteEvent(lane: .blue, time: 1.5, label: "Tom"),
            NoteEvent(lane: .green, time: 2.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 2.5, label: "Kick"),
        ]
        let chart = Chart(notes: notes, title: "Full Render Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let highway = scene._testHighwayNode
        let shapeNodes = highway.children.compactMap { $0 as? SKShapeNode }
        let labelNodes = highway.children.compactMap { $0 as? SKLabelNode }

        // Verify we have the right number of nodes
        // 5 lanes × 2 shape nodes each = 10, plus 1 hitLine = 11, plus 5 note nodes = 16 total shape nodes
        XCTAssertEqual(shapeNodes.count, 16, "Should have 16 shape nodes (5 lanes × 2 + hitLine + 5 notes)")
        XCTAssertEqual(labelNodes.count, 10, "Should have 10 label nodes (5 lanes × 2)")

        // Verify colors are correct (first shape node should be red with 0.17 alpha)
        let firstLaneColor = shapeNodes[0].fillColor
        let expectedRedColor = NSColor.systemRed.withAlphaComponent(0.17)
        XCTAssertEqual(firstLaneColor, expectedRedColor,
                      "First lane should be red with 0.17 alpha")

        // Verify labels are correct
        XCTAssertEqual(labelNodes[0].text, "D", "First key label should be D")
        XCTAssertEqual(labelNodes[1].text, "Snare", "First drum label should be Snare")
        XCTAssertEqual(labelNodes[2].text, "F", "Second key label should be F")
        XCTAssertEqual(labelNodes[3].text, "Hi-Hat", "Second drum label should be Hi-Hat")

        // Verify purple (last lane) is rendered with correct color
        let lastLaneColor = shapeNodes[8].fillColor  // Second-to-last shape node (9th)
        let expectedPurpleColor = NSColor.systemPurple.withAlphaComponent(0.17)
        XCTAssertEqual(lastLaneColor, expectedPurpleColor,
                      "Last lane should be purple with 0.17 alpha")
    }
}
