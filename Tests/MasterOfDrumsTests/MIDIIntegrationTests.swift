import XCTest
@testable import MasterOfDrums

@MainActor
final class MIDIIntegrationTests: XCTestCase {
    let midiDir = URL(fileURLWithPath: "/Users/klewisjr/Development/MacOS/masterofdrums-pipeline/Tests/PipelineRuntimeTests/Fixtures/midi")
    let testOutputDir = URL(fileURLWithPath: "/tmp/midi-test-charts")

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: testOutputDir, withIntermediateDirectories: true)
    }

    /// Convert MIDI file to modchart.json using midi_to_modchart.py
    func convertMIDIToChart(_ midiFilename: String) throws -> URL {
        let midiPath = midiDir.appendingPathComponent(midiFilename)
        let chartPath = testOutputDir.appendingPathComponent(midiFilename.replacingOccurrences(of: ".mid", with: ".modchart.json"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            "/Users/klewisjr/Development/MacOS/masterofdrums/Tools/midi_to_modchart.py",
            midiPath.path,
            chartPath.path
        ]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let error = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "MIDIConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
        }

        return chartPath
    }

    // MARK: - Production MIDI File Lane Coverage

    func testKenChartFillsExpectedLanes() throws {
        let chartUrl = try convertMIDIToChart("im-just-ken-ryan-gosling-from-barbie.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        // Ken should fill: kick, snare, tom_high, crash/ride (4 lanes)
        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 4, "Ken should have 4 lanes")
        XCTAssertTrue(lanes.contains(.purple), "Should have kick")
        XCTAssertTrue(lanes.contains(.red), "Should have snare")
        XCTAssertTrue(lanes.contains(.blue), "Should have tom_high")
        XCTAssertTrue(lanes.contains(.green), "Should have crash/ride/tom")
        XCTAssertFalse(lanes.contains(.yellow), "Ken should NOT have hihat (verified in MIDI)")
    }

    func testDragulaChartFillsExpectedLanes() throws {
        let chartUrl = try convertMIDIToChart("rob-zombie-dragula.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        // Dragula should fill: kick, snare, hihat, crash/ride (4 lanes)
        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 4, "Dragula should have 4 lanes")
        XCTAssertTrue(lanes.contains(.purple), "Should have kick")
        XCTAssertTrue(lanes.contains(.red), "Should have snare")
        XCTAssertTrue(lanes.contains(.yellow), "Should have hihat")
        XCTAssertTrue(lanes.contains(.green), "Should have crash/ride")
    }

    func testProductionMIDIFilesHaveConsistentNoteCount() throws {
        let testFiles: [(filename: String, expectedNoteCount: ClosedRange<Int>)] = [
            ("im-just-ken-ryan-gosling-from-barbie.mid", 180...220),      // ~199
            ("killing-me-softly-arr-kaden-connell.mid", 1000...1200),     // ~1104
            ("rob-zombie-dragula.mid", 1400...1550),                      // ~1480
            ("the-real-slim-shady-eminem.mid", 70...100),                 // ~84
            ("timbaland-ft-onerepublic-apologize-committed-cover.mid", 350...420),  // ~386
            ("blinding-lights-the-weeknd.mid", 1100...1300),              // ~1212
            ("kill-bill-sza-with-drum-bass.mid", 500...600),              // ~555
        ]

        let chartStore = ChartFileStore()
        for (filename, expectedRange) in testFiles {
            let chartUrl = try convertMIDIToChart(filename)
            let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)
            XCTAssertTrue(
                expectedRange.contains(chart.notes.count),
                "\(filename): expected \(expectedRange) notes, got \(chart.notes.count)"
            )
        }
    }

    // MARK: - Lane Distribution Validation

    func testDragulaHasHeavyHiHatUsage() throws {
        let chartUrl = try convertMIDIToChart("rob-zombie-dragula.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        let hihatNotes = chart.notes.filter { $0.lane == .yellow }
        let hihatPercentage = Double(hihatNotes.count) / Double(chart.notes.count)

        // Dragula uses hihat heavily (expect >30%)
        XCTAssertGreaterThan(hihatPercentage, 0.30,
                            "Dragula should have heavy hihat usage (>30%), got \(Int(hihatPercentage * 100))%")
    }

    func testRealSlimShadyHasMinimalLaneUsage() throws {
        let chartUrl = try convertMIDIToChart("the-real-slim-shady-eminem.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        // Real Slim Shady is minimal (only 3 lanes: kick, snare, hihat)
        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 3, "Real Slim Shady should use minimal lanes")
        XCTAssertTrue(lanes.contains(.purple), "Should have kick")
        XCTAssertTrue(lanes.contains(.red), "Should have snare")
        XCTAssertTrue(lanes.contains(.yellow), "Should have hihat")
    }

    // MARK: - Synthetic Test Files

    func testSyntheticFullKitFillsAllLanes() throws {
        let chartUrl = try convertMIDIToChart("test-full-kit.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 5, "Synthetic full-kit should hit all 5 lanes")
        XCTAssertEqual(lanes, Set([.purple, .red, .yellow, .blue, .green]), "Should have all lanes")
    }

    func testSyntheticMonophonicFilesHaveSingleLane() throws {
        let monoFiles = ["test-kick-only.mid", "test-tom-high.mid", "test-tom-mid.mid", "test-tom-low.mid"]

        let chartStore = ChartFileStore()
        for filename in monoFiles {
            let chartUrl = try convertMIDIToChart(filename)
            let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)
            let lanes = chart.displayLanes()

            XCTAssertEqual(lanes.count, 1, "\(filename) should be monophonic (1 lane)")
        }
    }

    // MARK: - MIDI Parsing Edge Cases

    func testZeroVelocityNotesFiltered() throws {
        let chartUrl = try convertMIDIToChart("test-zero-velocity.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        // Kick has velocity 0 (filtered), only snare remains
        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 1, "Zero-velocity kick should be filtered")
        XCTAssertEqual(lanes.first, .red, "Only snare should remain")
    }

    func testWrongChannelNotesFiltered() throws {
        let chartUrl = try convertMIDIToChart("test-wrong-channel.mid")
        let chartStore = ChartFileStore()
        let (chart, _, _, _) = try chartStore.loadChart(from: chartUrl)

        // File has melody on channel 0 (ignored) and drums on channel 9 (kept)
        let lanes = Set(chart.displayLanes().map { $0.sourceLane })
        XCTAssertEqual(lanes.count, 2, "Only channel 9 notes should be captured")
        XCTAssertTrue(lanes.contains(.purple), "Should have kick")
        XCTAssertTrue(lanes.contains(.red), "Should have snare")
    }
}
