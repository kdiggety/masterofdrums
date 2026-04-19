import XCTest
@testable import MasterOfDrums

final class GameplaySceneRenderingTests: XCTestCase {

    // MARK: - Lane Color Mapping Tests

    func testGameplaySceneColorFunctionReturnsCorrectColors() {
        let chart = Chart(notes: [], title: "Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        // Test that color function returns correct system colors
        // Red lane
        let redColor = GameplayScene.staticColor(for: .red)
        XCTAssertEqual(redColor, .systemRed, "Red lane should use systemRed")

        // Yellow lane
        let yellowColor = GameplayScene.staticColor(for: .yellow)
        XCTAssertEqual(yellowColor, .systemYellow, "Yellow lane should use systemYellow")

        // Blue lane
        let blueColor = GameplayScene.staticColor(for: .blue)
        XCTAssertEqual(blueColor, .systemBlue, "Blue lane should use systemBlue")

        // Green lane
        let greenColor = GameplayScene.staticColor(for: .green)
        XCTAssertEqual(greenColor, .systemGreen, "Green lane should use systemGreen")

        // Purple lane
        let purpleColor = GameplayScene.staticColor(for: .purple)
        XCTAssertEqual(purpleColor, .systemPurple, "Purple lane should use systemPurple")
    }

    // MARK: - Lane Order Tests

    func testGameplaySceneInitializesWithCanonicalLaneOrder() {
        // Create a chart with notes in non-canonical order
        let notes: [NoteEvent] = [
            NoteEvent(lane: .purple, time: 0.0),  // Lane 4 first
            NoteEvent(lane: .red, time: 1.0),     // Lane 0 second
            NoteEvent(lane: .green, time: 2.0),   // Lane 3 third
            NoteEvent(lane: .yellow, time: 3.0),  // Lane 1 fourth
            NoteEvent(lane: .blue, time: 4.0),    // Lane 2 fifth
        ]
        let chart = Chart(notes: notes, title: "Non-Canonical Order")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        // Despite appearance order, lanes should be in canonical order
        let laneOrder = scene._testLaneOrder
        XCTAssertEqual(laneOrder.count, 5, "Should have 5 lanes")
        XCTAssertEqual(laneOrder.map { $0.sourceLane }, [.red, .yellow, .blue, .green, .purple],
                       "Lanes should be in canonical order: red(0), yellow(1), blue(2), green(3), purple(4)")
    }

    func testGameplaySceneRespectsLaneDisplayOrder() {
        // Create test charts with different note orders
        let testCases: [(notes: [NoteEvent], expectedOrder: [Lane])] = [
            // All lanes present
            (notes: [
                NoteEvent(lane: .red, time: 0.0),
                NoteEvent(lane: .yellow, time: 1.0),
                NoteEvent(lane: .blue, time: 2.0),
                NoteEvent(lane: .green, time: 3.0),
                NoteEvent(lane: .purple, time: 4.0),
            ], expectedOrder: [.red, .yellow, .blue, .green, .purple]),

            // Reverse order
            (notes: [
                NoteEvent(lane: .purple, time: 0.0),
                NoteEvent(lane: .green, time: 1.0),
                NoteEvent(lane: .blue, time: 2.0),
                NoteEvent(lane: .yellow, time: 3.0),
                NoteEvent(lane: .red, time: 4.0),
            ], expectedOrder: [.red, .yellow, .blue, .green, .purple]),

            // Random order
            (notes: [
                NoteEvent(lane: .green, time: 0.0),
                NoteEvent(lane: .purple, time: 1.0),
                NoteEvent(lane: .yellow, time: 2.0),
            ], expectedOrder: [.yellow, .green, .purple]),
        ]

        for (index, testCase) in testCases.enumerated() {
            let chart = Chart(notes: testCase.notes, title: "Test \(index)")
            let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())
            scene.updateVisibleNotes(testCase.notes)
            let laneOrder = scene._testLaneOrder

            XCTAssertEqual(laneOrder.map { $0.sourceLane }, testCase.expectedOrder,
                           "Test case \(index): lanes should be in canonical order regardless of input order")
        }
    }

