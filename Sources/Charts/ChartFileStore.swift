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
        let label: String?
    }

    struct Section: Codable {
        let id: UUID?
        let name: String
        let startTime: Double
        let endTime: Double?
        let colorName: String?
    }

    struct PipelineNote: Decodable {
        let noteID: UUID?
        let lane: String
        let startSeconds: Double
    }

    struct PipelineChart: Decodable {
        let notes: [PipelineNote]
    }

    struct PipelineSource: Decodable {
        let sourceAudio: String?
        let title: String?
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case bpm
        case timingContractVersion
        case timing
        case timelineDuration
        case notes
        case sections
        case chart
        case source
    }

    let title: String
    let bpm: Double?
    let timingContractVersion: String?
    let timing: Timing?
    let timelineDuration: Double?
    let notes: [Note]
    let sections: [Section]?

    init(title: String, bpm: Double?, timingContractVersion: String?, timing: Timing?, timelineDuration: Double?, notes: [Note], sections: [Section]?) {
        self.title = title
        self.bpm = bpm
        self.timingContractVersion = timingContractVersion
        self.timing = timing
        self.timelineDuration = timelineDuration
        self.notes = notes
        self.sections = sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let bpm = try container.decodeIfPresent(Double.self, forKey: .bpm)
        let timingContractVersion = try container.decodeIfPresent(String.self, forKey: .timingContractVersion)
        let timing = try container.decodeIfPresent(Timing.self, forKey: .timing)
        let timelineDuration = try container.decodeIfPresent(Double.self, forKey: .timelineDuration)
        let sections = try container.decodeIfPresent([Section].self, forKey: .sections)

        if let legacyNotes = try container.decodeIfPresent([Note].self, forKey: .notes) {
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Imported Chart"
            self.bpm = bpm
            self.timingContractVersion = timingContractVersion
            self.timing = timing
            self.timelineDuration = timelineDuration
            self.notes = legacyNotes
            self.sections = sections
            return
        }

        let pipelineChart = try container.decode(PipelineChart.self, forKey: .chart)
        let pipelineSource = try container.decodeIfPresent(PipelineSource.self, forKey: .source)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
            ?? pipelineSource?.title
            ?? pipelineSource?.sourceAudio
                .flatMap { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
            ?? "Imported Chart"
        self.bpm = bpm
        self.timingContractVersion = timingContractVersion
        self.timing = timing
        self.timelineDuration = timelineDuration
        self.notes = pipelineChart.notes.compactMap { item in
            guard let lane = Self.laneIndex(forPipelineLane: item.lane) else { return nil }
            return Note(id: item.noteID, lane: lane, time: item.startSeconds, label: Self.displayLabel(forPipelineLane: item.lane))
        }
        self.sections = sections
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(bpm, forKey: .bpm)
        try container.encodeIfPresent(timingContractVersion, forKey: .timingContractVersion)
        try container.encodeIfPresent(timing, forKey: .timing)
        try container.encodeIfPresent(timelineDuration, forKey: .timelineDuration)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(sections, forKey: .sections)
    }

    static func laneIndex(forPipelineLane rawLane: String) -> Int? {
        let normalized = rawLane
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")

        // Explicit kick mappings
        if normalized == "kick" || normalized.contains("bass drum") ||
           normalized.contains("808") || normalized.contains("909") || normalized.contains("kick drum") {
            return Lane.purple.rawValue
        }

        // Snare/clap family
        if normalized == "snare" || normalized == "red" || normalized.contains("snare") ||
           normalized.contains("clap") || normalized.contains("hand drum") {
            return Lane.red.rawValue
        }

        // Closed hi-hat (bright/tight rhythmic sound)
        if normalized == "hihatclosed" ||
           normalized.contains("closed hat") || normalized.contains("closed hihat") ||
           normalized.contains("hi hat closed") || normalized.contains("hihat closed") ||
           (normalized.contains("hihat") && !normalized.contains("open")) ||
           (normalized.contains("hi hat") && !normalized.contains("open")) ||
           normalized.contains("hihat pedal") || normalized.contains("hi hat pedal") ||
           normalized == "yellow" {
            return Lane.yellow.rawValue
        }

        // Open hi-hats, cymbals, and crash/ride family (resonant/open sounds)
        if normalized == "hihatopen" ||
           normalized.contains("open hat") || normalized.contains("open hihat") ||
           normalized.contains("hihat open") || normalized.contains("hi hat open") ||
           normalized.contains("cymbal") || normalized.contains("crash") || normalized.contains("ride") ||
           normalized.contains("gong") || (normalized.contains("bell") && !normalized.contains("cowbell")) {
            return Lane.green.rawValue
        }

        // Tom family (high toms)
        if normalized.contains("tom high") || normalized.contains("high tom") || normalized.contains("tom1") ||
           normalized == "tomhigh" || normalized == "tom_high" || normalized == "blue" {
            return Lane.blue.rawValue
        }

        // Mid/low toms and general percussion
        if normalized.contains("tom mid") || normalized.contains("mid tom") ||
           normalized.contains("tom low") || normalized.contains("low tom") || normalized.contains("floor tom") ||
           normalized.contains("tom2") || normalized.contains("tom3") ||
           normalized == "tommid" || normalized == "tom_mid" || normalized == "tomlow" || normalized == "tom_low" ||
           normalized == "green" || normalized == "percussion" ||
           normalized.contains("timpani") || normalized.contains("bongo") || normalized.contains("conga") ||
           normalized.contains("woodblock") || normalized.contains("cowbell") {
            return Lane.green.rawValue
        }

        return nil
    }

    fileprivate static func displayLabel(forPipelineLane rawLane: String) -> String {
        rawLane
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
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

struct ChartMatchCandidate: Equatable, Identifiable {
    let id: String
    let url: URL
    let score: Int
    let reason: String

    init(url: URL, score: Int, reason: String) {
        self.id = url.resolvingSymlinksInPath().path
        self.url = url
        self.score = score
        self.reason = reason
    }
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
            notes: chart.notes.map { .init(id: $0.id, lane: $0.lane.rawValue, time: $0.time, label: $0.label) },
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
                let sameFolder = candidateURL.deletingLastPathComponent() == audioDirectory
                let inDedicatedChartsFolder = ["charts", "Charts"].contains(candidateURL.deletingLastPathComponent().lastPathComponent)
                let isModChartJSON = filename.hasSuffix(".modchart.json")

                var score = 0
                var reasons: [String] = []
                if stem.caseInsensitiveCompare(audioBaseName) == .orderedSame {
                    score += sameFolder ? 100 : 92
                    reasons.append(sameFolder ? "same-folder basename" : "nearby basename")
                } else if normalizedStem == normalizedAudioBaseName {
                    score += sameFolder ? 84 : 74
                    reasons.append(sameFolder ? "same-folder normalized title" : "nearby normalized title")
                }
                if isModChartJSON {
                    score += 6
                    reasons.append("modchart artifact")
                }
                if inDedicatedChartsFolder {
                    score += 4
                    reasons.append("charts folder")
                }
                guard score > 0 else { continue }

                let key = candidateURL.resolvingSymlinksInPath().path
                let reason = reasons.joined(separator: " + ")
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
        var notes = document.notes.compactMap { item -> NoteEvent? in
            guard let lane = Lane(rawValue: item.lane) else { return nil }
            return NoteEvent(id: item.id ?? UUID(), lane: lane, time: item.time, label: item.label)
        }

        if notes.isEmpty,
           let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let chart = raw["chart"] as? [String: Any],
           let pipelineNotes = chart["notes"] as? [[String: Any]] {
            notes = pipelineNotes.compactMap { item in
                guard let rawLane = item["lane"] as? String,
                      let laneIndex = ChartDocument.laneIndex(forPipelineLane: rawLane),
                      let lane = Lane(rawValue: laneIndex) else {
                    return nil
                }
                let noteID = (item["noteID"] as? String).flatMap(UUID.init(uuidString:))
                let time = (item["startSeconds"] as? NSNumber)?.doubleValue ?? (item["time"] as? NSNumber)?.doubleValue
                guard let time else { return nil }
                return NoteEvent(
                    id: noteID ?? UUID(),
                    lane: lane,
                    time: time,
                    label: nil
                )
            }
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
