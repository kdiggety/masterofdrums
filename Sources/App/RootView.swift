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
            Text("Prototype pass 2: routed input layer, keyboard fallback device, scoring, miss tracking, and lane-hit feedback.")
                .foregroundStyle(.secondary)
            Text("Click the gameplay area if keyboard input doesn't register immediately.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            metric(title: "Score", value: "\(game.score)")
            metric(title: "Combo", value: "\(game.combo)")
            metric(title: "Hits", value: "\(game.hitCount)")
            metric(title: "Misses", value: "\(game.missCount)")

            VStack(alignment: .leading) {
                Text("Last Judgment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.lastJudgmentText)
                    .font(.title3.weight(.semibold))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("Active Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.activeInputSourceName)
                    .font(.headline)
                Text("D red · F yellow · J blue · K green · Space kick")
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 6)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
        }
    }
}