    // MARK: - Lane Index Mapping Tests

    func testLaneIndexMappingIsConsistent() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat"),
            NoteEvent(lane: .blue, time: 2.0, label: "Tom"),
            NoteEvent(lane: .green, time: 3.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 4.0, label: "Kick"),
        ]
        let chart = Chart(notes: notes, title: "Full Kit")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let laneIndexByID = scene._testLaneIndexByID

        // Verify each lane has a consistent index
        XCTAssertEqual(laneIndexByID["red"], 0, "Red lane should be at index 0")
        XCTAssertEqual(laneIndexByID["yellow"], 1, "Yellow lane should be at index 1")
        XCTAssertEqual(laneIndexByID["blue"], 2, "Blue lane should be at index 2")
        XCTAssertEqual(laneIndexByID["green"], 3, "Green lane should be at index 3")
        XCTAssertEqual(laneIndexByID["purple"], 4, "Purple lane should be at index 4")
    }

    // MARK: - Lane Label and Key Tests

    func testLaneLabelAndKeyAccuracy() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat Closed"),
            NoteEvent(lane: .blue, time: 2.0, label: "Tom High"),
            NoteEvent(lane: .green, time: 3.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 4.0, label: "Kick"),
        ]
        let chart = Chart(notes: notes, title: "Full Kit")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let laneOrder = scene._testLaneOrder

        // Verify labels and keys in canonical order
        let expectedData: [(label: String, key: String)] = [
            ("Snare", "D"),
            ("Hi-Hat Closed", "F"),
            ("Tom High", "J"),
            ("Crash", "K"),
            ("Kick", "␣"),
        ]

        for (index, expected) in expectedData.enumerated() {
            XCTAssertEqual(laneOrder[index].label, expected.label, "Lane \(index) label should be \(expected.label)")
            XCTAssertEqual(laneOrder[index].presentationKeyLabel, expected.key, "Lane \(index) key should be \(expected.key)")
        }
    }

    // MARK: - Full Rendering Pipeline Test

    func testFullRenderingPipelineWithAllLanes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5),
            NoteEvent(lane: .yellow, time: 1.0),
            NoteEvent(lane: .blue, time: 1.5),
            NoteEvent(lane: .green, time: 2.0),
            NoteEvent(lane: .purple, time: 2.5),
        ]
        let chart = Chart(notes: notes, title: "Full Pipeline Test")
        let scene = GameplayScene(chart: chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(notes)

        let laneOrder = scene._testLaneOrder
        let laneIndexByID = scene._testLaneIndexByID

        // Verify all lanes are present
        XCTAssertEqual(laneOrder.count, 5, "Should have 5 lanes")

        // Verify each lane in correct canonical order with correct properties
        let expectedLanes: [(Lane, String)] = [
            (.red, "red"), (.yellow, "yellow"), (.blue, "blue"), (.green, "green"), (.purple, "purple")
        ]

        for (index, (expectedLane, expectedID)) in expectedLanes.enumerated() {
            XCTAssertEqual(laneOrder[index].sourceLane, expectedLane, "Lane \(index) should be \(expectedLane)")
            XCTAssertEqual(laneOrder[index].id, expectedID, "Lane \(index) ID should be \(expectedID)")
            XCTAssertEqual(laneIndexByID[expectedID], index, "Lane \(expectedID) should be at index \(index)")

            // Verify color is correct
            let color = GameplayScene.staticColor(for: expectedLane)
            switch expectedLane {
            case .red:
                XCTAssertEqual(color, .systemRed)
            case .yellow:
                XCTAssertEqual(color, .systemYellow)
            case .blue:
                XCTAssertEqual(color, .systemBlue)
            case .green:
                XCTAssertEqual(color, .systemGreen)
            case .purple:
                XCTAssertEqual(color, .systemPurple)
            }
        }
    }
}

// MARK: - Test Helpers

extension GameplayScene {
    static func staticColor(for lane: Lane) -> NSColor {
        switch lane {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .purple: return .systemPurple
        }
    }
}
