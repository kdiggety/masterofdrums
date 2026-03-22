import SwiftUI

struct RootView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        NavigationSplitView {
            List {
                Section("Prototype") {
                    Label("Gameplay", systemImage: "music.note")
                    Label("Calibration", systemImage: "slider.horizontal.3")
                    Label("Devices", systemImage: "pianokeys")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            VStack(spacing: 16) {
                header
                GameplayContainerView(scene: game.scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                statusBar
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MasterOfDrums")
                .font(.largeTitle.bold())
            Text("Initial Swift prototype: note highway, keyboard input fallback, scoring, and judgment feedback.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading) {
                Text("Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(game.score)")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading) {
                Text("Combo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(game.combo)")
                    .font(.title2.bold())
            }

            VStack(alignment: .leading) {
                Text("Last Judgment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.lastJudgmentText)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("Keyboard Lanes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("D red · F yellow · J blue · K green · Space kick")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 6)
    }
}
