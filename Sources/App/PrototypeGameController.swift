import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class PrototypeGameController: ObservableObject {
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
    @Published var bpm: Double = 120
    @Published var songOffset: Double = 0

    let scene: GameplayScene
    let audio: AudioPlaybackController

    private let session: GameSession
    private let inputRouter: InputRouter
    private let midiLoader = MIDIChartLoader()
    private let completionGracePeriod: TimeInterval = 0.5

    init() {
        let initialChart = Chart.prototype
        self.session = GameSession(chart: initialChart)
        let keyboard = KeyboardInputDevice()
        self.inputRouter = InputRouter(activeDevice: keyboard)
        self.audio = AudioPlaybackController()
        self.scene = GameplayScene(chart: initialChart, keyboardInputDevice: keyboard)
        self.activeInputSourceName = keyboard.source.rawValue
        self.chartName = initialChart.title

        self.scene.timeProvider = { [weak audio] in
            audio?.currentTime ?? 0
        }

        self.inputRouter.onInput = { [weak self] event in
            self?.handleInput(event)
        }

        self.scene.onInput = { [weak self] event in
            self?.inputRouter.route(event)
        }
        self.scene.onTick = { [weak self] time in
            self?.handleTick(time)
        }

        syncState()
        syncTransportState()
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
        syncTransportState()
    }

    func chooseChartFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose chart file"
        panel.allowedContentTypes = chartContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        loadChart(from: url)
    }

    func playTransport() {
        audio.play()
        syncTransportState()
    }

    func pauseTransport() {
        audio.pause()
        syncTransportState()
    }

    func nudgeBPM(by delta: Double) {
        bpm = max(40, min(240, bpm + delta))
        bpmSourceText = "Manual"
        syncTransportState()
    }

    func nudgeOffset(by delta: Double) {
        songOffset = max(-2, min(2, songOffset + delta))
        syncTransportState()
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
    }

    private func loadChart(from url: URL) {
        do {
            let chart = try midiLoader.loadChart(from: url)
            session.replaceChart(chart)
            scene.replaceChart(chart)
            chartName = chart.title
            chartStatusText = "Loaded \(chart.notes.count) notes from \(url.lastPathComponent)"
            statusMessage = "Loaded chart \(chart.title)"
            restartRun()
        } catch {
            chartStatusText = "Chart load failed"
            statusMessage = error.localizedDescription
        }
    }

    private func handleTick(_ time: TimeInterval) {
        playbackTimeText = String(format: "%.2fs", time)
        guard !isRunComplete else {
            syncTransportState()
            return
        }

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
        if audio.state == .stopped {
            audio.play()
        }

        if isRunComplete {
            restartRun()
            audio.play()
        }

        let judgment = session.registerHit(lane: event.lane, at: event.timestamp)
        scene.flashJudgment(judgment)
        scene.flashLane(event.lane)
        activeInputSourceName = event.source.rawValue
        statusMessage = judgment == .miss ? "Miss" : "Playing"
        syncState()
        syncTransportState()
    }

    private func syncState() {
        score = session.state.score
        combo = session.state.combo
        missCount = session.state.missCount
        hitCount = session.state.hitCount
        lastJudgmentText = session.state.lastJudgment?.rawValue ?? "—"
        accuracyText = String(format: "%.0f%%", session.state.accuracy * 100)
        scene.updateVisibleNotes(session.notes(visibleAt: scene.currentSongTime, leadTime: 3.0))
        trackName = audio.loadedTrackName ?? "Preview clock"
        chartName = session.chart.title
        bpmAnalysisStatusText = audio.analysisDebug.status
        bpmAnalysisDetailText = audio.analysisDebug.detail
    }

    private func syncTransportState() {
        let currentTime = audio.currentTime
        transportStateText = audio.state.rawValue
        playbackTimeText = String(format: "%.2fs", currentTime)
        let position = MusicalTransport.position(at: currentTime, bpm: bpm, songOffset: songOffset)
        barBeatText = position.barBeatText
        musicalSubdivisionText = String(position.subdivision)
    }

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
