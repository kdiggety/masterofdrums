import SwiftUI
import SpriteKit

struct GameplayContainerView: NSViewRepresentable {
    let scene: GameplayScene

    func makeNSView(context: Context) -> SKView {
        let view = SKView()
        view.allowsTransparency = false
        view.ignoresSiblingOrder = true
        view.presentScene(scene)
        view.window?.makeFirstResponder(view)
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: SKView, context: Context) {
        if nsView.scene !== scene {
            nsView.presentScene(scene)
        }
    }
}
