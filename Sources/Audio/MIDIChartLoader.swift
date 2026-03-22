import Foundation

struct MIDIChartLoader {
    struct LoadedChartSummary {
        let sourceName: String
        let bytes: Int
        let status: String
    }

    func inspectFile(at url: URL) throws -> LoadedChartSummary {
        let data = try Data(contentsOf: url)
        return LoadedChartSummary(
            sourceName: url.lastPathComponent,
            bytes: data.count,
            status: "MIDI import scaffold ready"
        )
    }
}
