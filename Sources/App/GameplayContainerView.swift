import SwiftUI
import SpriteKit
import AppKit

final class GameplaySKView: SKView {
    var onAdminLeftMouseDown: ((CGPoint, CGSize, Int) -> Void)?
    var onAdminLeftMouseDragged: ((CGPoint, CGSize) -> Void)?
    var onAdminLeftMouseUp: ((CGPoint, CGSize) -> Void)?
    var onAdminRightMouseDown: ((CGPoint) -> Void)?
    var onAdminScenePointRightMouseDown: ((CGPoint) -> Void)?
    var onAdminScenePointDown: ((CGPoint, CGSize, Int) -> Void)?
    var onAdminScenePointDragged: ((CGPoint, CGSize) -> Void)?
    var onAdminScenePointUp: ((CGPoint, CGSize) -> Void)?
    var isAdminInteractive = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard isAdminInteractive, let scene else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.control) {
            onAdminRightMouseDown?(point)
            return
        }
        let scenePoint = convert(point, to: scene)
        onAdminScenePointDown?(scenePoint, bounds.size, event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isAdminInteractive, let scene else {
            super.mouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let scenePoint = convert(point, to: scene)
        onAdminScenePointDragged?(scenePoint, bounds.size)
    }

    override func mouseUp(with event: NSEvent) {
        guard isAdminInteractive, let scene else {
            super.mouseUp(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let scenePoint = convert(point, to: scene)
        onAdminScenePointUp?(scenePoint, bounds.size)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isAdminInteractive, let scene else {
            super.rightMouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let scenePoint = convert(point, to: scene)
        onAdminScenePointRightMouseDown?(scenePoint)
    }

    override func keyDown(with event: NSEvent) {
        if let scene {
            scene.keyDown(with: event)
        } else {
            super.keyDown(with: event)
        }
    }
}

struct GameplayContainerView: NSViewRepresentable {
    let scene: GameplayScene
    var focusVersion: Int = 0
    var game: PrototypeGameController? = nil
    var isAdminInteractive: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(scene: scene)
    }

    func makeNSView(context: Context) -> SKView {
        let view = GameplaySKView()
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        configure(view, coordinator: context.coordinator)

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        if nsView.scene !== scene {
            nsView.presentScene(scene)
        }

        if let view = nsView as? GameplaySKView {
            configure(view, coordinator: context.coordinator)
        }

        _ = focusVersion
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func configure(_ view: GameplaySKView, coordinator: Coordinator) {
        coordinator.scene = scene
        coordinator.game = game
        coordinator.isAdminInteractive = isAdminInteractive
        view.isAdminInteractive = isAdminInteractive

        view.onAdminScenePointDown = { scenePoint, size, clickCount in
            coordinator.handleLeftMouseDown(at: scenePoint, in: size, clickCount: clickCount)
        }
        view.onAdminScenePointDragged = { scenePoint, size in
            coordinator.handleLeftMouseDragged(at: scenePoint, in: size)
        }
        view.onAdminScenePointUp = { scenePoint, size in
            coordinator.handleLeftMouseUp(at: scenePoint, in: size)
        }
        view.onAdminScenePointRightMouseDown = { scenePoint in
            coordinator.handleRightMouseDown(at: scenePoint)
        }
    }

    @MainActor
    final class Coordinator {
        var scene: GameplayScene
        weak var game: PrototypeGameController?
        var isAdminInteractive = false

        private enum Interaction {
            case scrubbing(startTime: Double)
            case draggingNote(id: UUID, startTime: Double)
        }

        private var interaction: Interaction?
        private var dragBegan = false
        private let dragThreshold: CGFloat = 3
        private var initialPoint: CGPoint = .zero

        init(scene: GameplayScene) {
            self.scene = scene
        }

        func handleLeftMouseDown(at scenePoint: CGPoint, in size: CGSize, clickCount: Int) {
            guard isAdminInteractive, let game else { return }
            initialPoint = scenePoint
            dragBegan = false

            if let noteID = scene.adminNoteID(at: scenePoint) {
                game.adminSelectedNoteID = noteID
                let startTime = game.adminNotes.first(where: { $0.id == noteID })?.time ?? game.currentPlaybackTime
                interaction = .draggingNote(id: noteID, startTime: startTime)
            } else if clickCount >= 2, let lane = scene.adminLane(at: scenePoint) {
                let targetTime = game.adminNoteTime(at: scenePoint)
                game.addAdminNote(at: targetTime, lane: lane)
                interaction = nil
            } else {
                interaction = .scrubbing(startTime: game.currentPlaybackTime)
            }
            _ = size
        }

        func handleLeftMouseDragged(at scenePoint: CGPoint, in size: CGSize) {
            guard isAdminInteractive, let game, let interaction else { return }
            let translation = CGPoint(x: scenePoint.x - initialPoint.x, y: scenePoint.y - initialPoint.y)
            if !dragBegan,
               max(abs(translation.x), abs(translation.y)) >= dragThreshold {
                dragBegan = true
            }

            switch interaction {
            case .scrubbing(let startTime):
                let previewTime = game.scrubTargetTime(
                    from: startTime,
                    translationHeight: translation.y,
                    availableHeight: size.height
                )
                game.updateAdminScrubPreview(to: previewTime)
            case .draggingNote(let id, let startTime):
                let movedTime = game.adminDraggedNoteTime(
                    from: startTime,
                    translationHeight: translation.y,
                    availableHeight: size.height
                )
                let targetLane = scene.adminLane(at: scenePoint)
                game.previewAdminNoteMove(id, to: movedTime, yPosition: scenePoint.y, lane: targetLane)
                game.adminSelectedNoteID = id
            }
        }

        func handleLeftMouseUp(at scenePoint: CGPoint, in size: CGSize) {
            guard isAdminInteractive, let game, let interaction else { return }
            let translation = CGPoint(x: scenePoint.x - initialPoint.x, y: scenePoint.y - initialPoint.y)

            switch interaction {
            case .scrubbing(let startTime):
                print("[scrub] handleLeftMouseUp scrubbing: dragBegan=\(dragBegan), startTime=\(startTime), translation.y=\(translation.y), size.height=\(size.height)")
                if dragBegan {
                    let previewTime = game.scrubTargetTime(
                        from: startTime,
                        translationHeight: translation.y,
                        availableHeight: size.height
                    )
                    print("[scrub] previewTime=\(previewTime)")
                    let targetTime = game.resolvedAdminScrubTime(for: previewTime)
                    print("[scrub] targetTime=\(targetTime), calling seekTransport")
                    game.seekTransport(to: targetTime)
                    print("[scrub] after seekTransport: game.currentPlaybackTime=\(game.currentPlaybackTime)")
                }
            case .draggingNote(let id, let startTime):
                game.clearAdminNoteMovePreview(id)
                if dragBegan {
                    let movedTime = game.adminDraggedNoteTime(
                        from: startTime,
                        translationHeight: translation.y,
                        availableHeight: size.height
                    )
                    let targetLane = scene.adminLane(at: scenePoint)
                    game.moveAdminNote(id, to: movedTime, lane: targetLane)
                } else {
                    game.jumpToAdminNote(id)
                }
            }

            self.interaction = nil
            self.dragBegan = false
        }

        func handleRightMouseDown(at scenePoint: CGPoint) {
            guard isAdminInteractive, let game else { return }
            guard let noteID = scene.adminNoteID(at: scenePoint) else { return }
            game.adminSelectedNoteID = noteID
            game.deleteAdminNote(noteID)
        }

    }
}
