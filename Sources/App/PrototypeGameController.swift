import Foundation
import Combine

final class PrototypeGameController: ObservableObject {
    @Published private(set) var score: Int = 0
    @Published private(set) var combo: Int = 0
    @Published private(set) var lastJudgmentText: String = "—"

    let scene: GameplayScene
    private let session: GameSession

    init() {
        self.session = GameSession(chart: .prototype)
        self.scene = GameplayScene(chart: .prototype)
        self.scene.onLaneHit = { [weak self] lane, time in
            self?.handleHit(lane: lane, time: time)
        }
        self.scene.onTick = { [weak self] time in
            self?.session.advanceMisses(at: time)
            self?.syncState()
        }
    }

    private func handleHit(lane: Lane, time: TimeInterval) {
        let judgment = session.registerHit(lane: lane, at: time)
        scene.flashJudgment(judgment)
        syncState()
    }

    private func syncState() {
        score = session.state.score
        combo = session.state.combo
        lastJudgmentText = session.state.lastJudgment?.rawValue ?? "—"
        scene.updateVisibleNotes(session.notes(visibleAt: scene.currentSongTime, leadTime: 3.0))
    }
}
