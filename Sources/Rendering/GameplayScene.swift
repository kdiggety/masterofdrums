import SpriteKit
import AppKit

final class GameplayScene: SKScene {
    var onInput: ((InputEvent) -> Void)?
    var onTick: ((TimeInterval) -> Void)?

    private let chart: Chart
    private let keyboardInputDevice: KeyboardInputDevice
    private let highway = SKNode()
    private let judgmentLabel = SKLabelNode(fontNamed: "SF Pro Display")
    private let statusLabel = SKLabelNode(fontNamed: "SF Pro Display")
    private let laneWidth: CGFloat = 120
    private let laneInset: CGFloat = 2
    private let noteSpeed: CGFloat = 260
    private let hitLineY: CGFloat = 110
    private let laneOrder: [Lane] = [.red, .yellow, .blue, .green, .kick]
    private var songStartDate: Date?
    private var noteNodes: [UUID: SKShapeNode] = [:]
    private var laneHighlights: [Lane: SKShapeNode] = [:]

    var currentSongTime: TimeInterval {
        guard let songStartDate else { return 0 }
        return Date().timeIntervalSince(songStartDate)
    }

    init(chart: Chart, keyboardInputDevice: KeyboardInputDevice) {
        self.chart = chart
        self.keyboardInputDevice = keyboardInputDevice
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
        restartSong()
        view.window?.makeFirstResponder(view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        setupScene()
        updateVisibleNotes(Array(noteNodes.keys.compactMap { id in chart.notes.first(where: { $0.id == id }) }))
    }

    override func update(_ currentTime: TimeInterval) {
        guard songStartDate != nil else { return }
        let songTime = currentSongTime
        onTick?(songTime)
        updateNodePositions(songTime: songTime)
    }

    override func keyDown(with event: NSEvent) {
        guard let inputEvent = keyboardInputDevice.makeInputEvent(from: event, songTime: currentSongTime) else {
            super.keyDown(with: event)
            return
        }
        onInput?(inputEvent)
    }

    func restartSong() {
        songStartDate = Date()
        updateVisibleNotes([])
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

    func flashStatus(_ text: String) {
        statusLabel.text = text
        statusLabel.alpha = 1.0
        statusLabel.removeAllActions()
        statusLabel.run(.sequence([
            .fadeIn(withDuration: 0.02),
            .wait(forDuration: 0.25),
            .fadeOut(withDuration: 0.25)
        ]))
    }

    func flashLane(_ lane: Lane) {
        guard let highlight = laneHighlights[lane] else { return }
        highlight.removeAllActions()
        highlight.alpha = 0.8
        highlight.run(.sequence([
            .fadeAlpha(to: 0.8, duration: 0.01),
            .fadeAlpha(to: 0.0, duration: 0.16)
        ]))
    }

    private func setupScene() {
        removeAllChildren()
        highway.removeAllChildren()
        laneHighlights.removeAll()

        addChild(highway)
        addChild(judgmentLabel)
        addChild(statusLabel)

        let totalWidth = laneWidth * CGFloat(laneOrder.count)
        let startX = (size.width - totalWidth) / 2

        for (index, lane) in laneOrder.enumerated() {
            let laneFrame = frameForLane(at: index, startX: startX)

            let laneNode = SKShapeNode(rect: laneFrame, cornerRadius: 4)
            laneNode.strokeColor = .darkGray
            laneNode.fillColor = color(for: lane).withAlphaComponent(0.17)
            highway.addChild(laneNode)

            let highlightNode = SKShapeNode(rect: laneFrame, cornerRadius: 4)
            highlightNode.strokeColor = color(for: lane).withAlphaComponent(0.8)
            highlightNode.lineWidth = 2
            highlightNode.fillColor = color(for: lane).withAlphaComponent(0.35)
            highlightNode.alpha = 0.0
            highway.addChild(highlightNode)
            laneHighlights[lane] = highlightNode

            let laneLabel = SKLabelNode(fontNamed: "SF Pro Rounded")
            laneLabel.text = lane.keyLabel
            laneLabel.fontColor = .white.withAlphaComponent(0.9)
            laneLabel.fontSize = lane == .kick ? 22 : 24
            laneLabel.position = CGPoint(x: laneFrame.midX, y: hitLineY - 36)
            laneLabel.verticalAlignmentMode = .center
            laneLabel.horizontalAlignmentMode = .center
            highway.addChild(laneLabel)
        }

        let hitLineFrame = CGRect(
            x: startX + laneInset,
            y: hitLineY,
            width: totalWidth - (laneInset * 2),
            height: 6
        )
        let hitLine = SKShapeNode(rect: hitLineFrame, cornerRadius: 3)
        hitLine.fillColor = .white
        hitLine.strokeColor = .clear
        highway.addChild(hitLine)

        judgmentLabel.position = CGPoint(x: size.width / 2, y: size.height - 60)
        judgmentLabel.fontSize = 28
        judgmentLabel.alpha = 0

        statusLabel.position = CGPoint(x: size.width / 2, y: size.height - 96)
        statusLabel.fontSize = 20
        statusLabel.fontColor = .white.withAlphaComponent(0.85)
        statusLabel.alpha = 0
    }

    private func updateNodePositions(songTime: TimeInterval) {
        let totalWidth = laneWidth * CGFloat(laneOrder.count)
        let startX = (size.width - totalWidth) / 2

        for note in chart.notes {
            guard let node = noteNodes[note.id], let laneIndex = laneOrder.firstIndex(of: note.lane) else { continue }
            let laneFrame = frameForLane(at: laneIndex, startX: startX)
            let timeUntilHit = note.time - songTime
            node.position = CGPoint(x: laneFrame.midX, y: hitLineY + CGFloat(timeUntilHit) * noteSpeed)
        }
    }

    private func frameForLane(at index: Int, startX: CGFloat) -> CGRect {
        let laneX = startX + CGFloat(index) * laneWidth + laneInset
        return CGRect(x: laneX, y: 0, width: laneWidth - (laneInset * 2), height: size.height)
    }

    private func makeNoteNode(for note: NoteEvent) -> SKShapeNode {
        let radius: CGFloat = note.lane == .kick ? 28 : 24
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = color(for: note.lane)
        node.strokeColor = .white
        node.lineWidth = 2

        let label = SKLabelNode(fontNamed: "SF Pro Rounded")
        label.text = note.lane.keyLabel
        label.fontColor = .white
        label.fontSize = note.lane == .kick ? 22 : 24
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: note.lane == .kick ? 1 : 0)
        label.zPosition = 1
        node.addChild(label)

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
}
