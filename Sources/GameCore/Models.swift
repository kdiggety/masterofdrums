import Foundation

enum Lane: Int, CaseIterable, Identifiable {
    case red
    case yellow
    case blue
    case green
    case kick

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .green: return "Green"
        case .kick: return "Kick"
        }
    }

    var keyLabel: String {
        switch self {
        case .red: return "D"
        case .yellow: return "F"
        case .blue: return "J"
        case .green: return "K"
        case .kick: return "␣"
        }
    }
}

enum Judgment: String {
    case perfect = "Perfect"
    case good = "Good"
    case miss = "Miss"
}

struct NoteEvent: Identifiable {
    let id: UUID
    let lane: Lane
    let time: TimeInterval

    init(id: UUID = UUID(), lane: Lane, time: TimeInterval) {
        self.id = id
        self.lane = lane
        self.time = time
    }
}

struct SongSection: Identifiable, Equatable {
    let id: UUID
    let name: String
    let startTime: TimeInterval

    init(id: UUID = UUID(), name: String, startTime: TimeInterval) {
        self.id = id
        self.name = name
        self.startTime = startTime
    }
}

struct Chart {
    let notes: [NoteEvent]
    let title: String
    let sections: [SongSection]

    init(notes: [NoteEvent], title: String, sections: [SongSection] = []) {
        self.notes = notes
        self.title = title
        self.sections = sections.sorted { $0.startTime < $1.startTime }
    }

    var endTime: TimeInterval {
        max(notes.map(\.time).max() ?? 0, sections.map(\.startTime).max() ?? 0)
    }

    static let prototype: Chart = {
        let pattern: [(Lane, TimeInterval)] = [
            (.red, 1.0), (.yellow, 1.5), (.blue, 2.0), (.green, 2.5),
            (.red, 3.0), (.kick, 3.0), (.yellow, 3.5), (.blue, 4.0), (.green, 4.5),
            (.kick, 5.0), (.red, 5.5), (.yellow, 6.0), (.blue, 6.5), (.green, 7.0)
        ]
        return Chart(notes: pattern.map { NoteEvent(lane: $0.0, time: $0.1) }, title: "Prototype")
    }()
}

struct ScoreState {
    var score: Int = 0
    var combo: Int = 0
    var hitCount: Int = 0
    var missCount: Int = 0
    var lastJudgment: Judgment? = nil

    var accuracy: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }
}
