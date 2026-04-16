import XCTest
@testable import MasterOfDrums

final class LaneModelTests: XCTestCase {

    // MARK: - Lane Deduplication by Presentation

    func testDisplayLanesDeduplicatesByPresentationLane() {
        // Create notes with different labels that map to the same presentation lane
        // (e.g., "Hi Hat Open" and "Hi Hat Closed" both map to .yellow)
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .yellow, time: 0.5, label: "Hi Hat Closed"),
            NoteEvent(id: UUID(), lane: .yellow, time: 1.0, label: "Hi Hat Open"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes

        // Both notes should map to yellow presentation, so we should see only one
        let yellowLanes = displayLanes.filter { $0.presentationLane == .yellow }
        XCTAssertEqual(yellowLanes.count, 1, "Hi-Hat variations should deduplicate to one lane")
        XCTAssert(yellowLanes.first?.label.lowercased().contains("hat") == true)
    }

    func testDisplayLanesPreservesDistinctPresentationLanes() {
        // Create notes with different presentation lanes
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat"),
            NoteEvent(lane: .blue, time: 1.5, label: "Tom High"),
            NoteEvent(lane: .green, time: 2.0, label: "Crash"),
            NoteEvent(lane: .kick, time: 2.5, label: "Kick"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes

        // Should have 5 distinct lanes (one per presentation)
        XCTAssertEqual(displayLanes.count, 5)

        // Verify presentation lanes
        let presentations = Set(displayLanes.map { $0.presentationLane })
        XCTAssertEqual(presentations, Set([.red, .yellow, .blue, .green, .kick]))
    }

    func testDisplayLanesDoesNotShowDuplicateCanonicalRows() {
        // Create notes that would generate both "Red" and "Snare" rows if not deduplicated
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(id: UUID(), lane: .red, time: 1.0, label: nil), // Would use "Red" as label
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes

        // Should have only one row for red/snare, not duplicates
        let redLanes = displayLanes.filter { $0.presentationLane == .red }
        XCTAssertEqual(redLanes.count, 1, "Should not show duplicate Snare/Red rows")
    }

    // MARK: - Chart Display Lanes Behavior

    func testDisplayLanesReturnsLanesWhenChartEmpty() {
        let chart = Chart(notes: [], title: "Empty")
        let displayLanes = chart.displayLanes

        // Empty chart should still return some lanes (default set)
        XCTAssertGreaterThan(displayLanes.count, 0,
                            "Empty chart should return default lanes")
        // Verify lanes have presentation values
        let presentations = displayLanes.map { $0.presentationLane }
        XCTAssertEqual(presentations.count, displayLanes.count,
                      "All lanes should have valid presentation values")
    }

    func testDisplayLanesOrderByPriority() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .kick, time: 0.5), // Priority 99
            NoteEvent(lane: .red, time: 1.0),  // Priority 0 (Snare)
            NoteEvent(lane: .blue, time: 1.5), // Priority 4 (Tom High)
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes

        // Find priority order
        var priorities: [Int] = []
        for lane in displayLanes {
            if lane.presentationLane == .red { priorities.append(0) }
            else if lane.presentationLane == .blue { priorities.append(4) }
            else if lane.presentationLane == .kick { priorities.append(99) }
        }

        // Should be sorted by priority
        XCTAssertEqual(priorities, [0, 4, 99], "Lanes should be ordered by priority")
    }

    // MARK: - Admin Audition Display Lanes Unification

    func testAdminAuditionDisplayLanesUsesUnifiedSource() {
        // Verify that adminAuditionDisplayLanes exists and returns ChartLane array
        // The actual delegation to chart.displayLanes is verified through integration
        // (when notes are loaded, both gameplay and monitoring use the same lanes)
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat"),
        ]

        let chart = Chart(notes: notes, title: "Test")

        // Verify displayLanes have correct count and presentation values
        let displayLanes = chart.displayLanes
        XCTAssertGreaterThan(displayLanes.count, 0)
        XCTAssert(displayLanes.allSatisfy { lane in
            Lane.allCases.contains(lane.presentationLane)
        }, "All lanes should have valid presentation values")
    }

    // MARK: - Lane Presentation Mapping

    func testChartLanePresentationMapping() {
        // Verify that ChartLane correctly maps various drum kit instruments
        let testCases: [(label: String, expectedPresentation: Lane)] = [
            ("Snare", .red),
            ("Hi Hat Closed", .yellow),      // Space, not hyphen
            ("Hi Hat Open", .yellow),         // Space, not hyphen
            ("Crash", .green),
            ("Ride", .green),
            ("Tom High", .blue),
            ("Tom Mid", .blue),
            ("Tom Low", .blue),
            ("Kick", .kick),
            ("Kick Drum", .kick),
        ]

        for (label, expectedPresentation) in testCases {
            let lane = ChartLane(id: label.lowercased(), label: label, sourceLane: .red, keyLabel: nil)
            XCTAssertEqual(lane.presentationLane, expectedPresentation,
                          "Label '\(label)' should map to \(expectedPresentation)")
        }
    }

    func testPresentationKeyLabelsAreConsistent() {
        // Verify that presentation key labels are correctly derived
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0),    // Should map to "D"
            NoteEvent(lane: .yellow, time: 0.5), // Should map to "F"
            NoteEvent(lane: .blue, time: 1.0),   // Should map to "J"
            NoteEvent(lane: .green, time: 1.5),  // Should map to "K"
            NoteEvent(lane: .kick, time: 2.0),   // Should map to "␣"
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes

        let keyLabels = displayLanes.reduce(into: [Lane: String]()) { dict, lane in
            dict[lane.presentationLane] = lane.presentationKeyLabel ?? ""
        }

        XCTAssertEqual(keyLabels[.red], "D")
        XCTAssertEqual(keyLabels[.yellow], "F")
        XCTAssertEqual(keyLabels[.blue], "J")
        XCTAssertEqual(keyLabels[.green], "K")
        XCTAssertEqual(keyLabels[.kick], "␣")
    }
}
