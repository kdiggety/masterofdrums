import Foundation
import Combine

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
    @Published private(set) var transportStateText: String = TransportState.stopped.rawValue
    @Published private(set) var playbackTimeText: String = "0.00s"

    let scene: GameplayScene
    let audio: AudioPlaybackController

    private let session: GameSession
    private let inputRouter: InputRouter
    private let chart: Chart
    private let completionGracePeriod: TimeInterval = 0.5

    init() {
        self.chart = .prototype
        self.session = GameSession(chart: .prototype)
        let keyboard = KeyboardInputDevice()
        self.inputRouter = InputRouter(activeDevice: keyboard)
        self.audio = AudioPlaybackController()
        self.scene = GameplayScene(chart: .prototype, keyboardInputDevice: keyboard)
        self.activeInputSourceName = keyboard.source.rawValue

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
    }

    func chooseAudioFile() {
        audio.chooseAudioFile()
        if let loadedTrackName = audio.loadedTrackName {
            trackName = loadedTrackName
            statusMessage = "Loaded \(loadedTrackName)"
        }
        syncTransportState()
    }

    func playTransport() {
        audio.play()
        syncTransportState()
    }

    func pauseTransport() {
        audio.pause()
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

    private func handleTick(_ time: TimeInterval) {
        playbackTimeText = String(format: "%.2fs", time)
        guard !isRunComplete else {
            syncTransportState()
            return
        }

        session.advanceMisses(at: time)

        if session.isComplete && time >= chart.endTime + completionGracePeriod {
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
    }

    private func syncTransportState() {
        transportStateText = audio.state.rawValue
        playbackTimeText = String(format: "%.2fs", audio.currentTime)
    }

    private func completionMessage() -> String {
        "Run complete · \(hitCount) hits · \(missCount) misses · \(accuracyText) accuracy"
    }
}
