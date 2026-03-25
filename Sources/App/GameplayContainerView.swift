import SwiftUI
import SpriteKit
import AppKit

final class GameplaySKView: SKView {
    var onAdminLeftMouseDown: ((CGPoint, CGSize) -> Void)?
    var onAdminLeftMouseDragged: ((CGPoint, CGSize) -> Void)?
    var onAdminLeftMouseUp: ((CGPoint, CGSize) -> Void)?
    var onAdminRightMouseDown: ((CGPoint) -> Void)?
    var isAdminInteractive = false

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard isAdminInteractive else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.control) {
            onAdminRightMouseDown?(point)
            return
        }
        onAdminLeftMouseDown?(point, bounds.size)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isAdminInteractive else {
            super.mouseDragged(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        onAdminLeftMouseDragged?(point, bounds.size)
    }

    override func mouseUp(with event: NSEvent) {
        guard isAdminInteractive else {
            super.mouseUp(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        onAdminLeftMouseUp?(point, bounds.size)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isAdminInteractive else {
            super.rightMouseDown(with: event)
            return
        }

        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        onAdminRightMouseDown?(point)
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

        view.onAdminLeftMouseDown = { point, size in
            coordinator.handleLeftMouseDown(at: point, in: size)
        }
        view.onAdminLeftMouseDragged = { point, size in
            coordinator.handleLeftMouseDragged(at: point, in: size)
        }
        view.onAdminLeftMouseUp = { point, size in
            coordinator.handleLeftMouseUp(at: point, in: size)
        }
        view.onAdminRightMouseDown = { point in
            coordinator.handleRightMouseDown(at: point)
        }
    }

    @MainActor
    final class Coordinator {
        var scene: GameplayScene
        weak var game: PrototypeGameController?
        var isAdminInteractive = false

        private enum Interaction {
            case scrubbing(startTime: Double)
            case draggingNote(id: UUID)
        }

        private var interaction: Interaction?
        private var dragBegan = false
        private let dragThreshold: CGFloat = 3
        private var initialPoint: CGPoint = .zero

        init(scene: GameplayScene) {
            self.scene = scene
        }

        func handleLeftMouseDown(at viewPoint: CGPoint, in size: CGSize) {
            guard isAdminInteractive, let game else { return }
            initialPoint = viewPoint
            dragBegan = false

            let scenePoint = scene.convertPoint(fromView: viewPoint)
            if let noteID = scene.adminNoteID(at: scenePoint) {
                game.adminSelectedNoteID = noteID
                interaction = .draggingNote(id: noteID)
            } else {
                interaction = .scrubbing(startTime: game.currentPlaybackTime)
            }
            _ = size
        }

        func handleLeftMouseDragged(at viewPoint: CGPoint, in size: CGSize) {
            guard isAdminInteractive, let game, let interaction else { return }
            let translation = CGPoint(x: viewPoint.x - initialPoint.x, y: viewPoint.y - initialPoint.y)
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
            case .draggingNote(let id):
                let movedTime = game.scrubTargetTime(
                    from: noteStartTime(for: id, in: game) ?? game.currentPlaybackTime,
                    translationHeight: translation.y,
                    availableHeight: size.height
                )
                game.previewAdminNoteMove(id, to: movedTime)
                game.adminSelectedNoteID = id
            }
        }

        func handleLeftMouseUp(at viewPoint: CGPoint, in size: CGSize) {
            guard isAdminInteractive, let game, let interaction else { return }
            let translation = CGPoint(x: viewPoint.x - initialPoint.x, y: viewPoint.y - initialPoint.y)

            switch interaction {
            case .scrubbing(let startTime):
                if dragBegan {
                    let previewTime = game.scrubTargetTime(
                        from: startTime,
                        translationHeight: translation.y,
                        availableHeight: size.height
                    )
                    let targetTime = game.resolvedAdminScrubTime(for: previewTime)
                    game.seekTransport(to: targetTime)
                }
            case .draggingNote(let id):
                game.clearAdminNoteMovePreview(id)
                if dragBegan {
                    let movedTime = game.scrubTargetTime(
                        from: noteStartTime(for: id, in: game) ?? game.currentPlaybackTime,
                        translationHeight: translation.y,
                        availableHeight: size.height
                    )
                    game.moveAdminNote(id, to: movedTime)
                } else {
                    game.jumpToAdminNote(id)
                }
            }

            self.interaction = nil
            self.dragBegan = false
        }

        func handleRightMouseDown(at viewPoint: CGPoint) {
            guard isAdminInteractive, let game else { return }
            let scenePoint = scene.convertPoint(fromView: viewPoint)
            guard let noteID = scene.adminNoteID(at: scenePoint) else { return }
            game.adminSelectedNoteID = noteID
            game.deleteAdminNote(noteID)
        }

        private func noteStartTime(for id: UUID, in game: PrototypeGameController) -> Double? {
            game.adminNotes.first(where: { $0.id == id })?.time
        }
    }
}
