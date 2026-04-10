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

    var laneLabel: String {
        switch self {
        case .red: return "Snare"
        case .yellow: return "Hi-Hat"
        case .blue: return "Tom High"
        case .green: return "Tom Mid"
        case .kick: return "Kick"
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
    let label: String?

    init(id: UUID = UUID(), lane: Lane, time: TimeInterval, label: String? = nil) {
        self.id = id
        self.lane = lane
        self.time = time
        self.label = label
    }

    var displayLabel: String {
        label ?? lane.displayName
    }

    var displayLaneID: String {
        displayLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

struct ChartLane: Identifiable, Equatable {
    let id: String
    let label: String
    let sourceLane: Lane
    let keyLabel: String?
}

struct SongSection: Identifiable, Equatable {
    let id: UUID
    let name: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let colorName: String

    init(id: UUID = UUID(), name: String, startTime: TimeInterval, endTime: TimeInterval, colorName: String = "blue") {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = max(endTime, startTime)
        self.colorName = colorName
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
        max(notes.map(\.time).max() ?? 0, sections.map(\.endTime).max() ?? 0)
    }

    var displayLanes: [ChartLane] {
        var lanes: [ChartLane] = []
        var seen = Set<String>()
        for note in notes {
            let id = note.displayLaneID.isEmpty ? note.lane.displayName.lowercased() : note.displayLaneID
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            let isCanonicalLaneLabel = note.label == nil || note.displayLabel.caseInsensitiveCompare(note.lane.laneLabel) == .orderedSame || note.displayLabel.caseInsensitiveCompare(note.lane.displayName) == .orderedSame
            lanes.append(
                ChartLane(
                    id: id,
                    label: note.displayLabel,
                    sourceLane: note.lane,
                    keyLabel: isCanonicalLaneLabel ? note.lane.keyLabel : nil
                )
            )
        }

        if lanes.isEmpty {
            lanes = Lane.allCases.map {
                ChartLane(id: $0.displayName.lowercased(), label: $0.laneLabel, sourceLane: $0, keyLabel: $0.keyLabel)
            }
        }

        return lanes
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
