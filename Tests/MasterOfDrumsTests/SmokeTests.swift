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
        XCTAssertEqual(loaded.chart.notes.map(\.lane), [.purple, .red, .yellow, .blue])
        XCTAssertEqual(loaded.chart.notes.map(\.displayLabel), ["Kick", "Snare", "Hihat Closed", "Tom High"])
        XCTAssertEqual(loaded.timing?.source, "generated")
        XCTAssertEqual(loaded.timing?.ticksPerBeat, 480)
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

        let expectedLaneCounts: [Lane: Int] = [.purple: 3, .red: 1, .yellow: 1]
        XCTAssertEqual(scene.debugVisibleLaneCounts(), expectedLaneCounts)
    }
}
