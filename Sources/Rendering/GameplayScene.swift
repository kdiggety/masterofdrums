import SpriteKit
import AppKit

final class GameplayScene: SKScene {
    var onLaneHit: ((Lane, TimeInterval) -> Void)?
    var onTick: ((TimeInterval) -> Void)?

    private let chart: Chart
    private let highway = SKNode()
    private let judgmentLabel = SKLabelNode(fontNamed: "SF Pro Display")
    private let laneWidth: CGFloat = 120
    private let noteSpeed: CGFloat = 260
    private let hitLineY: CGFloat = 110
    private let laneOrder: [Lane] = [.red, .yellow, .blue, .green, .kick]
    private var songStartDate: Date?
    private var noteNodes: [UUID: SKShapeNode] = [:]

    var currentSongTime: TimeInterval {
        guard let songStartDate else { return 0 }
        return Date().timeIntervalSince(songStartDate)
    }

    init(chart: Chart) {
        self.chart = chart
        super.init(size: CGSize(width: 900, height: 480))
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        setupScene()
        songStartDate = Date()
        view.window?.makeFirstResponder(view)
    }

    override func update(_ currentTime: TimeInterval) {
        guard songStartDate != nil else { return }
        let songTime = currentSongTime
        onTick?(songTime)
        updateNodePositions(songTime: songTime)
    }

    override func keyDown(with event: NSEvent) {
        guard let lane = lane(for: event) else {
            super.keyDown(with: event)
            return
        }
        onLaneHit?(lane, currentSongTime)
    }

    func updateVisibleNotes(_ notes: [NoteEvent]) {
        let visibleIDs = Set(notes.map(\.id))

        for note in notes where noteNodes[note.id] == nil {
            let node = makeNoteNode(for: note)
            noteNodes[note.id] = node
            highway.addChild(node)
        }

        let staleIDs = noteNodes.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            noteNodes[id]?.removeFromParent()
            noteNodes.removeValue(forKey: id)
        }
    }

    func flashJudgment(_ judgment: Judgment) {
        judgmentLabel.text = judgment.rawValue
        switch judgment {
        case .perfect:
            judgmentLabel.fontColor = .systemGreen
        case .good:
            judgmentLabel.fontColor = .systemYellow
        case .miss:
            judgmentLabel.fontColor = .systemRed
        }

        judgmentLabel.alpha = 1.0
        judgmentLabel.removeAllActions()
        judgmentLabel.run(.sequence([
            .fadeIn(withDuration: 0.02),
            .wait(forDuration: 0.18),
            .fadeOut(withDuration: 0.25)
        ]))
    }

    private func setupScene() {
        removeAllChildren()
        noteNodes.removeAll()

        addChild(highway)
        addChild(judgmentLabel)

        let totalWidth = laneWidth * CGFloat(laneOrder.count)
        let startX = (size.width - totalWidth) / 2

        for (index, lane) in laneOrder.enumerated() {
            let laneX = startX + CGFloat(index) * laneWidth
            let laneRect = CGRect(x: laneX, y: 0, width: laneWidth - 4, height: size.height)
            let laneNode = SKShapeNode(rect: laneRect, cornerRadius: 4)
            laneNode.strokeColor = .darkGray
            laneNode.fillColor = color(for: lane).withAlphaComponent(0.17)
            highway.addChild(laneNode)
        }

        let hitLine = SKShapeNode(rect: CGRect(x: startX, y: hitLineY, width: totalWidth - 4, height: 6), cornerRadius: 3)
        hitLine.fillColor = .white
        hitLine.strokeColor = .clear
        highway.addChild(hitLine)

        judgmentLabel.position = CGPoint(x: size.width / 2, y: size.height - 60)
        judgmentLabel.fontSize = 28
        judgmentLabel.alpha = 0
    }

    private func updateNodePositions(songTime: TimeInterval) {
        let totalWidth = laneWidth * CGFloat(laneOrder.count)
        let startX = (size.width - totalWidth) / 2

        for note in chart.notes {
            guard let node = noteNodes[note.id], let laneIndex = laneOrder.firstIndex(of: note.lane) else { continue }
            let laneX = startX + CGFloat(laneIndex) * laneWidth + (laneWidth / 2) - 2
            let timeUntilHit = note.time - songTime
            node.position = CGPoint(x: laneX, y: hitLineY + CGFloat(timeUntilHit) * noteSpeed)
        }
    }

    private func makeNoteNode(for note: NoteEvent) -> SKShapeNode {
        let radius: CGFloat = note.lane == .kick ? 28 : 24
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = color(for: note.lane)
        node.strokeColor = .white
        node.lineWidth = 2
        return node
    }

    private func color(for lane: Lane) -> NSColor {
        switch lane {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .kick: return .systemGray
        }
    }

    private func lane(for event: NSEvent) -> Lane? {
        switch event.keyCode {
        case 2: return .red      // D
        case 3: return .yellow   // F
        case 38: return .blue    // J
        case 40: return .green   // K
        case 49: return .kick    // Space
        default: return nil
        }
    }
}
