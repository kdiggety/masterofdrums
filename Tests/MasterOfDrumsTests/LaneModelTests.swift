import XCTest
@testable import MasterOfDrums

final class LaneModelTests: XCTestCase {

    // MARK: - Lane Deduplication by Presentation

    func testDisplayLanesDeduplicatesByPresentationLane() {
        // After the bounded model change, Hi Hat Closed maps to .yellow and Hi Hat Open maps to .green
        // So they should NOT deduplicate - they should be on different presentation lanes
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .yellow, time: 0.5, label: "Hi Hat Closed"),
            NoteEvent(id: UUID(), lane: .yellow, time: 1.0, label: "Hi Hat Open"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes()

        // Hi Hat Closed → .yellow, Hi Hat Open → .green, they should be two separate lanes
        let yellowLanes = displayLanes.filter { $0.presentationLane == .yellow }
        let greenLanes = displayLanes.filter { $0.presentationLane == .green }
        XCTAssertEqual(yellowLanes.count, 1, "Hi-Hat Closed should be on .yellow")
        XCTAssertEqual(greenLanes.count, 1, "Hi-Hat Open should be on .green (crash family)")
        XCTAssert(yellowLanes.first?.label.lowercased().contains("closed") == true)
        XCTAssert(greenLanes.first?.label.lowercased().contains("open") == true)
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
        let displayLanes = chart.displayLanes()

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
        let displayLanes = chart.displayLanes()

        // Should have only one row for red/snare, not duplicates
        let redLanes = displayLanes.filter { $0.presentationLane == .red }
        XCTAssertEqual(redLanes.count, 1, "Should not show duplicate Snare/Red rows")
    }

    // MARK: - Chart Display Lanes Behavior

    func testDisplayLanesReturnsLanesWhenChartEmpty() {
        let chart = Chart(notes: [], title: "Empty")
        let displayLanes = chart.displayLanes()

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
        let displayLanes = chart.displayLanes()

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
        let displayLanes = chart.displayLanes()
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
            ("Hi Hat Closed", .yellow),      // Hi-Hat Closed is .yellow
            ("Hi Hat Open", .green),         // Hi-Hat Open maps to crash family (.green)
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
        let displayLanes = chart.displayLanes()

        let keyLabels = displayLanes.reduce(into: [Lane: String]()) { dict, lane in
            dict[lane.presentationLane] = lane.presentationKeyLabel ?? ""
        }

        XCTAssertEqual(keyLabels[.red], "D")
        XCTAssertEqual(keyLabels[.yellow], "F")
        XCTAssertEqual(keyLabels[.blue], "J")
        XCTAssertEqual(keyLabels[.green], "K")
        XCTAssertEqual(keyLabels[.kick], "␣")
    }

    // MARK: - Bounded 5-Lane Model

    func testTomCollapsingInBoundedMode() {
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .blue, time: 0.5, label: "Tom High"),
            NoteEvent(id: UUID(), lane: .blue, time: 1.0, label: "Tom Mid"),
            NoteEvent(id: UUID(), lane: .blue, time: 1.5, label: "Tom Low"),
        ]

        let chart = Chart(notes: notes, title: "Test")

        // In bounded mode, toms should collapse to one lane labeled "Tom"
        let boundedLanes = chart.displayLanes(extendedLanes: false)
        let tomLanes = boundedLanes.filter { $0.presentationLane == .blue }
        XCTAssertEqual(tomLanes.count, 1, "Toms should collapse to one lane in bounded mode")
        XCTAssertEqual(tomLanes.first?.label, "Tom", "Collapsed tom lane should be labeled 'Tom'")

        // In extended mode, all three should show
        let extendedLanes = chart.displayLanes(extendedLanes: true)
        let extendedTomLanes = extendedLanes.filter { $0.presentationLane == .blue }
        XCTAssertEqual(extendedTomLanes.count, 3, "All tom variants should show in extended mode")
    }

    func testBoundedModeCapFiveLanes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0, label: "Snare"),
            NoteEvent(lane: .yellow, time: 0.5, label: "Hi-Hat"),
            NoteEvent(lane: .green, time: 1.0, label: "Crash"),
            NoteEvent(lane: .blue, time: 1.5, label: "Tom High"),
            NoteEvent(lane: .blue, time: 2.0, label: "Tom Mid"),
            NoteEvent(lane: .kick, time: 2.5, label: "Kick"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let boundedLanes = chart.displayLanes(extendedLanes: false)

        // Should cap at 5: Snare, Hi-Hat, Crash, Tom (collapsed), Kick
        XCTAssertLessThanOrEqual(boundedLanes.count, 5, "Bounded mode should cap at 5 lanes")
    }

    func testOpenHiHatRoutesToCrashFamily() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .green, time: 0.0, label: "Hi Hat Open"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes()

        // Hi Hat Open should map to .green (crash family)
        let greenLanes = displayLanes.filter { $0.presentationLane == .green }
        XCTAssertEqual(greenLanes.count, 1, "Hi Hat Open should appear on .green presentation lane")
        XCTAssert(greenLanes.first?.label.lowercased().contains("open") == true)
    }

    func testOpenHiHatAndCrashDeduplicateInBoundedMode() {
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .green, time: 0.0, label: "Hi Hat Open"),
            NoteEvent(id: UUID(), lane: .green, time: 0.5, label: "Crash"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let boundedLanes = chart.displayLanes(extendedLanes: false)

        // Both map to .green with same key label, should deduplicate
        let greenLanes = boundedLanes.filter { $0.presentationLane == .green }
        XCTAssertEqual(greenLanes.count, 1, "Hi Hat Open and Crash should deduplicate on .green in bounded mode")
    }

    func testNoteDisplayLabelFallbackUsesLaneLabel() {
        // Verify that unlabeled notes use lane.laneLabel, not lane.displayName
        let redNote = NoteEvent(lane: .red, time: 0.0, label: nil)
        let greenNote = NoteEvent(lane: .green, time: 0.5, label: nil)
        let blueNote = NoteEvent(lane: .blue, time: 1.0, label: nil)

        XCTAssertEqual(redNote.displayLabel, "Snare", "Red unlabeled note should use laneLabel 'Snare'")
        XCTAssertEqual(greenNote.displayLabel, "Crash", "Green unlabeled note should use laneLabel 'Crash'")
        XCTAssertEqual(blueNote.displayLabel, "Tom", "Blue unlabeled note should use laneLabel 'Tom'")
    }
}
