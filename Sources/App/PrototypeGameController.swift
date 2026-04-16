import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

private struct AdminChartHistoryEntry {
    let chart: Chart
    let bpm: Double
    let selectedNoteID: UUID?
    let selectedNoteIDs: Set<UUID>
    let selectedSectionID: UUID?
}

private struct AdminClipboardNote {
    let lane: Lane
    let relativeTime: TimeInterval
}

private struct AdminSectionClipboard {
    let name: String
    let colorName: String
    let duration: TimeInterval
    let notes: [AdminClipboardNote]
}

enum SongSectionEdge {
    case start
    case end
    case move
}

@MainActor
final class PrototypeGameController: ObservableObject {
    private enum PersistenceKeys {
        static let lastAudioFilePath = "PrototypeGameController.lastAudioFilePath"
        static let lastChartFilePath = "PrototypeGameController.lastChartFilePath"
    }

    enum StepResolution: String, CaseIterable, Identifiable {
        case quarter = "1/4"
        case eighth = "1/8"
        case eighthTriplet = "1/8T"
        case sixteenth = "1/16"
        case sixteenthTriplet = "1/16T"
        case thirtySecond = "1/32"
        case thirtySecondTriplet = "1/32T"

        var id: String { rawValue }
        var subdivisionsPerBeat: Int {
            switch self {
            case .quarter: return 1
            case .eighth: return 2
            case .eighthTriplet: return 3
            case .sixteenth: return 4
            case .sixteenthTriplet: return 6
            case .thirtySecond: return 8
            case .thirtySecondTriplet: return 12
            }
        }

        var helpText: String {
            switch self {
            case .quarter: return "Straight quarter-note grid"
            case .eighth: return "Straight eighth-note grid"
            case .eighthTriplet: return "Eighth-note triplet grid"
            case .sixteenth: return "Straight sixteenth-note grid"
            case .sixteenthTriplet: return "Sixteenth-note triplet grid"
            case .thirtySecond: return "Straight thirty-second-note grid"
            case .thirtySecondTriplet: return "Thirty-second-note triplet grid"
            }
        }
    }

    enum LoopLength: String, CaseIterable, Identifiable {
        case off = "Off"
        case oneBar = "1 Bar"
        case twoBars = "2 Bars"
        case fourBars = "4 Bars"
        case eightBars = "8 Bars"

        var id: String { rawValue }
        var barCount: Int {
            switch self {
            case .off: return 0
            case .oneBar: return 1
            case .twoBars: return 2
            case .fourBars: return 4
            case .eightBars: return 8
            }
        }
    }

    @Published private(set) var score: Int = 0
    @Published private(set) var combo: Int = 0
    @Published private(set) var missCount: Int = 0
    @Published private(set) var hitCount: Int = 0
    @Published private(set) var lastJudgmentText: String = "—"
    @Published private(set) var activeInputSourceName: String
    @Published private(set) var isRunComplete: Bool = false
    @Published private(set) var statusMessage: String = "Ready"
    @Published private(set) var accuracyText: String = "0%"
    @Published private(set) var trackName: String = "No audio loaded"
    @Published private(set) var chartName: String = "Untitled Chart"
    @Published private(set) var chartStatusText: String = "No chart loaded"
    @Published private(set) var chartAssociationStatusText: String = "Load audio to auto-match a chart."
    @Published private(set) var chartMatchCandidates: [ChartMatchCandidate] = []
    @Published var isChartMatchPickerPresented: Bool = false
    @Published private(set) var transportStateText: String = TransportState.stopped.rawValue
    @Published private(set) var playbackTimeText: String = "0.00s"
    @Published private(set) var currentPlaybackNoteID: UUID?
    @Published var isRecordedNotesAutoscrollEnabled: Bool = true
    @Published private(set) var barBeatText: String = "1:1"
    @Published private(set) var musicalSubdivisionText: String = "1"
    @Published private(set) var bpmSourceText: String = "Manual"
    @Published private(set) var timingSourceText: String = "Manual"
    @Published private(set) var timingOverrideStatusText: String = "Using manual timing"
    @Published private(set) var timeSignatureText: String = "4/4"
    @Published private(set) var ticksPerBeatText: String = "480"
    @Published private(set) var bpmAnalysisStatusText: String = "Idle"
    @Published private(set) var bpmAnalysisDetailText: String = "No file analyzed yet"
    @Published private(set) var midiTempoText: String = "Not loaded"
    @Published private(set) var gameplayFocusVersion: Int = 0
    @Published private(set) var playbackRateText: String = "100%"
    @Published private(set) var playbackDurationText: String = "0.00s"
    @Published private(set) var loopStatusText: String = "Loop Off"
    @Published var isMetronomeEnabled: Bool = false
    @Published private(set) var isChartOnlyPlaybackEnabled: Bool = false
    @Published private(set) var isAudioMuted: Bool = false
    @Published private(set) var isChartMuted: Bool = false
    @Published private(set) var isChartAuditionActive: Bool = false
    @Published private(set) var adminTimelineDuration: Double = 1
    @Published var adminSelectedNoteID: UUID? {
        didSet {
            scene.selectedAdminNoteID = adminSelectedNoteID
        }
    }
    @Published var adminSelectedNoteIDs: Set<UUID> = [] {
        didSet {
            if let selected = adminSelectedNoteID, !adminSelectedNoteIDs.contains(selected) {
                adminSelectedNoteID = adminSelectedNoteIDs.first
            } else if adminSelectedNoteID == nil {
                adminSelectedNoteID = adminSelectedNoteIDs.first
            }
        }
    }
    @Published private(set) var adminScrubPreviewTime: Double?
    @Published var bpm: Double = 120
    @Published var songOffset: Double = 0
    @Published private(set) var beatsPerBar: Int = 4
    @Published private(set) var timeSignatureDenominator: Int = 4
    @Published private(set) var ticksPerBeat: Int = 480

    @Published var isAdminPageActive = false {
        didSet {
            scene.isAdminAuthoringMode = isAdminPageActive
            scene.selectedAdminNoteID = adminSelectedNoteID
            refreshAdminVisibleNotes(at: adminScrubPreviewTime ?? audio.currentTime)
        }
    }
    @Published var adminSelectedLane: Lane = .kick
    @Published var adminNoteTime: Double = 0
    @Published private(set) var adminNotes: [NoteEvent] = []
    @Published private(set) var adminStatusText: String = "Open Admin to create or load a chart."
    @Published var isAdminRecordMode = false
    @Published private(set) var canUndoAdminEdit = false
    @Published private(set) var canRedoAdminEdit = false
    @Published private(set) var adminSections: [SongSection] = []
    @Published var selectedAdminSectionID: UUID?
    @Published var stepResolution: StepResolution = .sixteenth
    @Published var stepCursorTime: Double = 0
    @Published private(set) var stepCursorDisplayText: String = "1.1.1.000 · 0.00s"
    @Published var loopLength: LoopLength = .off
    @Published private(set) var loopStartTime: Double = 0
    @Published private(set) var customLoopRange: ClosedRange<Double>?
    @Published var isNoteLaneSnapEnabled: Bool = true

    let scene: GameplayScene
    let audio: AudioPlaybackController

    private let session: GameSession
    private let inputRouter: InputRouter
    private let midiLoader = MIDIChartLoader()
    private let chartFileStore = ChartFileStore()
    private let laneSoundPlayer = LaneSoundPlayer()
    private let chartPreviewClock = PreviewPlaybackClock()
    private var lastMetronomeSubdivisionIndex: Int?
    private var lastChartPlaybackTriggeredNoteIDs: Set<UUID> = []
    private var chartPreviewLastAuditionTime: Double?
    private var chartPreviewTimerCancellable: AnyCancellable?
    private let completionGracePeriod: TimeInterval = 0.5
    private let adminLaneScrubDurationMultiplier: Double = 0.08
    private let adminNoteDragDurationMultiplier: Double = 0.03
    private let adminScrubSmoothingFactor: Double = 0.35
    private let adminNoteDragSmoothingFactor: Double = 0.45
    private let adminAuthoringNoteSpeed: Double = 110
    private let noteLaneHitLineHeight: Double = 6
    private var adminScrubPreviewTargetTime: Double?
    private var activeSectionDragSnapshot: [SongSection]?
    private var activeAdminChartURL: URL?

    // Caches for throttling @Published updates to avoid excessive SwiftUI re-renders
    private var lastPublishedPlaybackTimeText: String?
    private var lastPublishedBarBeatText: String?
    private var lastPublishedMusicalSubdivisionText: String?
    private var lastPublishedCurrentPlaybackNoteID: UUID?
    private var cancellables: Set<AnyCancellable> = []
    private var undoHistory: [AdminChartHistoryEntry] = []
    private var redoHistory: [AdminChartHistoryEntry] = []
    private var adminClipboard: [AdminClipboardNote] = []
    private var adminSectionClipboard: AdminSectionClipboard?
    private var importedChartTiming: ImportedChartTiming?
    private var hasManualTimingOverride = false
    private var activeDisplayLaneBlueprint: [ChartLane]?

    var isAdminAuthoringActive: Bool { isAdminPageActive }

