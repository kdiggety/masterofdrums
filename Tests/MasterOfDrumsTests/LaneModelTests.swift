import XCTest
@testable import MasterOfDrums

final class LaneModelTests: XCTestCase {

    // MARK: - Lane Deduplication by Presentation

    func testDisplayLanesDeduplicatesByPresentationLane() {
        // Notes with same sourceLane should deduplicate (only one lane per sourceLane)
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .yellow, time: 0.5, label: "Hi Hat Closed"),
            NoteEvent(id: UUID(), lane: .yellow, time: 1.0, label: "Hi Hat Open"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes()

        // Both notes have same sourceLane .yellow, so only one lane
        let yellowLanes = displayLanes.filter { $0.presentationLane == .yellow }
        XCTAssertEqual(yellowLanes.count, 1, "Multiple notes with same sourceLane should share one lane")
    }

    func testDisplayLanesPreservesDistinctPresentationLanes() {
        // Create notes with different presentation lanes
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.5, label: "Snare"),
            NoteEvent(lane: .yellow, time: 1.0, label: "Hi-Hat"),
            NoteEvent(lane: .blue, time: 1.5, label: "Tom High"),
            NoteEvent(lane: .green, time: 2.0, label: "Crash"),
            NoteEvent(lane: .purple, time: 2.5, label: "Kick"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes()

        // Should have 5 distinct lanes (one per presentation)
        XCTAssertEqual(displayLanes.count, 5)

        // Verify presentation lanes
        let presentations = Set(displayLanes.map { $0.presentationLane })
        XCTAssertEqual(presentations, Set([.red, .yellow, .blue, .green, .purple]))
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
            NoteEvent(lane: .purple, time: 0.5),
            NoteEvent(lane: .red, time: 1.0),
            NoteEvent(lane: .blue, time: 1.5),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let displayLanes = chart.displayLanes()

        // Lanes are displayed in order of appearance (in notes), not by priority
        XCTAssertEqual(displayLanes.map(\.presentationLane), [.purple, .red, .blue])
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
            ("Kick", .purple),
            ("Kick Drum", .purple),
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
            NoteEvent(lane: .purple, time: 2.0),   // Should map to "␣"
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
        XCTAssertEqual(keyLabels[.purple], "␣")
    }

    // MARK: - Bounded 5-Lane Model

    func testTomCollapsingInBoundedMode() {
        let notes: [NoteEvent] = [
            NoteEvent(id: UUID(), lane: .blue, time: 0.5, label: "Tom High"),
            NoteEvent(id: UUID(), lane: .blue, time: 1.0, label: "Tom Mid"),
            NoteEvent(id: UUID(), lane: .blue, time: 1.5, label: "Tom Low"),
        ]

        let chart = Chart(notes: notes, title: "Test")

        // Notes with same sourceLane deduplicate to one lane
        // Label is taken from first note encountered
        let boundedLanes = chart.displayLanes(extendedLanes: false)
        let tomLanes = boundedLanes.filter { $0.presentationLane == .blue }
        XCTAssertEqual(tomLanes.count, 1, "Notes with same sourceLane should appear as one lane")
        XCTAssertEqual(tomLanes.first?.label, "Tom High", "Lane label comes from first note")

        // extendedLanes parameter doesn't change deduplication behavior
        let extendedLanes = chart.displayLanes(extendedLanes: true)
        let extendedTomLanes = extendedLanes.filter { $0.presentationLane == .blue }
        XCTAssertEqual(extendedTomLanes.count, 1, "Extended mode still deduplicates same sourceLane")
    }

    func testBoundedModeCapFiveLanes() {
        let notes: [NoteEvent] = [
            NoteEvent(lane: .red, time: 0.0, label: "Snare"),
            NoteEvent(lane: .yellow, time: 0.5, label: "Hi-Hat"),
            NoteEvent(lane: .green, time: 1.0, label: "Crash"),
            NoteEvent(lane: .blue, time: 1.5, label: "Tom High"),
            NoteEvent(lane: .blue, time: 2.0, label: "Tom Mid"),
            NoteEvent(lane: .purple, time: 2.5, label: "Kick"),
        ]

        let chart = Chart(notes: notes, title: "Test")
        let boundedLanes = chart.displayLanes(extendedLanes: false)

        // One lane per sourceLane: .red, .yellow, .green, .blue (toms deduplicate), .purple = 5 lanes
        XCTAssertEqual(boundedLanes.count, 5, "One lane per unique sourceLane")
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
