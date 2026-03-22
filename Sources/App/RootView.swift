import SwiftUI

struct RootView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        NavigationSplitView {
            List {
                Section("Prototype") {
                    Label("Gameplay", systemImage: "music.note")
                    Label("Audio", systemImage: "waveform")
                    Label("Calibration", systemImage: "slider.horizontal.3")
                    Label("Devices", systemImage: "pianokeys")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            VStack(spacing: 12) {
                header
                compactTransportBar
                GameplayContainerView(scene: game.scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                statusBar
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MasterOfDrums")
                .font(.largeTitle.bold())
            Text("Prototype pass 5: musical transport UI, manual BPM/offset control, and bar-beat display on top of the audio clock.")
                .foregroundStyle(.secondary)
            Text("Click the gameplay area if keyboard input doesn't register immediately.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactTransportBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Label(game.trackName, systemImage: "waveform")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                Text("\(game.transportStateText) · \(game.playbackTimeText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Bar:Beat:Sub \(game.musicalPositionText)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button("Choose Audio") {
                    game.chooseAudioFile()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Play") {
                    game.playTransport()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Pause") {
                    game.pauseTransport()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                stepperChip(title: "BPM", value: String(format: "%.1f", game.bpm)) {
                    game.nudgeBPM(by: -1)
                } increment: {
                    game.nudgeBPM(by: 1)
                }

                stepperChip(title: "Offset", value: String(format: "%.2fs", game.songOffset)) {
                    game.nudgeOffset(by: -0.01)
                } increment: {
                    game.nudgeOffset(by: 0.01)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            metric(title: "Score", value: "\(game.score)")
            metric(title: "Combo", value: "\(game.combo)")
            metric(title: "Hits", value: "\(game.hitCount)")
            metric(title: "Misses", value: "\(game.missCount)")
            metric(title: "Accuracy", value: game.accuracyText)

            VStack(alignment: .leading, spacing: 6) {
                Text("Last Judgment")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.lastJudgmentText)
                    .font(.title3.weight(.semibold))
                Text(game.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(game.isRunComplete ? .orange : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("Active Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.activeInputSourceName)
                    .font(.headline)
                Button(game.isRunComplete ? "Restart Run" : "Reset Run") {
                    game.restartRun()
                }
                .buttonStyle(.borderedProminent)
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

    private func stepperChip(title: String, value: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("−", action: decrement)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 62, alignment: .center)
            Button("+", action: increment)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
    }
}
