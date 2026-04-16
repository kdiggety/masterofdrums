import SpriteKit
import AppKit

final class GameplayScene: SKScene {
    struct BeatGuideConfiguration {
        let bpm: Double
        let songOffset: TimeInterval
        let beatsPerBar: Int
        let subdivisionsPerBeat: Int
    }

    var onInput: ((InputEvent) -> Void)?
    var onTick: ((TimeInterval) -> Void)?
    var timeProvider: (() -> TimeInterval)?
    var beatGuideConfiguration: (() -> BeatGuideConfiguration?)?

    private var chart: Chart
    private let keyboardInputDevice: KeyboardInputDevice
    private let highway = SKNode()
    private let judgmentLabel = SKLabelNode(fontNamed: "SF Pro Display")
    private let statusLabel = SKLabelNode(fontNamed: "SF Pro Display")
    private let laneWidth: CGFloat = 120
    private let laneInset: CGFloat = 2
    private let defaultNoteSpeed: CGFloat = 260
    private let adminAuthoringNoteSpeed: CGFloat = 110
    private let hitLineY: CGFloat = 110
    private var laneOrder: [ChartLane] = []
    private var laneIDBySourceLane: [Lane: String] = [:]
    private var laneIndexByID: [String: Int] = [:]
    private let noteNodeNamePrefix = "note-"
    private let beatGuideNodeNamePrefix = "beat-guide-"
    private let beatGuideLabelNodeNamePrefix = "beat-guide-label-"
    private var noteNodes: [UUID: SKShapeNode] = [:]
    private var visibleNotes: [NoteEvent] = []
    private var laneHighlights: [String: SKShapeNode] = [:]
    private var draggedAdminNotePreviewTimeByID: [UUID: TimeInterval] = [:]
    private var draggedAdminNotePreviewYByID: [UUID: CGFloat] = [:]
    private var draggedAdminNotePreviewTargetYByID: [UUID: CGFloat] = [:]
    private var draggedAdminNotePreviewLaneByID: [UUID: Lane] = [:]
    var isAdminAuthoringMode: Bool = false
    var selectedAdminNoteID: UUID? {
        didSet { updateSelectionAppearance() }
    }

    var currentSongTime: TimeInterval {
        timeProvider?() ?? 0
    }

    var hitLineYPosition: CGFloat { hitLineY }

    init(chart: Chart, keyboardInputDevice: KeyboardInputDevice) {
        self.chart = chart
        self.keyboardInputDevice = keyboardInputDevice
        self.laneOrder = chart.displayLanes
        self.laneIDBySourceLane = Dictionary(uniqueKeysWithValues: self.laneOrder.map { ($0.sourceLane, $0.id) })
        self.laneIndexByID = Dictionary(uniqueKeysWithValues: self.laneOrder.enumerated().map { ($0.element.id, $0.offset) })
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
        updateVisibleNotes(visibleNotes)
    }

    override func update(_ currentTime: TimeInterval) {
        let songTime = currentSongTime
        onTick?(songTime)
        advanceDraggedNotePreviewPositions()
        updateBeatGuideLines(songTime: songTime)
        updateNodePositions(songTime: songTime)
    }

    override func keyDown(with event: NSEvent) {
        guard let inputEvent = keyboardInputDevice.makeInputEvent(from: event, songTime: currentSongTime) else {
            super.keyDown(with: event)
            return
        }
        onInput?(inputEvent)
    }

    func replaceChart(_ chart: Chart) {
        self.chart = chart
        laneOrder = chart.displayLanes
        laneIDBySourceLane = Dictionary(uniqueKeysWithValues: laneOrder.map { ($0.sourceLane, $0.id) })
        laneIndexByID = Dictionary(uniqueKeysWithValues: laneOrder.enumerated().map { ($0.element.id, $0.offset) })
        noteNodes.removeAll()
        visibleNotes = []
        draggedAdminNotePreviewTimeByID.removeAll()
        draggedAdminNotePreviewYByID.removeAll()
        draggedAdminNotePreviewTargetYByID.removeAll()
        draggedAdminNotePreviewLaneByID.removeAll()
        restartSong()
        updateVisibleNotes([])
    }

    func restartSong() {
        updateVisibleNotes([])
    }

