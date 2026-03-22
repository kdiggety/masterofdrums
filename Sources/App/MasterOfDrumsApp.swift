import SwiftUI

@main
struct MasterOfDrumsApp: App {
    @StateObject private var game = PrototypeGameController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(game)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}
