import XCTest
@testable import MasterOfDrums

final class SmokeTests: XCTestCase {
    func testPackageLoads() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testChartFileStoreLoadsPipelineBaseChartNotes() throws {
        let json = """
        {
          "chart": {
            "notes": [
              {"noteID":"00000000-0000-0000-0000-000000000001","lane":"kick","startSeconds":0.02},
              {"noteID":"00000000-0000-0000-0000-000000000002","lane":"snare","startSeconds":0.62},
              {"noteID":"00000000-0000-0000-0000-000000000003","lane":"hihat_closed","startSeconds":1.22},
              {"noteID":"00000000-0000-0000-0000-000000000004","lane":"tom_high","startSeconds":1.82}
            ]
          },
          "timingContractVersion": "0.1.0",
          "timing": {
            "bpm": 120,
            "offsetSeconds": 0,
            "ticksPerBeat": 480,
            "timeSignature": {"numerator": 4, "denominator": 4},
            "source": "generated"
          },
          "source": {
            "sourceAudio": "/tmp/Lecrazy.mp3",
            "title": "Lecrazy"
          }
        }
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-base-chart-test.modchart.json")
        try json.data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let loaded = try ChartFileStore().loadChart(from: tempURL)

        XCTAssertEqual(loaded.chart.title, "Lecrazy")
        XCTAssertEqual(loaded.chart.notes.count, 4)
        XCTAssertEqual(loaded.chart.notes.map(\.lane), [.kick, .red, .yellow, .blue])
        XCTAssertEqual(loaded.chart.notes.map(\.displayLabel), ["Kick", "Snare", "Hihat Closed", "Tom High"])
        XCTAssertEqual(loaded.timing?.source, "generated")
        XCTAssertEqual(loaded.timing?.ticksPerBeat, 480)
    }

    /// The midi_to_modchart.py converter emits the legacy format: top-level "notes" array
    /// with integer lane values (0–4) matching Lane.rawValue. Verify ChartFileStore loads it.
    @MainActor
    func testChartFileStoreLoadsMIDIImportFormat() throws {
        let json = """
        {
          "title": "Test Drums",
          "bpm": 120.0,
          "timingContractVersion": "0.1.0",
          "timing": {
            "bpm": 120.0,
            "offsetSeconds": 0,
            "ticksPerBeat": 480,
            "timeSignature": {"numerator": 4, "denominator": 4},
            "source": "midi_import"
          },
          "timelineDuration": 4.0,
          "notes": [
            {"id": "00000000-0000-0000-0000-000000000001", "lane": 4, "time": 0.0,  "label": "Kick"},
            {"id": "00000000-0000-0000-0000-000000000002", "lane": 1, "time": 0.25, "label": "HiHat Closed"},
            {"id": "00000000-0000-0000-0000-000000000003", "lane": 0, "time": 0.5,  "label": "Snare"},
            {"id": "00000000-0000-0000-0000-000000000004", "lane": 2, "time": 1.0,  "label": "Tom High"},
            {"id": "00000000-0000-0000-0000-000000000005", "lane": 3, "time": 1.5,  "label": "Tom Low"}
          ],
          "sections": [],
          "metadata": {
            "sourceMIDI": "test.mid",
            "format": 0,
            "trackCount": 1,
            "tempoChanges": 1,
            "unmappedMIDINotes": []
          }
        }
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("midi-import-format-test.modchart.json")
        try json.data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let loaded = try ChartFileStore().loadChart(from: tempURL)

        XCTAssertEqual(loaded.chart.title, "Test Drums")
        XCTAssertEqual(loaded.chart.notes.count, 5)
        XCTAssertEqual(loaded.timing?.source, "midi_import")
        XCTAssertEqual(loaded.timing?.ticksPerBeat, 480)

        // Notes are sorted by time: kick(0.0), hihat(0.25), snare(0.5), tomHigh(1.0), tomLow(1.5)
        XCTAssertEqual(loaded.chart.notes.map(\.lane), [.kick, .yellow, .red, .blue, .green])

        // Labels from the converter are preserved in the legacy note format.
        let byLane = Dictionary(grouping: loaded.chart.notes, by: \.lane)
        XCTAssertEqual(byLane[.kick]?.first?.label, "Kick")
        XCTAssertEqual(byLane[.red]?.first?.label, "Snare")
        XCTAssertEqual(byLane[.yellow]?.first?.label, "HiHat Closed")
        XCTAssertEqual(byLane[.blue]?.first?.label, "Tom High")
        XCTAssertEqual(byLane[.green]?.first?.label, "Tom Low")
    }