    func updateVisibleNotes(_ notes: [NoteEvent]) {
        visibleNotes = notes
        let visibleIDs = Set(notes.map(\.id))

        for note in notes where noteNodes[note.id] == nil {
            let node = makeNoteNode(for: note)
            noteNodes[note.id] = node
            highway.addChild(node)
        }

        let staleIDs = noteNodes.keys.filter { !visibleIDs.contains($0) }
        for id in staleIDs {
            draggedAdminNotePreviewTimeByID.removeValue(forKey: id)
            draggedAdminNotePreviewYByID.removeValue(forKey: id)
            draggedAdminNotePreviewTargetYByID.removeValue(forKey: id)
            draggedAdminNotePreviewLaneByID.removeValue(forKey: id)
            noteNodes[id]?.removeFromParent()
            noteNodes.removeValue(forKey: id)
        }

        removeOrphanedNoteNodes(excluding: visibleIDs)
        updateSelectionAppearance()
        updateNodePositions(songTime: currentSongTime)
    }

    func debugVisibleNoteCount() -> Int {
        visibleNotes.count
    }

    func debugRenderedNoteNodeCount() -> Int {
        noteNodes.count
    }

    func debugVisibleLaneCounts() -> [Lane: Int] {
        Dictionary(grouping: visibleNotes, by: \.lane).mapValues(\.count)
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
        guard let highlight = laneHighlights[laneIDBySourceLane[lane] ?? lane.displayName.lowercased()] else { return }
        highlight.removeAllActions()
        highlight.alpha = 0.8
        highlight.run(.sequence([
            .fadeAlpha(to: 0.8, duration: 0.01),
            .fadeAlpha(to: 0.0, duration: 0.16)
        ]))
    }

    func adminNoteID(at scenePoint: CGPoint) -> UUID? {
        guard isAdminAuthoringMode else { return nil }
        let nodesAtPoint = nodes(at: scenePoint)
        for node in nodesAtPoint {
            if let noteID = noteID(from: node) {
                return noteID
            }
        }
        return nil
    }

    func adminLane(at scenePoint: CGPoint) -> Lane? {
        let totalWidth = laneWidth * CGFloat(laneOrder.count)
        let startX = (size.width - totalWidth) / 2
        for (index, lane) in laneOrder.enumerated() {
            if frameForLane(at: index, startX: startX).contains(scenePoint) {
                return lane.sourceLane
            }
        }
        return nil
    }

    func previewAdminNoteMove(id: UUID, time: TimeInterval, yPosition: CGFloat, lane: Lane? = nil, smoothingFactor: Double = 0.45) {
        _ = smoothingFactor
        draggedAdminNotePreviewTimeByID[id] = time
        if draggedAdminNotePreviewYByID[id] == nil {
            draggedAdminNotePreviewYByID[id] = yPosition
        }
        draggedAdminNotePreviewTargetYByID[id] = yPosition
        if let lane {
            draggedAdminNotePreviewLaneByID[id] = lane
        }
        updateNodePositions(songTime: currentSongTime)
    }

    func clearAdminNoteMovePreview(for id: UUID? = nil) {
        if let id {
            draggedAdminNotePreviewTimeByID.removeValue(forKey: id)
            draggedAdminNotePreviewYByID.removeValue(forKey: id)
            draggedAdminNotePreviewTargetYByID.removeValue(forKey: id)
            draggedAdminNotePreviewLaneByID.removeValue(forKey: id)
        } else {
            draggedAdminNotePreviewTimeByID.removeAll()
            draggedAdminNotePreviewYByID.removeAll()
            draggedAdminNotePreviewTargetYByID.removeAll()
            draggedAdminNotePreviewLaneByID.removeAll()
        }
        updateNodePositions(songTime: currentSongTime)
    }

    private func advanceDraggedNotePreviewPositions() {
        for (id, targetY) in draggedAdminNotePreviewTargetYByID {
            let currentY = draggedAdminNotePreviewYByID[id] ?? targetY
            let delta = targetY - currentY
            let nextY: CGFloat
            if abs(delta) < 0.25 {
                nextY = targetY
            } else {
                let minimumStep = min(abs(delta), 2.0)
                nextY = currentY + (delta * 0.5) + (delta.sign == .minus ? -minimumStep : minimumStep)
            }
            draggedAdminNotePreviewYByID[id] = nextY
        }
    }

