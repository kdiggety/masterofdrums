import SwiftUI

struct RootView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        AdminChartEditorView()
            .environmentObject(game)
    }
}
