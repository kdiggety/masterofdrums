import Foundation

final class GameSession {
    private(set) var chart: Chart
    private(set) var state = ScoreState()
    private var nextIndex = 0

    private let perfectWindow: TimeInterval = 0.09
    private let goodWindow: TimeInterval = 0.18

    init(chart: Chart) {
        self.chart = chart
    }

    func replaceChart(_ chart: Chart) {
        self.chart = chart
        reset()
    }

    func reset() {
        state = ScoreState()
        nextIndex = 0
    }

    func notes(visibleAt time: TimeInterval, leadTime: TimeInterval) -> [NoteEvent] {
        chart.notes.filter { note in
            note.time >= max(0, time - 0.25) && note.time <= time + leadTime
        }
    }

    var isComplete: Bool {
        nextIndex >= chart.notes.count
    }

    @discardableResult
    func registerHit(lane: Lane, at time: TimeInterval) -> Judgment {
        advanceMisses(at: time)

        guard let candidateIndex = chart.notes.indices.first(where: { index in
            let note = chart.notes[index]
            guard index >= nextIndex else { return false }
            return note.lane == lane && abs(note.time - time) <= goodWindow
        }) else {
            state.combo = 0
            state.missCount += 1
            state.lastJudgment = .miss
            return .miss
        }

        let note = chart.notes[candidateIndex]
        nextIndex = candidateIndex + 1
        state.hitCount += 1

        let delta = abs(note.time - time)
        if delta <= perfectWindow {
            state.score += 100
            state.combo += 1
            state.lastJudgment = .perfect
            return .perfect
        } else {
            state.score += 60
            state.combo += 1
            state.lastJudgment = .good
            return .good
        }
    }

    func advanceMisses(at time: TimeInterval) {
        while nextIndex < chart.notes.count {
            let note = chart.notes[nextIndex]
            if note.time + goodWindow < time {
                state.combo = 0
                state.missCount += 1
                state.lastJudgment = .miss
                nextIndex += 1
            } else {
                break
            }
        }
    }
}