    private func updateBeatGuideLines(songTime: TimeInterval) {
        highway.children
            .filter {
                ($0.name?.hasPrefix(beatGuideNodeNamePrefix) == true) ||
                ($0.name?.hasPrefix(beatGuideLabelNodeNamePrefix) == true)
            }
            .forEach { $0.removeFromParent() }

        guard isAdminAuthoringMode,
              let configuration = beatGuideConfiguration?(),
              configuration.bpm > 0 else { return }

        let totalWidth = laneWidth * CGFloat(laneOrder.count)
        let startX = (size.width - totalWidth) / 2
        let guideStartX = startX + laneInset
        let guideWidth = totalWidth - (laneInset * 2)
        let beatDuration = 60.0 / configuration.bpm
        let subdivisionDuration = beatDuration / Double(max(configuration.subdivisionsPerBeat, 1))
        let adjustedSongTime = songTime - configuration.songOffset
        let currentSubdivisionIndex = Int(floor(adjustedSongTime / subdivisionDuration))
        let subdivisionsToDraw = max(configuration.subdivisionsPerBeat * 24, 32)

        for offset in -(configuration.subdivisionsPerBeat * 8)...subdivisionsToDraw {
            let subdivisionIndex = currentSubdivisionIndex + offset
            let subdivisionTime = configuration.songOffset + (Double(subdivisionIndex) * subdivisionDuration)
            let timeUntilSubdivision = subdivisionTime - songTime
            let y = hitLineY + CGFloat(timeUntilSubdivision) * activeNoteSpeed
            guard y >= 0, y <= size.height else { continue }

            let isBeatLine = subdivisionIndex % configuration.subdivisionsPerBeat == 0
            let beatIndex = subdivisionIndex / configuration.subdivisionsPerBeat
            let isMeasureLine = isBeatLine && beatIndex >= 0 && (beatIndex % configuration.beatsPerBar == 0)
            let lineHeight: CGFloat = isMeasureLine ? 3 : (isBeatLine ? 1.5 : 1)
            let lineRect = CGRect(x: guideStartX, y: y, width: guideWidth, height: lineHeight)
            let line = SKShapeNode(rect: lineRect)
            line.name = beatGuideNodeNamePrefix + "\(subdivisionIndex)"
            if isMeasureLine {
                line.fillColor = NSColor.white.withAlphaComponent(0.52)
            } else if isBeatLine {
                line.fillColor = NSColor.white.withAlphaComponent(0.22)
            } else {
                line.fillColor = NSColor.white.withAlphaComponent(0.08)
            }
            line.strokeColor = .clear
            line.zPosition = -0.5
            highway.addChild(line)

            if isMeasureLine {
                let barNumber = max(1, (beatIndex / max(configuration.beatsPerBar, 1)) + 1)
                let label = SKLabelNode(fontNamed: "SF Pro Rounded")
                label.name = beatGuideLabelNodeNamePrefix + "\(subdivisionIndex)"
                label.text = "Bar \(barNumber)"
                label.fontColor = .white.withAlphaComponent(0.68)
                label.fontSize = 11
                label.horizontalAlignmentMode = .left
                label.verticalAlignmentMode = .bottom
                label.position = CGPoint(x: guideStartX + 6, y: min(size.height - 14, y + 4))
                label.zPosition = -0.4
                highway.addChild(label)
            }
        }
    }

