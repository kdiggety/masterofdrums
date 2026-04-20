import SwiftUI
import Combine

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

            transportStatusRow("Position", game.barBeatText)
            PositionSliderView(game: game)
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

struct PositionSliderView: View {
    let game: PrototypeGameController
    @State private var sliderValue: Double = 0
    @State private var isDragging = false
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        Slider(
            value: $sliderValue,
            in: 0...1,
            onEditingChanged: { isEditing in
                isDragging = isEditing
                if isEditing {
                    let duration = max(game.globalTime.duration, 0.1)
                    sliderValue = game.globalTime.time / duration
                } else {
                    let targetTime = sliderValue * max(game.globalTime.duration, 0.1)
                    game.seekTransport(to: targetTime)
                }
            }
        )
        .onReceive(game.globalTime.didChange) { tuple in
            let (time, source) = tuple
            // Only update if change came from elsewhere
            guard source != .positionSlider, !isDragging else { return }
            let duration = max(game.globalTime.duration, 0.1)
            sliderValue = time / duration
        }
    }
}
