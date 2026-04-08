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
}