    /// Verify that newly-mapped GM notes (Hand Clap, Cowbell, Ride Bell, Tambourine)
    /// survive a round-trip through the MIDI converter → JSON → ChartFileStore.
    @MainActor
    func testChartFileStoreLoadsNewlyMappedGMNotes() throws {
        // Hand Clap (GM 39) → lane 0 / red
        // Cowbell (GM 56)    → lane 1 / yellow
        // Ride Bell (GM 53)  → lane 1 / yellow
        // Tambourine (GM 54) → lane 1 / yellow
        let json = """
        {
          "title": "GM Coverage Test",
          "bpm": 120.0,
          "timingContractVersion": "0.1.0",
          "timing": {
            "bpm": 120.0,
            "offsetSeconds": 0,
            "ticksPerBeat": 480,
            "timeSignature": {"numerator": 4, "denominator": 4},
            "source": "midi_import"
          },
          "timelineDuration": 4.0,
          "notes": [
            {"id": "00000000-0000-0000-0000-000000000001", "lane": 0, "time": 0.0,  "label": "Hand Clap"},
            {"id": "00000000-0000-0000-0000-000000000002", "lane": 1, "time": 0.5,  "label": "Cowbell"},
            {"id": "00000000-0000-0000-0000-000000000003", "lane": 1, "time": 1.0,  "label": "Ride Bell"},
            {"id": "00000000-0000-0000-0000-000000000004", "lane": 1, "time": 1.5,  "label": "Tambourine"}
          ],
          "sections": [],
          "metadata": {
            "sourceMIDI": "gm-coverage.mid",
            "format": 0,
            "trackCount": 1,
            "tempoChanges": 1,
            "unmappedMIDINotes": []
          }
        }
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("midi-gm-coverage-test.modchart.json")
        try json.data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let loaded = try ChartFileStore().loadChart(from: tempURL)

        XCTAssertEqual(loaded.chart.notes.count, 4)
        // Notes sorted by time: hand clap, cowbell, ride bell, tambourine
        XCTAssertEqual(loaded.chart.notes[0].lane, .red)
        XCTAssertEqual(loaded.chart.notes[0].label, "Hand Clap")
        XCTAssertEqual(loaded.chart.notes[1].lane, .yellow)
        XCTAssertEqual(loaded.chart.notes[1].label, "Cowbell")
        XCTAssertEqual(loaded.chart.notes[2].lane, .yellow)
        XCTAssertEqual(loaded.chart.notes[2].label, "Ride Bell")
        XCTAssertEqual(loaded.chart.notes[3].lane, .yellow)
        XCTAssertEqual(loaded.chart.notes[3].label, "Tambourine")
    }

    @MainActor
    func testImportedRecordedNoteCountsMatchVisibleLaneEvents() throws {
        let json = """
        {
          "chart": {
            "notes": [
              {"noteID":"00000000-0000-0000-0000-000000000011","lane":"kick","startSeconds":0.02},
              {"noteID":"00000000-0000-0000-0000-000000000012","lane":"kick","startSeconds":0.18},
              {"noteID":"00000000-0000-0000-0000-000000000013","lane":"kick","startSeconds":0.34},
              {"noteID":"00000000-0000-0000-0000-000000000014","lane":"snare","startSeconds":0.62},
              {"noteID":"00000000-0000-0000-0000-000000000015","lane":"hihat_closed","startSeconds":0.74}
            ]
          },
          "timingContractVersion": "0.1.0",
          "timing": {
            "bpm": 120,
            "offsetSeconds": 0,
            "ticksPerBeat": 480,
            "timeSignature": {"numerator": 4, "denominator": 4},
            "source": "generated"
          },
          "source": {
            "sourceAudio": "/tmp/motion-trap.mp3",
            "title": "Motion Trap"
          }
        }
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-visible-note-parity-test.modchart.json")
        try json.data(using: .utf8)!.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let loaded = try ChartFileStore().loadChart(from: tempURL)
        let scene = GameplayScene(chart: loaded.chart, keyboardInputDevice: KeyboardInputDevice())

        scene.updateVisibleNotes(loaded.chart.notes)

        XCTAssertEqual(loaded.chart.notes.count, 5)
        XCTAssertEqual(scene.debugVisibleNoteCount(), loaded.chart.notes.count)
        XCTAssertEqual(scene.debugRenderedNoteNodeCount(), loaded.chart.notes.count)

        let expectedLaneCounts: [Lane: Int] = [.kick: 3, .red: 1, .yellow: 1]
        XCTAssertEqual(scene.debugVisibleLaneCounts(), expectedLaneCounts)
    }
}
