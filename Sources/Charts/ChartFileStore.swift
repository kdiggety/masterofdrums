import Foundation
import AppKit
import UniformTypeIdentifiers

struct ChartDocument: Codable {
    struct Note: Codable {
        let lane: Int
        let time: Double
    }

    struct Section: Codable {
        let id: UUID?
        let name: String
        let startTime: Double
    }

    let title: String
    let bpm: Double
    let notes: [Note]
    let sections: [Section]?
}

@MainActor
struct ChartFileStore {
    func chooseChartFileForOpen() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose chart file"
        panel.allowedContentTypes = chartContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseChartFileForSave(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save chart file"
        panel.allowedContentTypes = chartContentTypes
        panel.nameFieldStringValue = defaultName.hasSuffix(".modchart.json") ? defaultName : "\(defaultName).modchart.json"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func save(chart: Chart, bpm: Double, to url: URL) throws {
        let document = ChartDocument(
            title: chart.title,
            bpm: bpm,
            notes: chart.notes.map { .init(lane: $0.lane.rawValue, time: $0.time) },
            sections: chart.sections.map { .init(id: $0.id, name: $0.name, startTime: $0.startTime) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url)
    }

    func loadChart(from url: URL) throws -> (chart: Chart, bpm: Double?) {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document = try decoder.decode(ChartDocument.self, from: data)
        let notes = document.notes.compactMap { item -> NoteEvent? in
            guard let lane = Lane(rawValue: item.lane) else { return nil }
            return NoteEvent(lane: lane, time: item.time)
        }
        let sections = (document.sections ?? []).map {
            SongSection(id: $0.id ?? UUID(), name: $0.name, startTime: $0.startTime)
        }
        return (Chart(notes: notes.sorted { $0.time < $1.time }, title: document.title, sections: sections), document.bpm)
    }

    private var chartContentTypes: [UTType] {
        if let json = UTType.json as UTType? {
            return [json]
        }
        return [.data]
    }
}
