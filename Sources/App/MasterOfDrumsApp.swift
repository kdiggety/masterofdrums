import SwiftUI
import AppKit

@main
struct MasterOfDrumsApp: App {
    @StateObject private var game = PrototypeGameController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    DispatchQueue.main.async {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.forEach { window in
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
    }
}
