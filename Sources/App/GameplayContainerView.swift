import SwiftUI
import SpriteKit
import AppKit

final class GameplaySKView: SKView {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
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

    func makeNSView(context: Context) -> SKView {
        let view = GameplaySKView()
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.presentScene(scene)

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        if nsView.scene !== scene {
            nsView.presentScene(scene)
        }

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}
