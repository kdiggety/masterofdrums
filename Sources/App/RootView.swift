import SwiftUI

struct RootView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        NavigationSplitView {
            List {
                Section("Prototype") {
                    NavigationLink {
                        gameplayView
                    } label: {
                        Label("Gameplay", systemImage: "music.note")
                    }

                    NavigationLink {
                        AdminChartEditorView()
                            .environmentObject(game)
                    } label: {
                        Label("Admin", systemImage: "slider.horizontal.3")
                    }

                    Label("Audio", systemImage: "waveform")
                    Label("Devices", systemImage: "pianokeys")
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            gameplayView
        }
    }

    private var gameplayView: some View {
        VStack(spacing: 8) {
            compactHeader

            HStack(alignment: .top, spacing: 14) {
                GameplayContainerView(scene: game.scene)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                sideControlPanel
                    .frame(width: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var compactHeader: some View {
        HStack {
            Text("MasterOfDrums")
                .font(.title.bold())
            Spacer()
            Text("Click playfield if keys stop responding")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var sideControlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Transport") {
                VStack(alignment: .leading, spacing: 10) {
                    Label(game.trackName, systemImage: "waveform")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    infoRow("Chart", game.chartName)
                    Text(game.chartStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    infoRow("State", game.transportStateText)
                    infoRow("Time", game.playbackTimeText)
                    infoRow("Bar:Beat", game.barBeatText)
                    infoRow("Sub", game.musicalSubdivisionText)

                    HStack(spacing: 8) {
                        Button("Choose Audio") {
                            game.chooseAudioFile()
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button("Find Matching Chart") {
                            game.findMatchingChartForCurrentAudio()
                        }
                        .buttonStyle(BorderedButtonStyle())

                        Button("Choose Chart") {
                            game.chooseChartFile()
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }

                    Text(game.chartAssociationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Play") {
                            game.playTransport()
                        }
                        .buttonStyle(BorderedProminentButtonStyle())

                        Button("Pause") {
                            game.pauseTransport()
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }
            }

            GroupBox("Tempo") {
                VStack(alignment: .leading, spacing: 10) {
                    infoRow("BPM Source", game.bpmSourceText)
                    infoRow("Timing", game.timingSourceText)
                    infoRow("Time Sig", game.timeSignatureText)
                    infoRow("Ticks/Beat", game.ticksPerBeatText)
                    Text(game.timingOverrideStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.midiTempoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    infoRow("Analysis", game.bpmAnalysisStatusText)
                    Text(game.bpmAnalysisDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                }
            }

            GroupBox("Run") {
                VStack(alignment: .leading, spacing: 10) {
                    Button(game.isRunComplete ? "Restart Run" : "Reset Run") {
                        game.restartRun()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())

                    Text("D red · F yellow · J blue · K green · Space kick")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 18) {
            metric(title: "Score", value: "\(game.score)")
            metric(title: "Combo", value: "\(game.combo)")
            metric(title: "Hits", value: "\(game.hitCount)")
            metric(title: "Misses", value: "\(game.missCount)")
            metric(title: "Accuracy", value: game.accuracyText)

            VStack(alignment: .leading, spacing: 4) {
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

            VStack(alignment: .trailing, spacing: 6) {
                Text("Active Input")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(game.activeInputSourceName)
                    .font(.headline)
            }
        }
        .padding(.horizontal, 4)
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

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
    }

    private func stepperChip(title: String, value: String, decrement: @escaping () -> Void, increment: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("−", action: decrement)
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.mini)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 62, alignment: .center)
            Button("+", action: increment)
                .buttonStyle(BorderedButtonStyle())
                .controlSize(.mini)
        }
    }
}