    private func setupScene() {
        removeAllChildren()
        highway.removeAllChildren()
        noteNodes.removeAll()
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
            laneNode.fillColor = color(for: lane.sourceLane).withAlphaComponent(0.17)
            highway.addChild(laneNode)

            let highlightNode = SKShapeNode(rect: laneFrame, cornerRadius: 4)
            highlightNode.strokeColor = color(for: lane.sourceLane).withAlphaComponent(0.8)
            highlightNode.lineWidth = 2
            highlightNode.fillColor = color(for: lane.sourceLane).withAlphaComponent(0.35)
            highlightNode.alpha = 0.0
            highway.addChild(highlightNode)
            laneHighlights[lane.id] = highlightNode

            if let key = lane.keyLabel {
                let keyLabel = SKLabelNode(fontNamed: "SF Pro Rounded")
                keyLabel.text = key
                keyLabel.fontColor = .white.withAlphaComponent(0.92)
                keyLabel.fontSize = lane.sourceLane == .kick ? 22 : 24
                keyLabel.position = CGPoint(x: laneFrame.midX, y: hitLineY - 30)
                keyLabel.verticalAlignmentMode = .center
                keyLabel.horizontalAlignmentMode = .center
                highway.addChild(keyLabel)
            }

            let drumLabel = SKLabelNode(fontNamed: "SF Pro Rounded")
            drumLabel.text = lane.label
            drumLabel.fontColor = .white.withAlphaComponent(0.76)
            drumLabel.fontSize = 12
            drumLabel.position = CGPoint(x: laneFrame.midX, y: hitLineY - 48)
            drumLabel.verticalAlignmentMode = .center
            drumLabel.horizontalAlignmentMode = .center
            highway.addChild(drumLabel)
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

        for note in visibleNotes {
            guard let node = noteNodes[note.id] else { continue }
            let effectiveLane = draggedAdminNotePreviewLaneByID[note.id] ?? note.lane
            let effectiveLaneID = draggedAdminNotePreviewLaneByID[note.id].map { lane in
                laneIDBySourceLane[lane] ?? lane.displayName.lowercased()
            } ?? note.displayLaneID
            guard let laneIndex = laneIndexByID[effectiveLaneID] ?? (note.label == nil ? laneOrder.firstIndex(where: { $0.sourceLane == effectiveLane }) : nil) else { continue }
            let laneFrame = frameForLane(at: laneIndex, startX: startX)
            let yPosition: CGFloat
            if let previewY = draggedAdminNotePreviewYByID[note.id] {
                yPosition = previewY
            } else {
                let effectiveTime = draggedAdminNotePreviewTimeByID[note.id] ?? note.time
                let timeUntilHit = effectiveTime - songTime
                yPosition = hitLineY + CGFloat(timeUntilHit) * activeNoteSpeed
            }
            node.position = CGPoint(x: laneFrame.midX, y: yPosition)
        }
    }

    private var activeNoteSpeed: CGFloat {
        isAdminAuthoringMode ? adminAuthoringNoteSpeed : defaultNoteSpeed
    }

    private func frameForLane(at index: Int, startX: CGFloat) -> CGRect {
        let laneX = startX + CGFloat(index) * laneWidth + laneInset
        return CGRect(x: laneX, y: 0, width: laneWidth - (laneInset * 2), height: size.height)
    }

    private func makeNoteNode(for note: NoteEvent) -> SKShapeNode {
        let noteSize = CGSize(width: note.lane == .kick ? 60 : 52, height: note.lane == .kick ? 14 : 12)
        let noteRect = CGRect(x: -noteSize.width / 2, y: -noteSize.height / 2, width: noteSize.width, height: noteSize.height)
        let node = SKShapeNode(rect: noteRect, cornerRadius: 3)
        node.name = noteNodeNamePrefix + note.id.uuidString
        node.fillColor = color(for: note.lane)
        node.strokeColor = .white.withAlphaComponent(0.9)
        node.lineWidth = 1.5

        if note.label == nil {
            let label = SKLabelNode(fontNamed: "SF Pro Rounded")
            label.text = note.lane.keyLabel
            label.fontColor = .white
            label.fontSize = note.lane == .kick ? 12 : 11
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: 0)
            label.zPosition = 1
            node.addChild(label)
        }

        return node
    }

    private func noteID(from node: SKNode) -> UUID? {
        var currentNode: SKNode? = node
        while let node = currentNode {
            if let name = node.name,
               name.hasPrefix(noteNodeNamePrefix) {
                return UUID(uuidString: String(name.dropFirst(noteNodeNamePrefix.count)))
            }
            currentNode = node.parent
        }
        return nil
    }

    private func removeOrphanedNoteNodes(excluding visibleIDs: Set<UUID>) {
        for child in highway.children {
            guard let noteID = noteID(from: child), !visibleIDs.contains(noteID) else { continue }
            child.removeFromParent()
        }
    }

    private func updateSelectionAppearance() {
        for (id, node) in noteNodes {
            if id == selectedAdminNoteID {
                node.lineWidth = 5
                node.strokeColor = .systemPink
                node.glowWidth = 8
            } else {
                node.lineWidth = 2
                node.strokeColor = .white
                node.glowWidth = 0
            }
        }
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
