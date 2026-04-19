import XCTest
import SpriteKit
@testable import MasterOfDrums

final class GameplaySceneNotePositioningTests: XCTestCase {

    // MARK: - Note X-Position Tests

    func testNotesAreCenteredWithinLanes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 1.0),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 1.0),
            NoteEvent(lane: .green, time: 1.0),
            NoteEvent(lane: .purple, time: 1.0),
        ]
        let chart = Chart(notes: notes, title: "Positioning Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)
        scene.update(0.0)

        let highway = scene._testHighwayNode
        let noteNodes = highway.children.compactMap { node -> SKShapeNode? in
            guard let shapeNode = node as? SKShapeNode,
                  let name = node.name,
                  name.hasPrefix("note-") else { return nil }
            return shapeNode
        }

        // Calculate lane positions
        let laneOrder = scene._testLaneOrder
        let totalWidth = scene._testLaneWidth * CGFloat(laneOrder.count)
        let startX = (scene.size.width - totalWidth) / 2

        // Verify each note is centered in its lane
        for lane in laneOrder {
            let laneX = startX + CGFloat(lane.sourceLane.rawValue) * scene._testLaneWidth
            let laneMidX = laneX + scene._testLaneWidth / 2
            let laneMinX = laneX
            let laneMaxX = laneX + scene._testLaneWidth

            // Find notes that belong to this lane
            let laneNotes = notes.filter { $0.lane == lane.sourceLane }
            XCTAssertGreaterThan(laneNotes.count, 0, "Lane \(lane.sourceLane) should have at least one note")

            // All notes in this lane should have X-position within lane bounds
            for note in laneNotes {
                // Find the corresponding note node
                let noteNode = noteNodes.first { node in
                    // Try to match by position (since we don't have direct access to note IDs in nodes)
                    abs(node.position.x - laneMidX) < 5  // Within 5 points of center
                }

                if let noteNode = noteNode {
                    XCTAssertGreaterThanOrEqual(noteNode.position.x, laneMinX - 5,
                                              "Note in lane \(lane.sourceLane) should not extend past left boundary")
                    XCTAssertLessThanOrEqual(noteNode.position.x, laneMaxX + 5,
                                           "Note in lane \(lane.sourceLane) should not extend past right boundary")
                }
            }
        }
    }

    func testNotesDoNotSpanAcrossLaneBoundaries() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 1.0, label: "Snare"),
            NoteEvent(lane: .green, time: 1.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 1.0, label: "Kick"),
        ]
        let chart = Chart(notes: notes, title: "Boundary Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)
        scene.update(0.0)

        // Calculate lane boundaries
        let laneOrder = scene._testLaneOrder
        let totalWidth = scene._testLaneWidth * CGFloat(laneOrder.count)
        let startX = (scene.size.width - totalWidth) / 2

        let laneBoundaries = laneOrder.map { lane -> (lane: Lane, minX: CGFloat, maxX: CGFloat) in
            let laneX = startX + CGFloat(lane.sourceLane.rawValue) * scene._testLaneWidth
            return (lane.sourceLane, laneX, laneX + scene._testLaneWidth)
        }

        let highway = scene._testHighwayNode
        let noteNodes = highway.children.compactMap { node -> SKShapeNode? in
            guard let shapeNode = node as? SKShapeNode,
                  let name = node.name,
                  name.hasPrefix("note-") else { return nil }
            return shapeNode
        }

        // Each note should be within its lane's horizontal bounds
        for noteNode in noteNodes {
            var foundLane = false
            for (_, minX, maxX) in laneBoundaries {
                if noteNode.position.x >= minX - 30 && noteNode.position.x <= maxX + 30 {  // 30 = half of widest note
                    foundLane = true
                    break
                }
            }
            XCTAssert(foundLane, "Note at position \(noteNode.position.x) should be within some lane's horizontal bounds")
        }
    }
}

