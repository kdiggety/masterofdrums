import Foundation
import Combine

final class PrototypeGameController: ObservableObject {
    @Published private(set) var score: Int = 0
    @Published private(set) var combo: Int = 0
    @Published private(set) var missCount: Int = 0
    @Published private(set) var hitCount: Int = 0
    @Published private(set) var lastJudgmentText: String = "—"
    @Published private(set) var activeInputSourceName: String

    let scene: GameplayScene
    private let session: GameSession
    private let inputRouter: InputRouter

    init() {
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
            self?.session.advanceMisses(at: time)
            self?.syncState()
        }
    }

    private func handleInput(_ event: InputEvent) {
        let judgment = session.registerHit(lane: event.lane, at: event.timestamp)
        scene.flashJudgment(judgment)
        scene.flashLane(event.lane)
        activeInputSourceName = event.source.rawValue
        syncState()
    }

    private func syncState() {
        score = session.state.score
        combo = session.state.combo
        missCount = session.state.missCount
        hitCount = session.state.hitCount
        lastJudgmentText = session.state.lastJudgment?.rawValue ?? "—"
        scene.updateVisibleNotes(session.notes(visibleAt: scene.currentSongTime, leadTime: 3.0))
    }
}
