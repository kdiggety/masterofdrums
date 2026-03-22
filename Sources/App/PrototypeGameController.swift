import Foundation
import Combine

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

    let scene: GameplayScene
    private let session: GameSession
    private let inputRouter: InputRouter
    private let chart: Chart
    private let completionGracePeriod: TimeInterval = 0.5

    init() {
        self.chart = .prototype
        self.session = GameSession(chart: .prototype)
        let keyboard = KeyboardInputDevice()
        self.inputRouter = InputRouter(activeDevice: keyboard)
        self.scene = GameplayScene(chart: .prototype, keyboardInputDevice: keyboard)
        self.activeInputSourceName = keyboard.source.rawValue

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

    func restartRun() {
        session.reset()
        isRunComplete = false
        statusMessage = "Restarted"
        scene.restartSong()
        scene.flashStatus("Restart")
        syncState()
    }

    private func handleTick(_ time: TimeInterval) {
        guard !isRunComplete else { return }
        session.advanceMisses(at: time)

        if session.isComplete && time >= chart.endTime + completionGracePeriod {
            isRunComplete = true
            statusMessage = completionMessage()
            scene.flashStatus("Finished")
        }

        syncState()
    }

    private func handleInput(_ event: InputEvent) {
        if isRunComplete {
            restartRun()
        }

        let judgment = session.registerHit(lane: event.lane, at: event.timestamp)
        scene.flashJudgment(judgment)
        scene.flashLane(event.lane)
        activeInputSourceName = event.source.rawValue
        statusMessage = judgment == .miss ? "Miss" : "Playing"
        syncState()
    }

    private func syncState() {
        score = session.state.score
        combo = session.state.combo
        missCount = session.state.missCount
        hitCount = session.state.hitCount
        lastJudgmentText = session.state.lastJudgment?.rawValue ?? "—"
        accuracyText = String(format: "%.0f%%", session.state.accuracy * 100)
        scene.updateVisibleNotes(session.notes(visibleAt: scene.currentSongTime, leadTime: 3.0))
    }

    private func completionMessage() -> String {
        "Run complete · \(hitCount) hits · \(missCount) misses · \(accuracyText) accuracy"
    }
}
