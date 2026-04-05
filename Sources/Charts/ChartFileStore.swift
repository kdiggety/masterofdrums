import Foundation
import AppKit
import UniformTypeIdentifiers

struct ChartDocument: Codable {
    struct TimeSignature: Codable, Equatable {
        let numerator: Int
        let denominator: Int
    }

    struct Timing: Codable, Equatable {
        let bpm: Double
        let offsetSeconds: Double
        let ticksPerBeat: Int
        let timeSignature: TimeSignature
        let source: String
    }

    struct Note: Codable {
        let id: UUID?
        let lane: Int
        let time: Double
    }

    struct Section: Codable {
        let id: UUID?
        let name: String
        let startTime: Double
        let endTime: Double?
        let colorName: String?
    }

    let title: String
    let bpm: Double?
    let timingContractVersion: String?
    let timing: Timing?
    let timelineDuration: Double?
    let notes: [Note]
    let sections: [Section]?
}

struct ImportedChartTiming: Equatable {
    let contractVersion: String?
    let bpm: Double
    let offsetSeconds: Double
    let ticksPerBeat: Int
    let timeSignatureNumerator: Int
    let timeSignatureDenominator: Int
    let source: String

    var sourceLabel: String {
        source.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isGenerated: Bool {
        source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "generated"
    }
}

struct ChartMatchCandidate: Equatable {
    let url: URL
    let score: Int
    let reason: String
}

@MainActor
struct ChartFileStore {
    func chooseChartFileForOpen(startingDirectory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose chart file"
        panel.allowedContentTypes = chartContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = startingDirectory
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseChartFileForSave(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save chart file"
        panel.allowedContentTypes = chartContentTypes
        panel.nameFieldStringValue = defaultName.hasSuffix(".modchart.json") ? defaultName : "\(defaultName).modchart.json"
        return panel.runModal() == .OK ? panel.url : nil
    }

    func save(chart: Chart, bpm: Double, songOffset: Double = 0, timelineDuration: Double? = nil, timingContractVersion: String? = nil, ticksPerBeat: Int = 480, timeSignatureNumerator: Int = 4, timeSignatureDenominator: Int = 4, timingSource: String = "manual", to url: URL) throws {
        let timing = ChartDocument.Timing(
            bpm: bpm,
            offsetSeconds: songOffset,
            ticksPerBeat: ticksPerBeat,
            timeSignature: .init(numerator: timeSignatureNumerator, denominator: timeSignatureDenominator),
            source: timingSource
        )
        let document = ChartDocument(
            title: chart.title,
            bpm: bpm,
            timingContractVersion: timingContractVersion,
            timing: timing,
            timelineDuration: timelineDuration,
            notes: chart.notes.map { .init(id: $0.id, lane: $0.lane.rawValue, time: $0.time) },
            sections: chart.sections.map { .init(id: $0.id, name: $0.name, startTime: $0.startTime, endTime: $0.endTime, colorName: $0.colorName) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url)
    }

    func findMatchingCharts(forAudioURL audioURL: URL) -> [ChartMatchCandidate] {
        let fileManager = FileManager.default
        let audioDirectory = audioURL.deletingLastPathComponent()
        let audioBaseName = audioURL.deletingPathExtension().lastPathComponent
        let normalizedAudioBaseName = normalizedLookupKey(audioBaseName)

        let searchDirectories = [
            audioDirectory,
            audioDirectory.appendingPathComponent("charts", isDirectory: true),
            audioDirectory.appendingPathComponent("Charts", isDirectory: true),
            audioDirectory.deletingLastPathComponent().appendingPathComponent("charts", isDirectory: true),
            audioDirectory.deletingLastPathComponent().appendingPathComponent("Charts", isDirectory: true)
        ]

        var ranked: [String: ChartMatchCandidate] = [:]
        for directory in searchDirectories {
            guard fileManager.fileExists(atPath: directory.path) else { continue }
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let candidateURL as URL in enumerator {
                guard candidateURL.pathExtension.lowercased() == "json" else { continue }
                let filename = candidateURL.lastPathComponent.lowercased()
                guard filename.hasSuffix(".modchart.json") || filename.hasSuffix(".json") else { continue }

                let stem = candidateURL.deletingPathExtension().deletingPathExtension().lastPathComponent
                let normalizedStem = normalizedLookupKey(stem)

                var score = 0
                var reason = ""
                if stem.caseInsensitiveCompare(audioBaseName) == .orderedSame {
                    let sameFolder = candidateURL.deletingLastPathComponent() == audioDirectory
                    score = sameFolder ? 100 : 92
                    reason = sameFolder ? "Same-folder basename match" : "Nearby basename match"
                } else if normalizedStem == normalizedAudioBaseName {
                    let sameFolder = candidateURL.deletingLastPathComponent() == audioDirectory
                    score = sameFolder ? 84 : 74
                    reason = sameFolder ? "Same-folder normalized title match" : "Nearby normalized title match"
                }
                guard score > 0 else { continue }

                let key = candidateURL.resolvingSymlinksInPath().path
                if let existing = ranked[key], existing.score >= score { continue }
                ranked[key] = ChartMatchCandidate(url: candidateURL, score: score, reason: reason)
            }
        }

        return ranked.values.sorted {
            if $0.score == $1.score {
                return $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending
            }
            return $0.score > $1.score
        }
    }

    func loadChart(from url: URL) throws -> (chart: Chart, bpm: Double?, timelineDuration: Double?, timing: ImportedChartTiming?) {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let document = try decoder.decode(ChartDocument.self, from: data)
        let notes = document.notes.compactMap { item -> NoteEvent? in
            guard let lane = Lane(rawValue: item.lane) else { return nil }
            return NoteEvent(id: item.id ?? UUID(), lane: lane, time: item.time)
        }
        let sortedRawSections = (document.sections ?? []).sorted { $0.startTime < $1.startTime }
        let sections = sortedRawSections.enumerated().map { index, item in
            let fallbackEnd = index + 1 < sortedRawSections.count
                ? sortedRawSections[index + 1].startTime
                : max(notes.map(\.time).max() ?? item.startTime, item.startTime + 1)
            return SongSection(
                id: item.id ?? UUID(),
                name: item.name,
                startTime: item.startTime,
                endTime: item.endTime ?? fallbackEnd,
                colorName: item.colorName ?? "blue"
            )
        }
        let timing = document.timing.map {
            ImportedChartTiming(
                contractVersion: document.timingContractVersion,
                bpm: $0.bpm,
                offsetSeconds: $0.offsetSeconds,
                ticksPerBeat: $0.ticksPerBeat,
                timeSignatureNumerator: $0.timeSignature.numerator,
                timeSignatureDenominator: $0.timeSignature.denominator,
                source: $0.source
            )
        }
        return (
            Chart(notes: notes.sorted { $0.time < $1.time }, title: document.title, sections: sections),
            timing?.bpm ?? document.bpm,
            document.timelineDuration,
            timing
        )
    }

    private func normalizedLookupKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    private var chartContentTypes: [UTType] {
        if let json = UTType.json as UTType? {
            return [json]
        }
        return [.data]
    }
}