    init() {
        let initialChart = Chart(notes: [], title: "Untitled Chart", sections: [])
        self.session = GameSession(chart: initialChart)
        let keyboard = KeyboardInputDevice()
        self.inputRouter = InputRouter(activeDevice: keyboard)
        self.audio = AudioPlaybackController()
        self.scene = GameplayScene(chart: initialChart, keyboardInputDevice: keyboard)
        self.scene.isAdminAuthoringMode = false
        self.activeInputSourceName = keyboard.source.rawValue
        self.chartName = initialChart.title
        self.chartStatusText = "No chart loaded"
        self.adminStatusText = "Open Admin to create or load a chart."
        self.adminNotes = initialChart.notes
        self.adminSections = initialChart.sections

        self.scene.timeProvider = { [weak self, weak audio] in
            if let self {
                return self.currentSceneTime(fallbackAudioTime: audio?.currentTime ?? 0)
            }
            return audio?.currentTime ?? 0
        }
        self.scene.beatGuideConfiguration = { [weak self] in
            guard let self else { return nil }
            return GameplayScene.BeatGuideConfiguration(
                bpm: self.bpm,
                songOffset: self.songOffset,
                beatsPerBar: self.beatsPerBar,
                subdivisionsPerBeat: self.stepResolution.subdivisionsPerBeat
            )
        }
        self.inputRouter.onInput = { [weak self] event in self?.handleInput(event) }
        self.scene.onInput = { [weak self] event in self?.inputRouter.route(event) }
        self.scene.onTick = { [weak self] time in self?.handleTick(time) }

        audio.$detectedBPM
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncBPMStateFromCurrentSources() }
            .store(in: &cancellables)
        audio.$analysisDebug
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncBPMStateFromCurrentSources() }
            .store(in: &cancellables)
        audio.$isMuted
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isAudioMuted = value }
            .store(in: &cancellables)

        syncState()
        syncTransportState()
        updateStepCursorDisplay()
        updatePlaybackRateText()
        updateLoopStatusText()
        scene.selectedAdminNoteID = adminSelectedNoteID
        updateAdminHistoryAvailability()
        restoreLastOpenedSessionIfPossible()
    }

    func chooseAudioFile() {
        audio.chooseAudioFile()
        if audio.loadedTrackName != nil {
            updateAudioMetadataAfterLoad()
            persistLastOpenedAudioURL(audio.currentFileURL)
            attemptChartAutoMatchForCurrentAudio(userInitiated: false)
        } else {
            chartAssociationStatusText = "Audio selection cancelled."
        }
        refocusGameplay()
    }

    func chooseChartFile() {
        let startingDirectory = suggestedChartDirectoryForCurrentAudio()
        guard let url = chartFileStore.chooseChartFileForOpen(startingDirectory: startingDirectory) else {
            refocusGameplay(); return
        }
        loadChart(from: url)
    }

    func findMatchingChartForCurrentAudio() {
        attemptChartAutoMatchForCurrentAudio(userInitiated: true)
        refocusGameplay()
    }

    func selectChartMatch(_ candidate: ChartMatchCandidate) {
        isChartMatchPickerPresented = false
        chartMatchCandidates = []
        chartAssociationStatusText = "Selected chart: \(candidate.url.lastPathComponent) · \(candidate.reason)"
        loadChart(from: candidate.url)
        refocusGameplay()
    }

    func dismissChartMatchPicker() {
        isChartMatchPickerPresented = false
        chartAssociationStatusText = chartMatchCandidates.isEmpty
            ? chartAssociationStatusText
            : "Chart match selection dismissed. Use Choose Chart if you want to pick manually."
    }

    private func updateAudioMetadataAfterLoad() {
        if let loadedTrackName = audio.loadedTrackName {
            trackName = loadedTrackName
            statusMessage = "Loaded \(loadedTrackName)"
        } else {
            trackName = "No audio loaded"
            statusMessage = "Ready"
        }
        syncBPMStateFromCurrentSources()
        updateStepCursorDisplay()
        syncTransportState()
    }

    private func syncBPMStateFromCurrentSources() {
        if let importedChartTiming, importedChartTiming.isGenerated, !hasManualTimingOverride {
            bpm = importedChartTiming.bpm
            songOffset = importedChartTiming.offsetSeconds
            beatsPerBar = max(1, importedChartTiming.timeSignatureNumerator)
            timeSignatureDenominator = max(1, importedChartTiming.timeSignatureDenominator)
            ticksPerBeat = max(1, importedChartTiming.ticksPerBeat)
            bpmSourceText = "Chart JSON"
            timingSourceText = "Chart Timing v\(importedChartTiming.contractVersion ?? "0.1.0") · \(importedChartTiming.sourceLabel)"
            timingOverrideStatusText = "Generated chart timing is authoritative"
            midiTempoText = String(format: "%.1f BPM / %.2fs from chart timing", bpm, songOffset)
        } else if let importedChartTiming, !hasManualTimingOverride {
            bpm = importedChartTiming.bpm
            songOffset = importedChartTiming.offsetSeconds
            beatsPerBar = max(1, importedChartTiming.timeSignatureNumerator)
            timeSignatureDenominator = max(1, importedChartTiming.timeSignatureDenominator)
            ticksPerBeat = max(1, importedChartTiming.ticksPerBeat)
            bpmSourceText = "Chart JSON"
            timingSourceText = "Chart Timing v\(importedChartTiming.contractVersion ?? "0.1.0") · \(importedChartTiming.sourceLabel)"
            timingOverrideStatusText = "Chart timing loaded"
            midiTempoText = String(format: "%.1f BPM / %.2fs from chart timing", bpm, songOffset)
        } else if let detected = audio.detectedBPM, importedChartTiming == nil {
            bpm = detected.bpm
            bpmSourceText = detected.source.capitalized
            timingSourceText = detected.source.capitalized
            timingOverrideStatusText = "Using detected audio BPM"
            midiTempoText = String(format: "%.1f BPM from \(detected.source)", detected.bpm)
        } else {
            bpmSourceText = hasManualTimingOverride ? "Manual Override" : "Manual"
            timingSourceText = hasManualTimingOverride ? "Manual Override" : "Manual"
            timingOverrideStatusText = hasManualTimingOverride
                ? "Manual override active — chart timing kept visible for reference"
                : "Using manual timing"
            if importedChartTiming == nil, (midiTempoText == "Not loaded" || midiTempoText.contains("from chart") || midiTempoText.contains("from MIDI") || midiTempoText.contains("from metadata") || midiTempoText.contains("from filename") || midiTempoText.contains("from analysis")) {
                midiTempoText = audio.loadedTrackName == nil ? "Not loaded" : "No BPM detected yet"
            }
        }
        timeSignatureText = "\(beatsPerBar)/\(timeSignatureDenominator)"
        ticksPerBeatText = "\(ticksPerBeat)"
        bpmAnalysisStatusText = importedChartTiming?.isGenerated == true ? "Diagnostic Only" : audio.analysisDebug.status
        bpmAnalysisDetailText = importedChartTiming?.isGenerated == true
            ? (audio.detectedBPM.map { String(format: "Audio analysis suggests %.1f BPM from %@", $0.bpm, $0.source) } ?? audio.analysisDebug.detail)
            : audio.analysisDebug.detail
        updateStepCursorDisplay()
        updateLoopStatusText()
        syncTransportState()
    }

    private func suggestedChartDirectoryForCurrentAudio() -> URL? {
        guard let currentAudioURL = audio.currentFileURL else { return nil }
        let candidates = chartFileStore.findMatchingCharts(forAudioURL: currentAudioURL)
        return candidates.first?.url.deletingLastPathComponent() ?? currentAudioURL.deletingLastPathComponent()
    }

    private func attemptChartAutoMatchForCurrentAudio(userInitiated: Bool) {
        guard let currentAudioURL = audio.currentFileURL else {
            chartAssociationStatusText = "Choose audio first to search for a matching chart."
            return
        }
        let candidates = chartFileStore.findMatchingCharts(forAudioURL: currentAudioURL)
        if let best = candidates.first, candidates.count == 1 {
            chartAssociationStatusText = "Matched chart: \(best.url.lastPathComponent) · \(best.reason.lowercased())"
            loadChart(from: best.url)
            return
        }
        if let best = candidates.first {
            chartAssociationStatusText = "Found \(candidates.count) chart candidates. Best match: \(best.url.lastPathComponent) · \(best.reason.lowercased()). Use Choose Chart to confirm."
        } else {
            chartAssociationStatusText = userInitiated
                ? "No matching chart found near \(currentAudioURL.lastPathComponent). Use Choose Chart to pick one manually."
                : "No matching chart found automatically for \(currentAudioURL.lastPathComponent)."
        }
    }

    private func persistLastOpenedAudioURL(_ url: URL?) {
        let defaults = UserDefaults.standard
        if let path = url?.path {
            defaults.set(path, forKey: PersistenceKeys.lastAudioFilePath)
        } else {
            defaults.removeObject(forKey: PersistenceKeys.lastAudioFilePath)
        }
    }

    private func persistLastOpenedChartURL(_ url: URL?) {
        let defaults = UserDefaults.standard
        if let path = url?.path {
            defaults.set(path, forKey: PersistenceKeys.lastChartFilePath)
        } else {
            defaults.removeObject(forKey: PersistenceKeys.lastChartFilePath)
        }
    }

    private func restoreLastOpenedSessionIfPossible() {
        let defaults = UserDefaults.standard
        let fileManager = FileManager.default

        if let audioPath = defaults.string(forKey: PersistenceKeys.lastAudioFilePath),
           fileManager.fileExists(atPath: audioPath) {
            audio.loadAudioFile(from: URL(fileURLWithPath: audioPath))
            updateAudioMetadataAfterLoad()
        }

        if let chartPath = defaults.string(forKey: PersistenceKeys.lastChartFilePath),
           fileManager.fileExists(atPath: chartPath) {
            loadChart(from: URL(fileURLWithPath: chartPath))
        } else if audio.currentFileURL != nil {
            attemptChartAutoMatchForCurrentAudio(userInitiated: false)
        }
    }

    func startAdminChart() {
        activeAdminChartURL = nil
        importedChartTiming = nil
        hasManualTimingOverride = false
        adminTimelineDuration = max(playbackDuration, 1)
        activeDisplayLaneBlueprint = nil
        let chart = Chart(notes: [], title: trackName == "No audio loaded" ? "Untitled Chart" : trackName, sections: [], displayLaneBlueprint: nil)
        applyChart(chart, bpmOverride: bpm, chartStatus: "Started empty admin chart", recordHistory: true)
        adminStatusText = "Started new chart. Use step mode or record mode."
        adminNoteTime = 0
        adminSelectedLane = .kick
        stepCursorTime = 0
        updateStepCursorDisplay()
        refocusGameplay()
    }

    func toggleAdminRecordMode() {
        isAdminRecordMode.toggle()
        adminStatusText = isAdminRecordMode ? "Record mode armed. Press Play, then use gameplay keys to capture notes." : "Record mode off. Step mode remains available."
        statusMessage = isAdminRecordMode ? "Admin Record" : "Admin Step"
        refocusGameplay()
    }

    func undoAdminEdit() {
        guard let previous = undoHistory.popLast() else { return }
        redoHistory.append(currentAdminHistoryEntry())
        restoreAdminHistoryEntry(previous, statusText: "Undo chart edit")
    }

    func redoAdminEdit() {
        guard let next = redoHistory.popLast() else { return }
        undoHistory.append(currentAdminHistoryEntry())
        restoreAdminHistoryEntry(next, statusText: "Redo chart edit")
    }

    func clearAdminNotes() {
        let title = chartName == "Untitled Chart" ? "Admin Chart" : chartName
        applyChart(Chart(notes: [], title: title, sections: adminSections, displayLaneBlueprint: activeDisplayLaneBlueprint), bpmOverride: bpm, chartStatus: "Cleared chart notes", recordHistory: true)
        adminStatusText = "Cleared chart notes."
        stepCursorTime = 0
        updateStepCursorDisplay()
        refocusGameplay()
    }

    @discardableResult
    func addSongSection(at time: Double? = nil, named name: String? = nil) -> UUID? {
        let liveTime = audio.state == .playing ? audio.currentTime : stepCursorTime
        let baseTime = time ?? liveTime
        let desiredStart = quantizedLoopStart(for: baseTime)
        let defaultLength = max(barDuration * 4, barDuration)
        let existingSections = adminSections.sorted { $0.startTime < $1.startTime }
        let snapThreshold = stepInterval
        let minimumLength = stepInterval

        if let containingSection = existingSections.first(where: { desiredStart > $0.startTime + 0.0001 && desiredStart < $0.endTime - 0.0001 }) {
            guard desiredStart - containingSection.startTime >= minimumLength,
                  containingSection.endTime - desiredStart >= minimumLength else {
                adminStatusText = "Not enough room to split this section here"
                return nil
            }

            let sectionName = normalizedSectionName(name)
            let splitSection = SongSection(
                name: sectionName,
                startTime: desiredStart,
                endTime: containingSection.endTime,
                colorName: containingSection.colorName
            )
            let updatedSections = existingSections.map { section in
                guard section.id == containingSection.id else { return section }
                return SongSection(
                    id: section.id,
                    name: section.name,
                    startTime: section.startTime,
                    endTime: desiredStart,
                    colorName: section.colorName
                )
            } + [splitSection]

            let title = normalizedAdminChartTitle()
            applyChart(Chart(notes: adminNotes, title: title, sections: updatedSections), bpmOverride: bpm, chartStatus: "Split song section", recordHistory: true)
            selectedAdminSectionID = splitSection.id
            adminStatusText = "Split at \(sectionBarBeatText(for: desiredStart)) into \(containingSection.name) and \(splitSection.name)"
            refocusGameplay()
            return splitSection.id
        }

        var startTime = desiredStart
        if let adjacentEnd = existingSections
            .map(\.endTime)
            .min(by: { abs($0 - desiredStart) < abs($1 - desiredStart) }),
           abs(adjacentEnd - desiredStart) <= snapThreshold {
            startTime = adjacentEnd
        }

        let previousSection = existingSections.last(where: { $0.endTime <= startTime + 0.0001 })
        let nextSection = existingSections.first(where: { $0.startTime >= startTime - 0.0001 })
        let gapStart = previousSection.map { max(startTime, $0.endTime) } ?? startTime
        startTime = gapStart
        let endLimit = nextSection?.startTime ?? max(playbackDuration, adminNotes.map(\.time).max() ?? 0, startTime + defaultLength)
        var endTime = min(startTime + defaultLength, endLimit)
        if let nextSection, abs(endTime - nextSection.startTime) <= snapThreshold {
            endTime = nextSection.startTime
        }

        guard endTime - startTime >= minimumLength else {
            adminStatusText = nextSection == nil
                ? "Not enough open space to create a section here"
                : "No room here — try a gap or split the current section"
            return nil
        }

        if existingSections.contains(where: { startTime < $0.endTime - 0.0001 && endTime > $0.startTime + 0.0001 }) {
            adminStatusText = "New section overlaps an existing section"
            return nil
        }

        let sectionName = normalizedSectionName(name)
        let section = SongSection(name: sectionName, startTime: startTime, endTime: endTime, colorName: nextSection?.colorName ?? previousSection?.colorName ?? "blue")
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: adminNotes, title: title, sections: existingSections + [section]), bpmOverride: bpm, chartStatus: "Added song section", recordHistory: true)
        selectedAdminSectionID = section.id
        adminStatusText = "Added \(section.name) \(sectionBarBeatText(for: section.startTime))–\(sectionBarBeatText(for: section.endTime))"
        refocusGameplay()
        return section.id
    }

    func renameSongSection(_ id: UUID, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard let section = adminSections.first(where: { $0.id == id }), section.name != trimmedName else { return }
        let updatedSections = adminSections.map { item in
            item.id == id ? SongSection(id: item.id, name: trimmedName, startTime: item.startTime, endTime: item.endTime, colorName: item.colorName) : item
        }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: adminNotes, title: title, sections: updatedSections), bpmOverride: bpm, chartStatus: "Renamed song section", recordHistory: true)
        selectedAdminSectionID = id
        adminStatusText = "Renamed section to \(trimmedName)"
    }

    func selectSongSection(_ id: UUID?, movePlayhead: Bool = false) {
        selectedAdminSectionID = id
        if movePlayhead, let id, let section = adminSections.first(where: { $0.id == id }) {
            let wasPlaying = audio.state == .playing
            adminScrubPreviewTargetTime = nil
            adminScrubPreviewTime = nil
            audio.seek(to: section.startTime)
            moveStepCursor(to: section.startTime, seekPlayback: false)
            refreshAdminVisibleNotes(at: section.startTime)
            if wasPlaying {
                audio.play()
            }
            syncTransportState()
            adminStatusText = wasPlaying ? "Playing from \(section.name)" : "Moved to \(section.name)"
        }
    }

    func jumpToSongSection(_ id: UUID, playIfAlreadyPlaying: Bool = false) {
        guard let section = adminSections.first(where: { $0.id == id }) else { return }
        let wasPlaying = audio.state == .playing
        selectedAdminSectionID = id
        moveStepCursor(to: section.startTime, seekPlayback: true)
        if playIfAlreadyPlaying && wasPlaying {
            audio.play()
        }
        adminStatusText = wasPlaying && playIfAlreadyPlaying
            ? "Playing from \(section.name)"
            : "Jumped to \(section.name) at \(sectionBarBeatText(for: section.startTime))"
        refocusGameplay()
    }

    func beginSongSectionDrag() {
        if activeSectionDragSnapshot == nil {
            activeSectionDragSnapshot = adminSections.sorted { $0.startTime < $1.startTime }
        }
    }

    func endSongSectionDrag() {
        guard let snapshot = activeSectionDragSnapshot else { return }
        activeSectionDragSnapshot = nil
        let current = adminSections.sorted { $0.startTime < $1.startTime }
        guard snapshot != current else { return }
        undoHistory.append(
            AdminChartHistoryEntry(
                chart: Chart(notes: adminNotes, title: chartName, sections: snapshot),
                bpm: bpm,
                selectedNoteID: adminSelectedNoteID,
                selectedNoteIDs: adminSelectedNoteIDs,
                selectedSectionID: selectedAdminSectionID
            )
        )
        redoHistory.removeAll()
        canUndoAdminEdit = !undoHistory.isEmpty
        canRedoAdminEdit = !redoHistory.isEmpty
    }

    func updateSongSectionBoundary(_ id: UUID, edge: SongSectionEdge, to time: Double) {
        let sortedSections = adminSections.sorted { $0.startTime < $1.startTime }
        guard let sortedIndex = sortedSections.firstIndex(where: { $0.id == id }) else { return }

        let minDuration = stepInterval
        let snapThreshold = stepInterval
        let snappedTime = quantizedAdminGridTime(for: max(0, time))
        var updatedSections = sortedSections
        var updatedSection = sortedSections[sortedIndex]

        switch edge {
        case .move:
            let previous = sortedIndex > 0 ? sortedSections[sortedIndex - 1] : nil
            let next = sortedIndex + 1 < sortedSections.count ? sortedSections[sortedIndex + 1] : nil
            let duration = updatedSection.endTime - updatedSection.startTime
            let minStart = previous?.endTime ?? 0
            let maxStart = (next?.startTime ?? max(playbackDuration, adminNotes.map(\.time).max() ?? 0, updatedSection.endTime)) - duration
            let newStart = min(max(snappedTime, minStart), maxStart)
            let delta = newStart - updatedSection.startTime
            let newEnd = newStart + duration
            updatedSection = SongSection(id: updatedSection.id, name: updatedSection.name, startTime: newStart, endTime: newEnd, colorName: updatedSection.colorName)
            updatedSections[sortedIndex] = updatedSection

            let sectionRange = sortedSections[sortedIndex].startTime..<sortedSections[sortedIndex].endTime
            let updatedNotes = adminNotes.map { note in
                guard sectionRange.contains(note.time) else { return note }
                let movedTime = isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: note.time + delta) : max(0, note.time + delta)
                return NoteEvent(id: note.id, lane: note.lane, time: movedTime)
            }.sorted { lhs, rhs in
                if abs(lhs.time - rhs.time) > 0.0001 { return lhs.time < rhs.time }
                return lhs.lane.rawValue < rhs.lane.rawValue
            }
            let title = normalizedAdminChartTitle()
            applyChart(Chart(notes: updatedNotes, title: title, sections: updatedSections), bpmOverride: bpm, chartStatus: "Moved song section", recordHistory: false)
            selectedAdminSectionID = id
            adminStatusText = "Moved \(updatedSection.name) to \(sectionBarBeatText(for: updatedSection.startTime))"
            refocusGameplay()
            return
        case .start:
            let previous = sortedIndex > 0 ? sortedSections[sortedIndex - 1] : nil
            let isAdjacent = previous.map { abs($0.endTime - updatedSection.startTime) <= snapThreshold * 0.5 } ?? false
            let minStart = previous.map { isAdjacent ? $0.startTime + minDuration : $0.endTime } ?? 0
            let maxStart = updatedSection.endTime - minDuration
            var newStart = min(max(snappedTime, minStart), maxStart)
            if let previous, !isAdjacent, abs(newStart - previous.endTime) <= snapThreshold {
                newStart = previous.endTime
            }
            updatedSection = SongSection(id: updatedSection.id, name: updatedSection.name, startTime: newStart, endTime: updatedSection.endTime, colorName: updatedSection.colorName)
            updatedSections[sortedIndex] = updatedSection
            if let previous, isAdjacent {
                updatedSections[sortedIndex - 1] = SongSection(id: previous.id, name: previous.name, startTime: previous.startTime, endTime: newStart, colorName: previous.colorName)
            }
        case .end:
            let next = sortedIndex + 1 < sortedSections.count ? sortedSections[sortedIndex + 1] : nil
            let isAdjacent = next.map { abs(updatedSection.endTime - $0.startTime) <= snapThreshold * 0.5 } ?? false
            let maxEnd = next.map { isAdjacent ? $0.endTime - minDuration : $0.startTime } ?? max(playbackDuration, adminNotes.map(\.time).max() ?? 0, updatedSection.endTime)
            let minEnd = updatedSection.startTime + minDuration
            var newEnd = max(min(snappedTime, maxEnd), minEnd)
            if let next, !isAdjacent, abs(newEnd - next.startTime) <= snapThreshold {
                newEnd = next.startTime
            }
            updatedSection = SongSection(id: updatedSection.id, name: updatedSection.name, startTime: updatedSection.startTime, endTime: newEnd, colorName: updatedSection.colorName)
            updatedSections[sortedIndex] = updatedSection
            if let next, isAdjacent {
                updatedSections[sortedIndex + 1] = SongSection(id: next.id, name: next.name, startTime: newEnd, endTime: next.endTime, colorName: next.colorName)
            }
        }

        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: adminNotes, title: title, sections: updatedSections), bpmOverride: bpm, chartStatus: "Adjusted song section", recordHistory: false)
        selectedAdminSectionID = id
        adminStatusText = "Adjusted \(updatedSection.name) \(sectionBarBeatText(for: updatedSection.startTime))–\(sectionBarBeatText(for: updatedSection.endTime))"
        refocusGameplay()
    }

    func updateSongSectionColor(_ id: UUID, colorName: String) {
        guard let section = adminSections.first(where: { $0.id == id }), section.colorName != colorName else { return }
        let updatedSections = adminSections.map { item in
            item.id == id ? SongSection(id: item.id, name: item.name, startTime: item.startTime, endTime: item.endTime, colorName: colorName) : item
        }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: adminNotes, title: title, sections: updatedSections), bpmOverride: bpm, chartStatus: "Changed section color", recordHistory: true)
        selectedAdminSectionID = id
        adminStatusText = "Changed \(section.name) color"
    }

    func deleteSongSection(_ id: UUID) {
        guard let section = adminSections.first(where: { $0.id == id }) else { return }
        let updatedSections = adminSections.filter { $0.id != id }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: adminNotes, title: title, sections: updatedSections), bpmOverride: bpm, chartStatus: "Deleted song section", recordHistory: true)
        if selectedAdminSectionID == id {
            selectedAdminSectionID = nil
        }
        if customLoopRange != nil, section.id == id {
            customLoopRange = nil
        }
        adminStatusText = "Deleted section \(section.name)"
        refocusGameplay()
    }

    func setLoopToSongSection(_ id: UUID) {
        guard let range = songSectionRange(id: id), let section = adminSections.first(where: { $0.id == id }) else { return }
        selectedAdminSectionID = id
        loopLength = .off
        customLoopRange = range
        loopStartTime = range.lowerBound
        updateLoopStatusText()
        adminStatusText = "Looping \(section.name)"
        refocusGameplay()
    }

    func clearSongSectionLoop() {
        guard customLoopRange != nil else { return }
        customLoopRange = nil
        updateLoopStatusText()
        adminStatusText = "Loop disabled"
        refocusGameplay()
    }

    func copySongSection(_ id: UUID) {
        guard let section = adminSections.first(where: { $0.id == id }),
              let range = songSectionRange(id: id) else {
            adminStatusText = "Unable to determine section range"
            return
        }
        let notes = adminNotes
            .filter { $0.time >= range.lowerBound && $0.time < range.upperBound }
            .sorted { $0.time < $1.time }
        let noteClipboard = notes.map { AdminClipboardNote(lane: $0.lane, relativeTime: $0.time - section.startTime) }
        adminSectionClipboard = AdminSectionClipboard(
            name: section.name,
            colorName: section.colorName,
            duration: max(section.endTime - section.startTime, stepInterval),
            notes: noteClipboard
        )
        selectedAdminSectionID = id
        adminStatusText = "Copied section \(section.name)"
    }

    func pasteSongSectionAtPlayhead() {
        let liveTime = audio.state == .playing ? audio.currentTime : stepCursorTime
        pasteSongSection(atTime: liveTime)
    }

    func pasteSongSection(atTime time: Double) {
        guard let clipboard = adminSectionClipboard else {
            adminStatusText = "No copied section available"
            return
        }

        let desiredStart = quantizedAdminGridTime(for: time)
        let duration = max(clipboard.duration, stepInterval)
        let existingSections = adminSections.sorted { $0.startTime < $1.startTime }

        let effectiveStart: Double
        if let containingSection = existingSections.first(where: { desiredStart > $0.startTime + 0.0001 && desiredStart < $0.endTime - 0.0001 }) {
            effectiveStart = containingSection.endTime
        } else {
            effectiveStart = desiredStart
        }

        let previousSection = existingSections.last(where: { $0.endTime <= effectiveStart + 0.0001 })
        let nextSection = existingSections.first(where: { $0.startTime >= effectiveStart - 0.0001 })
        let startTime = max(effectiveStart, previousSection?.endTime ?? effectiveStart)
        let endLimit = nextSection?.startTime ?? max(playbackDuration, adminNotes.map(\.time).max() ?? 0, startTime + duration)
        let endTime = startTime + duration
        guard endTime <= endLimit + 0.0001 else {
            adminStatusText = "No room to paste copied section at or after the playhead"
            return
        }
        guard !existingSections.contains(where: { startTime < $0.endTime - 0.0001 && endTime > $0.startTime + 0.0001 }) else {
            adminStatusText = "Pasted section would overlap an existing section"
            return
        }

        let pastedSection = SongSection(name: clipboard.name, startTime: startTime, endTime: endTime, colorName: clipboard.colorName)
        let newNotes = clipboard.notes.map {
            NoteEvent(lane: $0.lane, time: isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: pastedSection.startTime + $0.relativeTime) : max(0, pastedSection.startTime + $0.relativeTime))
        }.filter { $0.time < pastedSection.endTime + 0.0001 }
        let updatedNotes = (adminNotes + newNotes).sorted { lhs, rhs in
            if abs(lhs.time - rhs.time) > 0.0001 { return lhs.time < rhs.time }
            return lhs.lane.rawValue < rhs.lane.rawValue
        }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updatedNotes, title: title, sections: existingSections + [pastedSection]), bpmOverride: bpm, chartStatus: "Pasted section", recordHistory: true)
        selectedAdminSectionID = pastedSection.id
        adminSelectedNoteIDs = Set(newNotes.map(\.id))
        adminSelectedNoteID = newNotes.first?.id
        adminStatusText = "Pasted section at playhead"
    }

    func copySongSectionNotes(_ id: UUID) {
        guard let range = songSectionRange(id: id) else {
            adminStatusText = "Unable to determine section range"
            return
        }
        let selectedNotes = adminNotes.filter { note in
            note.time >= range.lowerBound && note.time < range.upperBound
        }.sorted { $0.time < $1.time }
        guard let firstTime = selectedNotes.first?.time else {
            adminStatusText = "No notes found in section"
            return
        }
        adminClipboard = selectedNotes.map { AdminClipboardNote(lane: $0.lane, relativeTime: $0.time - firstTime) }
        adminSelectedNoteIDs = Set(selectedNotes.map(\.id))
        adminSelectedNoteID = selectedNotes.first?.id
        if let section = adminSections.first(where: { $0.id == id }) {
            selectedAdminSectionID = id
            adminStatusText = "Copied \(selectedNotes.count) notes from \(section.name)"
        } else {
            adminStatusText = "Copied \(selectedNotes.count) section notes"
        }
        refocusGameplay()
    }

    func pasteSongSectionNotes(atSection id: UUID) {
        guard let section = adminSections.first(where: { $0.id == id }) else { return }
        selectedAdminSectionID = id
        pasteAdminNotes(at: section.startTime)
    }

    func seekSectionTimeline(to time: Double) {
        let targetTime = isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: time) : max(0, min(playbackDuration, time))
        clearAdminSelection()
        selectSongSection(nil)
        let wasPlaying = audio.state == .playing
        adminScrubPreviewTargetTime = nil
        adminScrubPreviewTime = nil
        audio.seek(to: targetTime)
        moveStepCursor(to: targetTime, seekPlayback: false)
        refreshAdminVisibleNotes(at: targetTime)
        if wasPlaying {
            audio.play()
        }
        syncTransportState()
        adminStatusText = "Moved to \(sectionBarBeatText(for: targetTime))"
        refocusGameplay()
    }

    func addAdminNote() {
        let snappedTime = isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: adminNoteTime) : max(0, adminNoteTime)
        let note = NoteEvent(lane: adminSelectedLane, time: snappedTime)
        appendAdminNote(note)
        adminStatusText = "Added \(note.lane.displayName) at \(String(format: "%.2f", note.time))s"
        refocusGameplay()
    }

    func addAdminNote(at time: Double, lane: Lane) {
        let baseTime = max(0, min(playbackDuration, time))
        let snappedTime = isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: baseTime) : baseTime
        let note = NoteEvent(lane: lane, time: snappedTime)
        appendAdminNote(note)
        adminSelectedLane = lane
        adminNoteTime = note.time
        adminStatusText = "Added \(note.lane.displayName) at \(String(format: "%.2f", note.time))s"
        refocusGameplay()
    }

    func placeStepNote(_ lane: Lane? = nil) {
        let selectedLane = lane ?? adminSelectedLane
        let note = NoteEvent(lane: selectedLane, time: quantizedStepCursorTime())
        appendAdminNote(note)
        adminStatusText = "Placed \(selectedLane.displayName) at \(stepCursorDisplayText)"
        statusMessage = "Admin Step"
        refocusGameplay()
    }

    func stepBackward() {
        moveStepCursor(to: max(0, stepCursorTime - stepInterval), seekPlayback: true)
        auditionNotesNearStepCursor()
        adminStatusText = "Stepped backward to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func stepForward() {
        moveStepCursor(to: stepCursorTime + stepInterval, seekPlayback: true)
        auditionNotesNearStepCursor()
        adminStatusText = "Stepped forward to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func jumpBackwardBar() {
        moveStepCursor(to: max(0, stepCursorTime - barDuration), seekPlayback: true)
        auditionNotesNearStepCursor()
        adminStatusText = "Jumped back one bar to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func jumpForwardBar() {
        moveStepCursor(to: stepCursorTime + barDuration, seekPlayback: true)
        auditionNotesNearStepCursor()
        adminStatusText = "Jumped forward one bar to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func syncStepCursorToPlayback() {
        moveStepCursor(to: max(0, activeTransportTime), seekPlayback: false)
        adminStatusText = "Synced step cursor to playback: \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func setPlaybackRate(_ rate: Float) {
        audio.setPlaybackRate(rate)
        updatePlaybackRateText()
        adminStatusText = "Playback speed set to \(playbackRateText)"
        refocusGameplay()
    }

    func scrubTargetTime(from startTime: Double, translationHeight: Double, availableHeight: Double) -> Double {
        let height = max(availableHeight, 1)
        let normalizedDelta = -translationHeight / height
        let scaledDuration = max(playbackDuration, 0) * adminLaneScrubDurationMultiplier
        let unclampedTargetTime = startTime + (normalizedDelta * scaledDuration)
        return max(0, min(playbackDuration, unclampedTargetTime))
    }

    func adminDraggedNoteTime(from startTime: Double, translationHeight: Double, availableHeight: Double) -> Double {
        let height = max(availableHeight, 1)
        let normalizedDelta = translationHeight / height
        let scaledDuration = max(playbackDuration, 0) * adminNoteDragDurationMultiplier
        let unclampedTargetTime = startTime + (normalizedDelta * scaledDuration)
        return max(0, min(playbackDuration, unclampedTargetTime))
    }

    func adminNoteTime(at scenePoint: CGPoint) -> Double {
        let deltaY = Double(scenePoint.y - scene.hitLineYPosition)
        let unclampedTime = scene.currentSongTime + (deltaY / adminAuthoringNoteSpeed)
        return max(0, min(playbackDuration, unclampedTime))
    }

    func seekTransport(to time: Double) {
        audio.seek(to: time)
        finalizeAdminScrub(at: time, announce: false)
        syncTransportState()
        adminStatusText = "Seeked to \(playbackTimeText)"
        refocusGameplay()
    }

    func updateAdminScrubPreview(to time: Double) {
        let clampedTime = max(0, min(playbackDuration, time))
        if adminScrubPreviewTime == nil {
            adminScrubPreviewTime = clampedTime
        }
        adminScrubPreviewTargetTime = clampedTime
    }

    func resolvedAdminScrubTime(for previewTime: Double) -> Double {
        guard isNoteLaneSnapEnabled else {
            adminSelectedNoteID = nil
            return previewTime
        }
        adminSelectedNoteID = nil
        return quantizedAdminGridTime(for: previewTime)
    }

    func finalizeAdminScrub(at time: Double, announce: Bool = true) {
        adminScrubPreviewTargetTime = nil
        adminScrubPreviewTime = nil
        moveStepCursor(to: time, seekPlayback: false)
        if loopLength != .off {
            loopStartTime = quantizedLoopStart(for: time)
            updateLoopStatusText()
        }
        refreshAdminVisibleNotes(at: time)
        if announce {
            adminStatusText = "Scrubbed to \(String(format: "%.2f", time))s"
        }
    }

    func setLoopLength(_ length: LoopLength) {
        customLoopRange = nil
        selectedAdminSectionID = nil
        loopLength = length
        loopStartTime = quantizedLoopStart(for: audio.currentTime)
        updateLoopStatusText()
        adminStatusText = length == .off ? "Loop disabled" : "Looping \(length.rawValue) from current position"
        refocusGameplay()
    }

    func selectAdminNote(_ id: UUID, extendSelection: Bool = false) {
        if extendSelection {
            if adminSelectedNoteIDs.contains(id) {
                adminSelectedNoteIDs.remove(id)
            } else {
                adminSelectedNoteIDs.insert(id)
            }
            adminSelectedNoteID = adminSelectedNoteIDs.first
        } else {
            adminSelectedNoteIDs = [id]
            adminSelectedNoteID = id
        }
    }

    func clearAdminSelection() {
        adminSelectedNoteIDs = []
        adminSelectedNoteID = nil
    }

    func copySelectedAdminNotes() {
        let selectedNotes = adminNotes.filter { adminSelectedNoteIDs.contains($0.id) }.sorted { $0.time < $1.time }
        guard let firstTime = selectedNotes.first?.time else {
            adminStatusText = "No notes selected to copy"
            return
        }
        adminClipboard = selectedNotes.map {
            AdminClipboardNote(lane: $0.lane, relativeTime: $0.time - firstTime)
        }
        adminStatusText = "Copied \(selectedNotes.count) notes"
    }

    func cutSelectedAdminNotes() {
        copySelectedAdminNotes()
        deleteSelectedAdminNotes(statusPrefix: "Cut")
    }

    func pasteAdminNotes(at baseTime: Double? = nil) {
        guard !adminClipboard.isEmpty else {
            adminStatusText = "Clipboard is empty"
            return
        }
        let anchorTime = baseTime ?? quantizedStepCursorTime()
        let newNotes = adminClipboard.map {
            NoteEvent(lane: $0.lane, time: isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: anchorTime + $0.relativeTime) : max(0, anchorTime + $0.relativeTime))
        }
        let updated = (adminNotes + newNotes).sorted { lhs, rhs in
            if abs(lhs.time - rhs.time) > 0.0001 { return lhs.time < rhs.time }
            return lhs.lane.rawValue < rhs.lane.rawValue
        }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title, sections: adminSections), bpmOverride: bpm, chartStatus: "Pasted \(newNotes.count) notes", recordHistory: true)
        adminSelectedNoteIDs = Set(newNotes.map(\.id))
        adminSelectedNoteID = newNotes.first?.id
        adminStatusText = "Pasted \(newNotes.count) notes"
        refocusGameplay()
    }

    func deleteSelectedAdminNotes(statusPrefix: String = "Deleted") {
        guard !adminSelectedNoteIDs.isEmpty else {
            adminStatusText = "No notes selected"
            return
        }
        let updated = adminNotes.filter { !adminSelectedNoteIDs.contains($0.id) }
        let removedCount = adminNotes.count - updated.count
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title, sections: adminSections), bpmOverride: bpm, chartStatus: "Edited chart notes", recordHistory: true)
        clearAdminSelection()
        adminStatusText = "\(statusPrefix) \(removedCount) notes"
        refocusGameplay()
    }

    func jumpToAdminNote(_ id: UUID) {
        guard let note = adminNotes.first(where: { $0.id == id }) else { return }
        adminSelectedNoteIDs = [id]
        adminSelectedNoteID = id
        seekTransport(to: note.time)
        adminStatusText = "Jumped to \(note.lane.displayName) at \(String(format: "%.2f", note.time))s"
        refocusGameplay()
    }

    func deleteAdminNote(_ id: UUID) {
        let updated = adminNotes.filter { $0.id != id }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title, sections: adminSections), bpmOverride: bpm, chartStatus: "Edited chart notes", recordHistory: true)
        adminSelectedNoteIDs.remove(id)
        if adminSelectedNoteID == id {
            adminSelectedNoteID = adminSelectedNoteIDs.first
        }
        adminStatusText = "Deleted note. \(updated.count) notes remain."
        refocusGameplay()
    }

    func previewAdminNoteMove(_ id: UUID, to time: Double, yPosition: CGFloat, lane: Lane? = nil) {
        let clampedTime = max(0, min(playbackDuration, time))
        scene.previewAdminNoteMove(id: id, time: clampedTime, yPosition: yPosition, lane: lane, smoothingFactor: adminNoteDragSmoothingFactor)
    }

    func clearAdminNoteMovePreview(_ id: UUID? = nil) {
        scene.clearAdminNoteMovePreview(for: id)
    }

    func moveAdminNote(_ id: UUID, to time: Double, lane: Lane? = nil) {
        guard let existingNote = adminNotes.first(where: { $0.id == id }) else { return }
        let baseTime = max(0, min(playbackDuration, time))
        let clampedTime = isNoteLaneSnapEnabled ? quantizedAdminGridTime(for: baseTime) : baseTime
        let targetLane = lane ?? existingNote.lane
        let updated = adminNotes.map { note in
            guard note.id == id else { return note }
            return NoteEvent(id: id, lane: targetLane, time: clampedTime)
        }.sorted { lhs, rhs in
            if abs(lhs.time - rhs.time) > 0.0001 {
                return lhs.time < rhs.time
            }
            return lhs.lane.rawValue < rhs.lane.rawValue
        }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title, sections: adminSections), bpmOverride: bpm, chartStatus: "Edited chart notes", recordHistory: true)
        if let movedNote = adminNotes.first(where: { $0.id == id }) {
            adminSelectedNoteID = movedNote.id
            moveStepCursor(to: movedNote.time, seekPlayback: false)
            adminStatusText = "Moved \(movedNote.lane.displayName) to \(String(format: "%.2f", movedNote.time))s"
        } else {
            adminStatusText = "Moved note to \(String(format: "%.2f", clampedTime))s"
        }
        syncTransportState()
        refocusGameplay()
    }

    func noteCount(for lane: Lane) -> Int { adminNotes.filter { $0.lane == lane }.count }

    func saveAdminChartDocument() {
        guard let url = chartFileStore.chooseChartFileForSave(defaultName: chartName) else { refocusGameplay(); return }
        do {
            let currentChart = Chart(notes: adminNotes, title: chartName, sections: adminSections)
            try chartFileStore.save(chart: currentChart, bpm: bpm, songOffset: songOffset, timelineDuration: adminTimelineDuration, timingContractVersion: importedChartTiming?.contractVersion ?? "0.1.0", ticksPerBeat: ticksPerBeat, timeSignatureNumerator: beatsPerBar, timeSignatureDenominator: timeSignatureDenominator, timingSource: hasManualTimingOverride ? "manual_override" : (importedChartTiming?.source ?? "manual"), to: url)
            activeAdminChartURL = url
            persistLastOpenedChartURL(url)
            adminStatusText = "Saved chart to \(url.lastPathComponent)"
            chartStatusText = "Saved chart file \(url.lastPathComponent)"
        } catch {
            adminStatusText = "Save failed: \(error.localizedDescription)"
        }
        refocusGameplay()
    }

    func loadAdminChartDocument() {
        guard let url = chartFileStore.chooseChartFileForOpen() else { refocusGameplay(); return }
        do {
            let loaded = try chartFileStore.loadChart(from: url)
            activeAdminChartURL = url
            importedChartTiming = loaded.timing
            hasManualTimingOverride = false
            persistLastOpenedChartURL(url)
            adminTimelineDuration = max(loaded.timelineDuration ?? 0, loaded.chart.endTime, playbackDuration, 1)
            applyChart(loaded.chart, bpmOverride: loaded.bpm, chartStatus: "Loaded chart file \(url.lastPathComponent)", recordHistory: true, persistLoadedChart: false)
            syncBPMStateFromCurrentSources()
            adminStatusText = "Loaded chart JSON \(url.lastPathComponent)"
            stepCursorTime = 0
            updateStepCursorDisplay()
        } catch {
            adminStatusText = "Load failed: \(error.localizedDescription)"
        }
        refocusGameplay()
    }

    func playTransport() {
        startTransport(at: adminScrubPreviewTime ?? activeTransportTime)
    }
    func pauseTransport() {
        isChartAuditionActive = false
        chartPreviewTimerCancellable?.cancel()
        chartPreviewTimerCancellable = nil
        if isChartOnlyPlaybackEnabled {
            stopChartOnlyPlaybackIfNeeded(resetTime: false)
            adminStatusText = "Chart-only playback off"
        } else {
            audio.pause()
        }
        syncTransportState()
        refocusGameplay()
    }

    func toggleMetronome() {
        isMetronomeEnabled.toggle()
        lastMetronomeSubdivisionIndex = nil
        adminStatusText = isMetronomeEnabled ? "Metronome on" : "Metronome off"
        refocusGameplay()
    }

    func toggleChartOnlyPlayback() {
        if isChartOnlyPlaybackEnabled {
            stopChartOnlyPlaybackIfNeeded(resetTime: false)
            adminStatusText = "Chart-only playback off"
        } else {
            guard !session.chart.notes.isEmpty else {
                adminStatusText = "Load a chart first"
                refocusGameplay()
                return
            }
            let startTime = adminScrubPreviewTime ?? audio.currentTime
            audio.pause()
            chartPreviewClock.stop()
            chartPreviewClock.seek(to: startTime)
            adminScrubPreviewTime = nil
            adminScrubPreviewTargetTime = nil
            lastChartPlaybackTriggeredNoteIDs.removeAll()
            chartPreviewLastAuditionTime = max(0, startTime - 0.02)
            lastMetronomeSubdivisionIndex = nil
            isChartOnlyPlaybackEnabled = true
            isChartAuditionActive = !isChartMuted
            chartPreviewClock.play()
            if !isChartMuted {
                startChartPreviewTimer()
            }
            refreshAdminVisibleNotes(at: startTime)
            adminStatusText = "Chart-only playback on at \(displayPositionText(for: startTime))"
        }
        syncTransportState()
        refocusGameplay()
    }

    func toggleAudioMute() {
        audio.toggleMute()
        isAudioMuted = audio.isMuted
        adminStatusText = isAudioMuted ? "Audio muted" : "Audio unmuted"
        refocusGameplay()
    }

    func toggleChartMute() {
        isChartMuted.toggle()
        if isChartMuted {
            isChartAuditionActive = false
            chartPreviewTimerCancellable?.cancel()
            chartPreviewTimerCancellable = nil
        } else if activeTransportState == .playing && !session.chart.notes.isEmpty {
            isChartAuditionActive = true
            chartPreviewLastAuditionTime = max(0, activeTransportTime - 0.02)
            startChartPreviewTimer()
        }
        adminStatusText = isChartMuted ? "Chart muted" : "Chart unmuted"
        refocusGameplay()
    }

    func unloadChart() {
        stopChartOnlyPlaybackIfNeeded(resetTime: true)
        activeAdminChartURL = nil
        importedChartTiming = nil
        hasManualTimingOverride = false
        let title = trackName == "No audio loaded" ? "Untitled Chart" : trackName
        activeDisplayLaneBlueprint = nil
        applyChart(Chart(notes: [], title: title, sections: [], displayLaneBlueprint: nil), bpmOverride: bpm, chartStatus: "Chart unloaded", recordHistory: true, persistLoadedChart: false)
        adminStatusText = "Chart unloaded"
        refocusGameplay()
    }

    func unloadAudio() {
        stopChartOnlyPlaybackIfNeeded(resetTime: true)
        audio.unloadAudio()
        isAudioMuted = audio.isMuted
        chartAssociationStatusText = "Load audio to auto-match a chart."
        trackName = "No audio loaded"
        adminStatusText = "Audio unloaded"
        syncBPMStateFromCurrentSources()
        syncTransportState()
        refocusGameplay()
    }

    func playFromStart() {
        customLoopRange = nil
        if loopLength != .off {
            loopLength = .off
            updateLoopStatusText()
        }
        adminScrubPreviewTargetTime = nil
        adminScrubPreviewTime = nil
        moveStepCursor(to: 0, seekPlayback: false)
        refreshAdminVisibleNotes(at: 0)
        startTransport(at: 0)
        adminStatusText = "Playing from start"
        refocusGameplay()
    }

    func nudgeBPM(by delta: Double) {
        bpm = max(40, min(240, bpm + delta))
        hasManualTimingOverride = true
        bpmSourceText = "Manual Override"
        timingSourceText = "Manual Override"
        timingOverrideStatusText = importedChartTiming == nil ? "Using manual timing" : "Manual override active — chart timing kept visible for reference"
        midiTempoText = String(format: "%.1f BPM manual", bpm)
        updateStepCursorDisplay()
        updateLoopStatusText()
        syncTransportState()
        refocusGameplay()
    }

    func nudgeOffset(by delta: Double) {
        songOffset = max(-2, min(2, songOffset + delta))
        hasManualTimingOverride = true
        bpmSourceText = "Manual Override"
        timingSourceText = "Manual Override"
        timingOverrideStatusText = importedChartTiming == nil ? "Using manual timing" : "Manual override active — chart timing kept visible for reference"
        midiTempoText = String(format: "%.1f BPM / %.2fs manual", bpm, songOffset)
        updateStepCursorDisplay()
        syncTransportState()
        refocusGameplay()
    }

    func restartRun() {
        session.reset()
        isRunComplete = false
        statusMessage = "Restarted"
        audio.stop()
        scene.restartSong()
        scene.flashStatus("Restart")
        syncState()
        syncTransportState()
        refocusGameplay()
    }

    private func loadChart(from url: URL) {
        do {
            let isJSONChart = url.pathExtension.lowercased() == "json"
            if isJSONChart {
                let loaded = try chartFileStore.loadChart(from: url)
                activeAdminChartURL = url
                importedChartTiming = loaded.timing
                hasManualTimingOverride = false
                chartMatchCandidates = []
                isChartMatchPickerPresented = false
                chartAssociationStatusText = "Loaded chart: \(url.lastPathComponent)"
                persistLastOpenedChartURL(url)
                adminTimelineDuration = max(loaded.timelineDuration ?? 0, loaded.chart.endTime, playbackDuration, 1)
                applyChart(loaded.chart, bpmOverride: loaded.bpm, chartStatus: "Loaded chart file \(url.lastPathComponent) (\(loaded.chart.notes.count) notes)", recordHistory: true, persistLoadedChart: false)
                syncBPMStateFromCurrentSources()
                statusMessage = "Loaded chart \(loaded.chart.title) (\(loaded.chart.notes.count) notes)"
                adminStatusText = "Loaded chart JSON \(url.lastPathComponent) with \(loaded.chart.notes.count) notes"
            } else {
                let loaded = try midiLoader.loadChartData(from: url)
                activeAdminChartURL = nil
                importedChartTiming = nil
                hasManualTimingOverride = false
                chartAssociationStatusText = "Imported MIDI chart manually: \(url.lastPathComponent)"
                persistLastOpenedChartURL(nil)
                adminTimelineDuration = max(playbackDuration, loaded.chart.endTime, 1)
                applyChart(loaded.chart, bpmOverride: loaded.bpm, chartStatus: "Loaded \(loaded.chart.notes.count) notes from \(url.lastPathComponent)", recordHistory: true, persistLoadedChart: false)
                if let bpm = loaded.bpm {
                    bpmSourceText = "MIDI"
                    midiTempoText = String(format: "%.1f BPM from MIDI", bpm)
                } else {
                    midiTempoText = "No MIDI tempo event"
                }
                statusMessage = "Loaded chart \(loaded.chart.title)"
                adminStatusText = "Imported MIDI chart \(url.lastPathComponent)"
            }
            stepCursorTime = 0
            updateStepCursorDisplay()
            updateLoopStatusText()
        } catch {
            chartStatusText = "Chart load failed"
            statusMessage = error.localizedDescription
            adminStatusText = "Load failed: \(error.localizedDescription)"
        }
        refocusGameplay()
    }

    private func appendAdminNote(_ note: NoteEvent) {
        let occupancyTolerance = max(stepInterval * 0.45, 0.02)
        let filteredExisting = adminNotes.filter { existing in
            !(existing.lane == note.lane && abs(existing.time - note.time) <= occupancyTolerance)
        }
        let updated = (filteredExisting + [note]).sorted { $0.time < $1.time }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title, sections: adminSections), bpmOverride: bpm, chartStatus: "Recorded \(updated.count) chart notes", recordHistory: true)
        adminSelectedNoteID = note.id
    }

    private func autosaveLoadedAdminChartIfPossible() {
        guard let url = activeAdminChartURL else { return }
        do {
            let currentChart = Chart(notes: adminNotes, title: chartName, sections: adminSections)
            try chartFileStore.save(chart: currentChart, bpm: bpm, songOffset: songOffset, timelineDuration: adminTimelineDuration, timingContractVersion: importedChartTiming?.contractVersion ?? "0.1.0", ticksPerBeat: ticksPerBeat, timeSignatureNumerator: beatsPerBar, timeSignatureDenominator: timeSignatureDenominator, timingSource: hasManualTimingOverride ? "manual_override" : (importedChartTiming?.source ?? "manual"), to: url)
        } catch {
            chartStatusText = "Autosave failed"
            adminStatusText = "Autosave failed: \(error.localizedDescription)"
        }
    }

    private func normalizedAdminChartTitle() -> String {
        chartName == "Untitled Chart" ? (trackName == "No audio loaded" ? "Admin Chart" : trackName) : chartName
    }

    private func currentAdminHistoryEntry() -> AdminChartHistoryEntry {
        AdminChartHistoryEntry(
            chart: Chart(notes: adminNotes, title: chartName, sections: adminSections),
            bpm: bpm,
            selectedNoteID: adminSelectedNoteID,
            selectedNoteIDs: adminSelectedNoteIDs,
            selectedSectionID: selectedAdminSectionID
        )
    }

    private func restoreAdminHistoryEntry(_ entry: AdminChartHistoryEntry, statusText: String) {
        adminSelectedNoteID = entry.selectedNoteID
        adminSelectedNoteIDs = entry.selectedNoteIDs
        selectedAdminSectionID = entry.selectedSectionID
        applyChart(entry.chart, bpmOverride: entry.bpm, chartStatus: statusText, recordHistory: false)
        let validSelectedIDs = entry.selectedNoteIDs.intersection(Set(adminNotes.map(\.id)))
        adminSelectedNoteIDs = validSelectedIDs
        if let selectedID = entry.selectedNoteID,
           adminNotes.contains(where: { $0.id == selectedID }) {
            adminSelectedNoteID = selectedID
        } else {
            adminSelectedNoteID = validSelectedIDs.first
        }
        adminStatusText = statusText
        updateAdminHistoryAvailability()
        refocusGameplay()
    }

    private func updateAdminHistoryAvailability() {
        canUndoAdminEdit = !undoHistory.isEmpty
        canRedoAdminEdit = !redoHistory.isEmpty
    }

    private func applyChart(_ chart: Chart, bpmOverride: Double?, chartStatus: String, recordHistory: Bool = false, persistLoadedChart: Bool = true) {
        if recordHistory {
            undoHistory.append(currentAdminHistoryEntry())
            redoHistory.removeAll()
        }
        if let bpmOverride { bpm = bpmOverride }
        let resolvedLaneBlueprint = chart.displayLaneBlueprint ?? activeDisplayLaneBlueprint ?? chart.displayLanes
        let resolvedChart = Chart(notes: chart.notes, title: chart.title, sections: chart.sections, displayLaneBlueprint: resolvedLaneBlueprint)
        activeDisplayLaneBlueprint = resolvedLaneBlueprint
        session.replaceChart(resolvedChart)
        scene.replaceChart(resolvedChart)
        chartName = resolvedChart.title
        chartStatusText = chartStatus
        adminNotes = resolvedChart.notes.sorted { $0.time < $1.time }
        adminSections = resolvedChart.sections.sorted { $0.startTime < $1.startTime }
        adminTimelineDuration = max(adminTimelineDuration, resolvedChart.endTime, 1)
        if let selectedID = adminSelectedNoteID,
           !adminNotes.contains(where: { $0.id == selectedID }) {
            adminSelectedNoteID = nil
        }
        if let selectedSectionID = selectedAdminSectionID,
           !adminSections.contains(where: { $0.id == selectedSectionID }) {
            selectedAdminSectionID = nil
        }
        scene.selectedAdminNoteID = adminSelectedNoteID
        session.reset()
        isRunComplete = false
        scene.restartSong()
        syncState()
        syncTransportState()
        updateAdminHistoryAvailability()
        if persistLoadedChart {
            autosaveLoadedAdminChartIfPossible()
        }
    }

    private func handleTick(_ time: TimeInterval) {
        playbackTimeText = String(format: "%.2fs", time)
        handleMetronomeTick(at: time)

        if isAdminAuthoringActive {
            applyLoopIfNeeded(at: time)
            syncTransportState()
            return
        }

        guard !isRunComplete else { syncTransportState(); return }
        session.advanceMisses(at: time)
        if session.isComplete && time >= session.chart.endTime + completionGracePeriod {
            isRunComplete = true
            statusMessage = completionMessage()
            scene.flashStatus("Finished")
            audio.pause()
        }
        syncState()
        syncTransportState()
    }

    private func handleInput(_ event: InputEvent) {
        laneSoundPlayer.play(lane: event.lane)
        if isAdminAuthoringActive {
            if isAdminRecordMode {
                let note = NoteEvent(lane: event.lane, time: event.timestamp)
                appendAdminNote(note)
                adminStatusText = "Recorded \(event.lane.displayName) at \(displayPositionText(for: event.timestamp))"
                statusMessage = "Admin Record"
            } else {
                placeStepNote(event.lane)
                statusMessage = "Admin Step"
            }
            return
        }

        let judgment = session.registerHit(lane: event.lane, at: event.timestamp)
        scene.flashJudgment(judgment)
        scene.flashLane(event.lane)
        activeInputSourceName = event.source.rawValue
        statusMessage = judgment == .miss ? "Miss" : "Playing"
        syncState()
        syncTransportState()
    }

    private func applyLoopIfNeeded(at time: TimeInterval) {
        guard activeTransportState == .playing else { return }
        if isChartOnlyPlaybackEnabled {
            if let customLoopRange {
                if time >= customLoopRange.upperBound {
                    chartPreviewClock.seek(to: customLoopRange.lowerBound)
                    lastChartPlaybackTriggeredNoteIDs.removeAll()
                    chartPreviewLastAuditionTime = max(0, customLoopRange.lowerBound - 0.02)
                }
                return
            }
            guard loopLength != .off else { return }
            let start = loopStartTime
            let end = start + (barDuration * Double(loopLength.barCount))
            if time >= end {
                chartPreviewClock.seek(to: start)
                lastChartPlaybackTriggeredNoteIDs.removeAll()
                chartPreviewLastAuditionTime = max(0, start - 0.02)
            }
            return
        }
        if let customLoopRange {
            if time >= customLoopRange.upperBound {
                audio.seek(to: customLoopRange.lowerBound)
            }
            return
        }
        guard loopLength != .off else { return }
        let start = loopStartTime
        let end = start + (barDuration * Double(loopLength.barCount))
        if time >= end {
            audio.seek(to: start)
        }
    }

    private func syncState() {
        if isAdminAuthoringActive {
            score = 0; combo = 0; missCount = 0; hitCount = 0; lastJudgmentText = "—"; accuracyText = "—"
        } else {
            score = session.state.score
            combo = session.state.combo
            missCount = session.state.missCount
            hitCount = session.state.hitCount
            lastJudgmentText = session.state.lastJudgment?.rawValue ?? "—"
            accuracyText = String(format: "%.0f%%", session.state.accuracy * 100)
        }
        scene.updateVisibleNotes(currentSceneNotes(at: scene.currentSongTime))
        scene.selectedAdminNoteID = adminSelectedNoteID
        trackName = audio.loadedTrackName ?? "No audio loaded"
        chartName = session.chart.title
        adminNotes = session.chart.notes.sorted { $0.time < $1.time }
        adminSections = session.chart.sections.sorted { $0.startTime < $1.startTime }
    }

    private func syncTransportState() {
        let currentTime = adminScrubPreviewTime ?? activeTransportTime

        // Only update transportStateText if it changes (less frequent than playbackTimeText)
        let newTransportStateText = isChartOnlyPlaybackEnabled ? "Chart Preview" : audio.state.rawValue
        if transportStateText != newTransportStateText {
            transportStateText = newTransportStateText
        }

        // Throttle playback time text to avoid excessive SwiftUI re-renders
        // Only update at 10 Hz (every ~100ms) instead of 60 Hz
        let newPlaybackTimeText = String(format: "%.2fs", currentTime)
        if newPlaybackTimeText != lastPublishedPlaybackTimeText {
            playbackTimeText = newPlaybackTimeText
            lastPublishedPlaybackTimeText = newPlaybackTimeText
        }

        // Duration text changes rarely; only update if playback duration changes
        let newPlaybackDurationText = String(format: "%.2fs", playbackDuration)
        if playbackDurationText != newPlaybackDurationText {
            playbackDurationText = newPlaybackDurationText
        }

        let position = MusicalTransport.position(at: currentTime, bpm: bpm, songOffset: songOffset, beatsPerBar: beatsPerBar, subdivisionsPerBeat: max(stepResolution.subdivisionsPerBeat, 1), ticksPerBeat: ticksPerBeat)

        // Only update bar/beat if position changes
        let newBarBeatText = position.barBeatDivisionTickText
        if newBarBeatText != lastPublishedBarBeatText {
            barBeatText = newBarBeatText
            lastPublishedBarBeatText = newBarBeatText
        }

        let newMusicalSubdivisionText = String(position.subdivision)
        if newMusicalSubdivisionText != lastPublishedMusicalSubdivisionText {
            musicalSubdivisionText = newMusicalSubdivisionText
            lastPublishedMusicalSubdivisionText = newMusicalSubdivisionText
        }

        // Only update note ID when it actually changes
        let newNoteID = playbackNoteID(near: currentTime)
        if newNoteID != lastPublishedCurrentPlaybackNoteID {
            currentPlaybackNoteID = newNoteID
            lastPublishedCurrentPlaybackNoteID = newNoteID
        }

        refreshAdminVisibleNotes(at: currentTime)
    }

    private func playbackNoteID(near time: Double) -> UUID? {
        let tolerance = max(stepInterval * 0.5, 0.05)
        if let nearestActive = session.chart.notes.first(where: { abs($0.time - time) <= tolerance }) {
            return nearestActive.id
        }
        return session.chart.notes.last(where: { $0.time <= time + 0.02 })?.id
    }

    private func quantizedStepCursorTime() -> Double {
        quantizedAdminGridTime(for: stepCursorTime)
    }

    private func quantizedAdminGridTime(for time: Double) -> Double {
        let interval = stepInterval
        guard interval > 0 else { return max(0, time) }
        let adjustedTime = time - songOffset
        let quantizedAdjustedTime = (adjustedTime / interval).rounded() * interval
        return max(0, quantizedAdjustedTime + songOffset)
    }

    private var stepInterval: Double {
        let beatDuration = 60.0 / max(1, bpm)
        return beatDuration / Double(stepResolution.subdivisionsPerBeat)
    }

    private var barDuration: Double { (60.0 / max(1, bpm)) * Double(max(1, beatsPerBar)) }

    private var currentBarStartTime: Double {
        let bar = floor(max(0, stepCursorTime - songOffset) / barDuration)
        return (bar * barDuration) + songOffset
    }

    private func quantizedLoopStart(for time: Double) -> Double {
        let bar = floor(max(0, time - songOffset) / barDuration)
        return (bar * barDuration) + songOffset
    }

    private func moveStepCursor(to time: Double, seekPlayback: Bool) {
        stepCursorTime = max(0, time)
        updateStepCursorDisplay()
        updateLoopStatusText()
        if seekPlayback {
            let wasPlaying = activeTransportState == .playing
            if isChartOnlyPlaybackEnabled {
                chartPreviewClock.seek(to: stepCursorTime)
            } else {
                audio.seek(to: stepCursorTime)
            }
            if isAdminAuthoringActive {
                if wasPlaying {
                    adminScrubPreviewTime = nil
                    adminScrubPreviewTargetTime = nil
                    refreshAdminVisibleNotes(at: stepCursorTime)
                    if isChartOnlyPlaybackEnabled {
                        chartPreviewClock.play()
                    } else {
                        audio.play()
                    }
                } else {
                    adminScrubPreviewTime = stepCursorTime
                    adminScrubPreviewTargetTime = stepCursorTime
                    refreshAdminVisibleNotes(at: stepCursorTime)
                }
            }
            syncTransportState()
        }
    }

    private func updateStepCursorDisplay() {
        let position = MusicalTransport.position(at: stepCursorTime, bpm: bpm, songOffset: songOffset, beatsPerBar: beatsPerBar, subdivisionsPerBeat: max(stepResolution.subdivisionsPerBeat, 1), ticksPerBeat: ticksPerBeat)
        stepCursorDisplayText = "\(position.barBeatDivisionTickText) · \(String(format: "%.2f", quantizedStepCursorTime()))s"
    }

    private func updatePlaybackRateText() {
        playbackRateText = "\(Int(audio.playbackRate * 100))%"
    }

    private func refreshAdminVisibleNotes(at time: Double? = nil) {
        let visibleTime = time ?? audio.currentTime
        scene.updateVisibleNotes(currentSceneNotes(at: visibleTime))
    }

    private func currentSceneNotes(at time: Double) -> [NoteEvent] {
        if isAdminAuthoringActive {
            return session.chart.notes
        }
        return session.notes(visibleAt: time, leadTime: 3.0)
    }

    private func currentSceneTime(fallbackAudioTime: Double) -> Double {
        let baseTime = isChartOnlyPlaybackEnabled ? chartPreviewClock.currentTime : fallbackAudioTime
        guard let targetTime = adminScrubPreviewTargetTime else {
            return adminScrubPreviewTime ?? baseTime
        }

        let currentTime = adminScrubPreviewTime ?? targetTime
        let delta = targetTime - currentTime
        let nextTime: Double
        if abs(delta) < 0.001 {
            nextTime = targetTime
        } else {
            nextTime = currentTime + (delta * adminScrubSmoothingFactor)
        }

        adminScrubPreviewTime = nextTime
        return nextTime
    }

    var currentPlaybackTime: Double { activeTransportTime }
    var playbackDuration: Double { max(audio.duration, session.chart.endTime, 0) }
    var playbackProgress: Double {
        let duration = max(playbackDuration, 0)
        guard duration > 0 else { return 0 }
        return min(max(activeTransportTime / duration, 0), 1)
    }

    func isPlaybackRateSelected(_ rate: Float) -> Bool {
        abs(audio.playbackRate - rate) < 0.001
    }

    private var activeTransportTime: Double {
        isChartOnlyPlaybackEnabled ? chartPreviewClock.currentTime : audio.currentTime
    }

    private var activeTransportState: TransportState {
        isChartOnlyPlaybackEnabled ? chartPreviewClock.state : audio.state
    }

    private func updateLoopStatusText() {
        if let customLoopRange {
            loopStatusText = "Section Loop · \(String(format: "%.2f", customLoopRange.lowerBound))s–\(String(format: "%.2f", customLoopRange.upperBound))s"
        } else if loopLength == .off {
            loopStatusText = "Loop Off"
        } else {
            let start = loopStartTime
            let end = start + (barDuration * Double(loopLength.barCount))
            loopStatusText = "\(loopLength.rawValue) · \(String(format: "%.2f", start))s–\(String(format: "%.2f", end))s"
        }
    }

    func songSectionRange(id: UUID) -> ClosedRange<Double>? {
        guard let section = adminSections.first(where: { $0.id == id }) else { return nil }
        return section.startTime...max(section.endTime, section.startTime + 0.001)
    }

    func displayTimeText(for time: Double) -> String {
        String(format: "%.2fs", time)
    }

    func displayPositionText(for time: Double) -> String {
        MusicalTransport.position(
            at: time,
            bpm: bpm,
            songOffset: songOffset,
            beatsPerBar: beatsPerBar,
            subdivisionsPerBeat: max(stepResolution.subdivisionsPerBeat, 1),
            ticksPerBeat: ticksPerBeat
        ).barBeatDivisionTickText
    }

    func sectionBarBeatText(for time: Double) -> String {
        displayPositionText(for: time)
    }

    private func stopChartOnlyPlaybackIfNeeded(resetTime: Bool) {
        guard isChartOnlyPlaybackEnabled else { return }
        chartPreviewClock.pause()
        if resetTime {
            chartPreviewClock.stop()
        }
        adminScrubPreviewTime = nil
        adminScrubPreviewTargetTime = nil
        isChartOnlyPlaybackEnabled = false
        isChartAuditionActive = false
        chartPreviewTimerCancellable?.cancel()
        chartPreviewTimerCancellable = nil
        lastChartPlaybackTriggeredNoteIDs.removeAll()
        chartPreviewLastAuditionTime = nil
        lastMetronomeSubdivisionIndex = nil
    }

    private func handleMetronomeTick(at time: Double) {
        guard isMetronomeEnabled, bpm > 0 else { return }
        let subdivisionDuration = stepInterval
        guard subdivisionDuration > 0 else { return }
        let adjusted = max(0, time - songOffset)
        let subdivisionIndex = Int(floor(adjusted / subdivisionDuration))
        guard subdivisionIndex != lastMetronomeSubdivisionIndex else { return }
        lastMetronomeSubdivisionIndex = subdivisionIndex
        let isBeat = subdivisionIndex % max(stepResolution.subdivisionsPerBeat, 1) == 0
        guard isBeat else { return }
        let beatIndex = subdivisionIndex / max(stepResolution.subdivisionsPerBeat, 1)
        let isDownbeat = beatIndex % max(beatsPerBar, 1) == 0
        laneSoundPlayer.playMetronome(isDownbeat: isDownbeat)
    }

    private func handleChartOnlyPlaybackTick(at time: Double) {
        guard isChartAuditionActive else { return }
        let previousTime = chartPreviewLastAuditionTime ?? (time - 0.02)
        let dueNotes = session.chart.notes.filter { note in
            note.time >= previousTime && note.time <= time + 0.02
        }
        for note in dueNotes {
            laneSoundPlayer.play(lane: note.lane)
            lastChartPlaybackTriggeredNoteIDs.insert(note.id)
        }
        chartPreviewLastAuditionTime = time
        if isChartOnlyPlaybackEnabled && time >= max(session.chart.endTime + 0.05, 0.05) {
            stopChartOnlyPlaybackIfNeeded(resetTime: true)
            adminStatusText = "Chart-only playback finished"
        } else if !isChartOnlyPlaybackEnabled && activeTransportState != .playing {
            isChartAuditionActive = false
            chartPreviewTimerCancellable?.cancel()
            chartPreviewTimerCancellable = nil
        }
    }

    private func startTransport(at startTime: Double) {
        let hasAudio = audio.loadedTrackName != nil
        let hasChart = !session.chart.notes.isEmpty
        guard hasAudio || hasChart else {
            adminStatusText = "Load audio or chart first"
            refocusGameplay()
            return
        }

        adminScrubPreviewTime = nil
        adminScrubPreviewTargetTime = nil

        if hasAudio {
            stopChartOnlyPlaybackIfNeeded(resetTime: false)
            audio.seek(to: startTime)
            audio.play()
        } else {
            chartPreviewClock.stop()
            chartPreviewClock.seek(to: startTime)
            isChartOnlyPlaybackEnabled = true
            chartPreviewClock.play()
        }

        if hasChart && !isChartMuted {
            isChartAuditionActive = true
            lastChartPlaybackTriggeredNoteIDs.removeAll()
            chartPreviewLastAuditionTime = startTime - 0.02
            handleChartOnlyPlaybackTick(at: startTime)
            startChartPreviewTimer()
        } else {
            isChartAuditionActive = false
        }

        syncTransportState()
        refocusGameplay()
    }

    private func startChartPreviewTimer() {
        chartPreviewTimerCancellable?.cancel()
        chartPreviewTimerCancellable = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let time = self.activeTransportTime
                self.handleChartOnlyPlaybackTick(at: time)
                self.syncTransportState()
            }
    }

    private func auditionNotesNearStepCursor() {
        let targetTime = quantizedStepCursorTime()
        let notes = session.chart.notes.filter { abs($0.time - targetTime) <= max(stepInterval * 0.45, 0.02) }
        for note in notes {
            laneSoundPlayer.play(lane: note.lane)
        }
    }

    private func normalizedSectionName(_ proposedName: String?) -> String {
        let trimmed = proposedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        let defaults = ["Intro", "Verse", "Chorus", "Bridge", "Fill", "Outro"]
        let usedNames = Set(adminSections.map(\.name))
        for name in defaults where !usedNames.contains(name) {
            return name
        }
        return "Section \(adminSections.count + 1)"
    }

    private func refocusGameplay() { gameplayFocusVersion += 1 }

    private func completionMessage() -> String {
        "Run complete · \(hitCount) hits · \(missCount) misses · \(accuracyText) accuracy"
    }
}
