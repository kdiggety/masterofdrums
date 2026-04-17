import SwiftUI

func transportStatusRow(_ title: String, _ value: String) -> some View {
    HStack {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .font(.subheadline.monospacedDigit())
            .lineLimit(1)
    }
}

struct TransportControlsView: View {
    @EnvironmentObject var game: PrototypeGameController

    let showsRecord: Bool
    let showsLoop: Bool

    init(showsRecord: Bool = false, showsLoop: Bool = false) {
        self.showsRecord = showsRecord
        self.showsLoop = showsLoop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if game.transportStateText == "Playing" || game.transportStateText == "Chart Preview" {
                    Button("Stop") { game.pauseTransport() }
                        .buttonStyle(BorderedProminentButtonStyle())
                } else {
                    Button("Play") { game.playTransport() }
                        .buttonStyle(BorderedProminentButtonStyle())
                }
                Button("Restart") { game.playFromStart() }
                    .buttonStyle(BorderedButtonStyle())
                if showsRecord {
                    Button(game.isAdminRecordMode ? "Stop Recording" : "Record") {
                        game.toggleAdminRecordMode()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                }
            }

            transportStatusRow("Position", "\(game.playbackTimeText) / \(game.playbackDurationText)")
            Slider(
                value: Binding(
                    get: { game.playbackProgress },
                    set: { newValue in
                        let targetTime = newValue * max(game.playbackDuration, 0.1)
                        game.updateAdminScrubPreview(to: targetTime)
                    }
                ),
                in: 0...1,
                onEditingChanged: { isEditing in
                    if !isEditing {
                        let targetTime = game.playbackProgress * max(game.playbackDuration, 0.1)
                        game.seekTransport(to: targetTime)
                    }
                }
            )
            .disabled(!game.canScrub)

            transportStatusRow("Speed", game.playbackRateText)
            HStack(spacing: 8) {
                speedButton("100%", rate: 1.0)
                speedButton("75%", rate: 0.75)
                speedButton("50%", rate: 0.5)
            }

            if showsLoop {
                transportStatusRow("Loop", game.loopStatusText)
                Picker("Loop", selection: $game.loopLength) {
                    ForEach(PrototypeGameController.LoopLength.allCases) { length in
                        Text(length.rawValue).tag(length)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: game.loopLength) { newValue in
                    game.setLoopLength(newValue)
                }
            }
        }
    }

    @ViewBuilder
    private func speedButton(_ title: String, rate: Float) -> some View {
        if game.isPlaybackRateSelected(rate) {
            Button(title) { game.setPlaybackRate(rate) }
                .buttonStyle(BorderedProminentButtonStyle())
        } else {
            Button(title) { game.setPlaybackRate(rate) }
                .buttonStyle(BorderedButtonStyle())
        }
    }
}
