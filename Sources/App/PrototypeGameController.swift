import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class PrototypeGameController: ObservableObject {
    enum StepResolution: String, CaseIterable, Identifiable {
        case quarter = "1/4"
        case eighth = "1/8"
        case sixteenth = "1/16"

        var id: String { rawValue }
        var subdivisionsPerBeat: Int {
            switch self {
            case .quarter: return 1
            case .eighth: return 2
            case .sixteenth: return 4
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
    @Published private(set) var trackName: String = "Preview clock"
    @Published private(set) var chartName: String = Chart.prototype.title
    @Published private(set) var chartStatusText: String = "Prototype chart loaded"
    @Published private(set) var transportStateText: String = TransportState.stopped.rawValue
    @Published private(set) var playbackTimeText: String = "0.00s"
    @Published private(set) var barBeatText: String = "1:1"
    @Published private(set) var musicalSubdivisionText: String = "1"
    @Published private(set) var bpmSourceText: String = "Manual"
    @Published private(set) var bpmAnalysisStatusText: String = "Idle"
    @Published private(set) var bpmAnalysisDetailText: String = "No file analyzed yet"
    @Published private(set) var midiTempoText: String = "Not loaded"
    @Published private(set) var gameplayFocusVersion: Int = 0
    @Published private(set) var playbackRateText: String = "100%"
    @Published private(set) var playbackDurationText: String = "0.00s"
    @Published private(set) var loopStatusText: String = "Loop Off"
    @Published var adminSelectedNoteID: UUID? {
        didSet {
            scene.selectedAdminNoteID = adminSelectedNoteID
        }
    }
    @Published private(set) var adminScrubPreviewTime: Double?
    @Published var bpm: Double = 120
    @Published var songOffset: Double = 0

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
    @Published var stepResolution: StepResolution = .sixteenth
    @Published var stepCursorTime: Double = 0
    @Published private(set) var stepCursorDisplayText: String = "1:1 · 0.00s"
    @Published var loopLength: LoopLength = .off
    @Published private(set) var loopStartTime: Double = 0
    @Published var isNoteLaneSnapEnabled: Bool = true

    let scene: GameplayScene
    let audio: AudioPlaybackController

    private let session: GameSession
    private let inputRouter: InputRouter
    private let midiLoader = MIDIChartLoader()
    private let chartFileStore = ChartFileStore()
    private let laneSoundPlayer = LaneSoundPlayer()
    private let completionGracePeriod: TimeInterval = 0.5
    private let adminLaneScrubDurationMultiplier: Double = 0.08
    private let adminScrubSmoothingFactor: Double = 0.35
    private let adminAuthoringNoteSpeed: Double = 110
    private let noteLaneHitLineHeight: Double = 6
    private var adminScrubPreviewTargetTime: Double?

    var isAdminAuthoringActive: Bool { isAdminPageActive }

    init() {
        let initialChart = Chart.prototype
        self.session = GameSession(chart: initialChart)
        let keyboard = KeyboardInputDevice()
        self.inputRouter = InputRouter(activeDevice: keyboard)
        self.audio = AudioPlaybackController()
        self.scene = GameplayScene(chart: initialChart, keyboardInputDevice: keyboard)
        self.scene.isAdminAuthoringMode = false
        self.activeInputSourceName = keyboard.source.rawValue
        self.chartName = initialChart.title
        self.adminNotes = initialChart.notes

        self.scene.timeProvider = { [weak self, weak audio] in
            if let self {
                return self.currentSceneTime(fallbackAudioTime: audio?.currentTime ?? 0)
            }
            return audio?.currentTime ?? 0
        }
        self.inputRouter.onInput = { [weak self] event in self?.handleInput(event) }
        self.scene.onInput = { [weak self] event in self?.inputRouter.route(event) }
        self.scene.onTick = { [weak self] time in self?.handleTick(time) }

        syncState()
        syncTransportState()
        updateStepCursorDisplay()
        updatePlaybackRateText()
        updateLoopStatusText()
        scene.selectedAdminNoteID = adminSelectedNoteID
    }

    func chooseAudioFile() {
        audio.chooseAudioFile()
        if let loadedTrackName = audio.loadedTrackName {
            trackName = loadedTrackName
            statusMessage = "Loaded \(loadedTrackName)"
        }
        if let detected = audio.detectedBPM {
            bpm = detected.bpm
            bpmSourceText = detected.source.capitalized
        } else {
            bpmSourceText = "Manual"
        }
        bpmAnalysisStatusText = audio.analysisDebug.status
        bpmAnalysisDetailText = audio.analysisDebug.detail
        updateStepCursorDisplay()
        syncTransportState()
        refocusGameplay()
    }

    func chooseChartFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose chart file"
        panel.allowedContentTypes = chartContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            refocusGameplay(); return
        }
        loadChart(from: url)
    }

    func startAdminChart() {
        let chart = Chart(notes: [], title: trackName == "Preview clock" ? "Untitled Chart" : trackName)
        applyChart(chart, bpmOverride: bpm, chartStatus: "Started empty admin chart")
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

    func clearAdminNotes() {
        let title = chartName == Chart.prototype.title ? "Admin Chart" : chartName
        applyChart(Chart(notes: [], title: title), bpmOverride: bpm, chartStatus: "Cleared chart notes")
        adminStatusText = "Cleared chart notes."
        stepCursorTime = 0
        updateStepCursorDisplay()
        refocusGameplay()
    }

    func addAdminNote() {
        let note = NoteEvent(lane: adminSelectedLane, time: max(0, adminNoteTime))
        appendAdminNote(note)
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
        adminStatusText = "Stepped backward to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func stepForward() {
        moveStepCursor(to: stepCursorTime + stepInterval, seekPlayback: true)
        adminStatusText = "Stepped forward to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func jumpBackwardBar() {
        moveStepCursor(to: max(0, stepCursorTime - barDuration), seekPlayback: true)
        adminStatusText = "Jumped back one bar to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func jumpForwardBar() {
        moveStepCursor(to: stepCursorTime + barDuration, seekPlayback: true)
        adminStatusText = "Jumped forward one bar to \(stepCursorDisplayText)"
        refocusGameplay()
    }

    func syncStepCursorToPlayback() {
        moveStepCursor(to: max(0, audio.currentTime), seekPlayback: false)
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
        let normalizedDelta = translationHeight / height
        let scaledDuration = max(playbackDuration, 0) * adminLaneScrubDurationMultiplier
        let unclampedTargetTime = startTime + (normalizedDelta * scaledDuration)
        return max(0, min(playbackDuration, unclampedTargetTime))
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
        guard isNoteLaneSnapEnabled, let nearestNote = nearestAdminNote(to: previewTime) else {
            adminSelectedNoteID = nil
            return previewTime
        }
        adminSelectedNoteID = nearestNote.id
        return nearestNote.time
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
        loopLength = length
        loopStartTime = quantizedLoopStart(for: audio.currentTime)
        updateLoopStatusText()
        adminStatusText = length == .off ? "Loop disabled" : "Looping \(length.rawValue) from current position"
        refocusGameplay()
    }

    func jumpToAdminNote(_ id: UUID) {
        guard let note = adminNotes.first(where: { $0.id == id }) else { return }
        adminSelectedNoteID = id
        seekTransport(to: note.time)
        adminStatusText = "Jumped to \(note.lane.displayName) at \(String(format: "%.2f", note.time))s"
        refocusGameplay()
    }

    func deleteAdminNote(_ id: UUID) {
        let updated = adminNotes.filter { $0.id != id }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title), bpmOverride: bpm, chartStatus: "Edited chart notes")
        if adminSelectedNoteID == id {
            adminSelectedNoteID = nil
        }
        adminStatusText = "Deleted note. \(updated.count) notes remain."
        refocusGameplay()
    }

    func previewAdminNoteMove(_ id: UUID, to time: Double) {
        let clampedTime = max(0, min(playbackDuration, time))
        scene.previewAdminNoteMove(id: id, time: clampedTime)
        adminStatusText = "Moving note to \(String(format: "%.2f", clampedTime))s"
    }

    func clearAdminNoteMovePreview(_ id: UUID? = nil) {
        scene.clearAdminNoteMovePreview(for: id)
    }

    func moveAdminNote(_ id: UUID, to time: Double) {
        guard let existingNote = adminNotes.first(where: { $0.id == id }) else { return }
        let clampedTime = max(0, min(playbackDuration, time))
        let updated = adminNotes.map { note in
            guard note.id == id else { return note }
            return NoteEvent(id: id, lane: existingNote.lane, time: clampedTime)
        }.sorted { lhs, rhs in
            if abs(lhs.time - rhs.time) > 0.0001 {
                return lhs.time < rhs.time
            }
            return lhs.lane.rawValue < rhs.lane.rawValue
        }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title), bpmOverride: bpm, chartStatus: "Edited chart notes")
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
            try chartFileStore.save(chart: session.chart, bpm: bpm, to: url)
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
            applyChart(loaded.chart, bpmOverride: loaded.bpm, chartStatus: "Loaded chart file \(url.lastPathComponent)")
            adminStatusText = "Loaded chart JSON \(url.lastPathComponent)"
            stepCursorTime = 0
            updateStepCursorDisplay()
        } catch {
            adminStatusText = "Load failed: \(error.localizedDescription)"
        }
        refocusGameplay()
    }

    func playTransport() { audio.play(); syncTransportState(); refocusGameplay() }
    func pauseTransport() { audio.pause(); syncTransportState(); refocusGameplay() }

    func nudgeBPM(by delta: Double) {
        bpm = max(40, min(240, bpm + delta))
        bpmSourceText = "Manual"
        updateStepCursorDisplay()
        updateLoopStatusText()
        syncTransportState()
        refocusGameplay()
    }

    func nudgeOffset(by delta: Double) {
        songOffset = max(-2, min(2, songOffset + delta))
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
            let loaded = try midiLoader.loadChartData(from: url)
            applyChart(loaded.chart, bpmOverride: loaded.bpm, chartStatus: "Loaded \(loaded.chart.notes.count) notes from \(url.lastPathComponent)")
            if let bpm = loaded.bpm {
                bpmSourceText = "MIDI"
                midiTempoText = String(format: "%.1f BPM from MIDI", bpm)
            } else {
                midiTempoText = "No MIDI tempo event"
            }
            statusMessage = "Loaded chart \(loaded.chart.title)"
            adminStatusText = "Imported MIDI chart \(url.lastPathComponent)"
            stepCursorTime = 0
            updateStepCursorDisplay()
            updateLoopStatusText()
        } catch {
            chartStatusText = "Chart load failed"
            statusMessage = error.localizedDescription
        }
        refocusGameplay()
    }

    private func appendAdminNote(_ note: NoteEvent) {
        let updated = (adminNotes + [note]).sorted { $0.time < $1.time }
        let title = normalizedAdminChartTitle()
        applyChart(Chart(notes: updated, title: title), bpmOverride: bpm, chartStatus: "Recorded \(updated.count) chart notes")
        adminSelectedNoteID = note.id
    }

    private func normalizedAdminChartTitle() -> String {
        chartName == Chart.prototype.title ? (trackName == "Preview clock" ? "Admin Chart" : trackName) : chartName
    }

    private func applyChart(_ chart: Chart, bpmOverride: Double?, chartStatus: String) {
        if let bpmOverride { bpm = bpmOverride }
        session.replaceChart(chart)
        scene.replaceChart(chart)
        chartName = chart.title
        chartStatusText = chartStatus
        adminNotes = chart.notes.sorted { $0.time < $1.time }
        if let selectedID = adminSelectedNoteID,
           !adminNotes.contains(where: { $0.id == selectedID }) {
            adminSelectedNoteID = nil
        }
        scene.selectedAdminNoteID = adminSelectedNoteID
        session.reset()
        isRunComplete = false
        scene.restartSong()
        syncState()
        syncTransportState()
    }

    private func handleTick(_ time: TimeInterval) {
        playbackTimeText = String(format: "%.2fs", time)

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
                adminStatusText = "Recorded \(event.lane.displayName) at \(String(format: "%.2f", event.timestamp))s"
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
        guard loopLength != .off, audio.state == .playing else { return }
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
        trackName = audio.loadedTrackName ?? "Preview clock"
        chartName = session.chart.title
        adminNotes = session.chart.notes.sorted { $0.time < $1.time }
        bpmAnalysisStatusText = audio.analysisDebug.status
        bpmAnalysisDetailText = audio.analysisDebug.detail
    }

    private func syncTransportState() {
        let currentTime = adminScrubPreviewTime ?? audio.currentTime
        transportStateText = audio.state.rawValue
        playbackTimeText = String(format: "%.2fs", currentTime)
        playbackDurationText = String(format: "%.2fs", audio.duration)
        let position = MusicalTransport.position(at: currentTime, bpm: bpm, songOffset: songOffset)
        barBeatText = position.barBeatText
        musicalSubdivisionText = String(position.subdivision)
        refreshAdminVisibleNotes(at: currentTime)
    }

    private func quantizedStepCursorTime() -> Double {
        let interval = stepInterval
        guard interval > 0 else { return max(0, stepCursorTime) }
        return (stepCursorTime / interval).rounded() * interval
    }

    private func nearestAdminNote(to time: Double) -> NoteEvent? {
        let hitLineHalfHeight = noteLaneHitLineHeight / 2
        let overlappingNotes = adminNotes.compactMap { note -> (note: NoteEvent, overlap: Double)? in
            let noteRadius = note.lane == .kick ? 28.0 : 24.0
            let distanceToHitLine = abs(note.time - time) * adminAuthoringNoteSpeed
            let overlap = (noteRadius + hitLineHalfHeight) - distanceToHitLine
            guard overlap >= 0 else { return nil }
            return (note, overlap)
        }

        return overlappingNotes.max { lhs, rhs in
            if abs(lhs.overlap - rhs.overlap) > 0.001 {
                return lhs.overlap < rhs.overlap
            }
            return abs(lhs.note.time - time) > abs(rhs.note.time - time)
        }?.note
    }

    private var stepInterval: Double {
        let beatDuration = 60.0 / max(1, bpm)
        return beatDuration / Double(stepResolution.subdivisionsPerBeat)
    }

    private var barDuration: Double { (60.0 / max(1, bpm)) * 4.0 }

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
            audio.seek(to: stepCursorTime)
            syncTransportState()
        }
    }

    private func updateStepCursorDisplay() {
        let position = MusicalTransport.position(at: stepCursorTime, bpm: bpm, songOffset: songOffset, subdivisionsPerBeat: max(stepResolution.subdivisionsPerBeat, 1))
        let subText = stepResolution == .quarter ? "" : ".\(position.subdivision)"
        stepCursorDisplayText = "\(position.bar):\(position.beat)\(subText) · \(String(format: "%.2f", quantizedStepCursorTime()))s"
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
        guard let targetTime = adminScrubPreviewTargetTime else {
            return adminScrubPreviewTime ?? fallbackAudioTime
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

    var currentPlaybackTime: Double { audio.currentTime }
    var playbackDuration: Double { audio.duration }
    var playbackProgress: Double {
        let duration = max(audio.duration, 0)
        guard duration > 0 else { return 0 }
        return min(max(audio.currentTime / duration, 0), 1)
    }

    func isPlaybackRateSelected(_ rate: Float) -> Bool {
        abs(audio.playbackRate - rate) < 0.001
    }

    private func updateLoopStatusText() {
        if loopLength == .off {
            loopStatusText = "Loop Off"
        } else {
            let start = loopStartTime
            let end = start + (barDuration * Double(loopLength.barCount))
            loopStatusText = "\(loopLength.rawValue) · \(String(format: "%.2f", start))s–\(String(format: "%.2f", end))s"
        }
    }

    private func refocusGameplay() { gameplayFocusVersion += 1 }

    private var chartContentTypes: [UTType] {
        var types: [UTType] = []
        if let midi = UTType(filenameExtension: "midi") { types.append(midi) }
        if let mid = UTType(filenameExtension: "mid") { types.append(mid) }
        return types.isEmpty ? [.data] : types
    }

    private func completionMessage() -> String {
        "Run complete · \(hitCount) hits · \(missCount) misses · \(accuracyText) accuracy"
    }
}
