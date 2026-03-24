import SwiftUI

struct AdminChartEditorView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                HStack(alignment: .top, spacing: 14) {
                    GameplayContainerView(scene: game.scene, focusVersion: game.gameplayFocusVersion)
                        .frame(maxWidth: .infinity)
                        .frame(height: 480)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    rightPanel
                        .frame(width: 320)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { game.isAdminPageActive = true }
        .onDisappear { game.isAdminPageActive = false }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Step + Record Mode")
                    .font(.title2.bold())
                Text("Use real audio slowdown plus looping to chart small sections. Gameplay keys remain D, F, J, K, and Space.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Authoring Controls") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        adminButton("Choose Audio") { game.chooseAudioFile() }
                        adminProminentButton("Play") { game.playTransport() }
                        adminButton("Pause") { game.pauseTransport() }
                    }

                    HStack(spacing: 10) {
                        adminButton("New Empty Chart") { game.startAdminChart() }
                        adminProminentButton(game.isAdminRecordMode ? "Stop Recording" : "Arm Record") { game.toggleAdminRecordMode() }
                    }

                    HStack(spacing: 10) {
                        adminButton("Clear Notes") { game.clearAdminNotes() }
                        adminButton("Load Chart JSON") { game.loadAdminChartDocument() }
                        adminButton("Save Chart JSON") { game.saveAdminChartDocument() }
                    }
                }
            }

            GroupBox("Playback") {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow("Position", "\(game.playbackTimeText) / \(game.playbackDurationText)")
                    Slider(
                        value: Binding(
                            get: { game.playbackProgress },
                            set: { game.seekTransport(to: $0 * game.playbackDuration) }
                        ),
                        in: 0...1
                    )
                    .disabled(game.playbackDuration <= 0)

                    statusRow("Speed", game.playbackRateText)
                    HStack(spacing: 8) {
                        playbackRateButton("100%", rate: 1.0)
                        playbackRateButton("75%", rate: 0.75)
                        playbackRateButton("50%", rate: 0.5)
                    }

                    statusRow("Loop", game.loopStatusText)
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

            GroupBox("Step Mode") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(game.stepCursorDisplayText)
                        .font(.headline.monospacedDigit())

                    Picker("Resolution", selection: $game.stepResolution) {
                        ForEach(PrototypeGameController.StepResolution.allCases) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        adminButton("← Back") { game.stepBackward() }
                        adminButton("Sync") { game.syncStepCursorToPlayback() }
                        adminButton("Next →") { game.stepForward() }
                    }

                    HStack(spacing: 8) {
                        adminButton("← Bar") { game.jumpBackwardBar() }
                        adminButton("Bar →") { game.jumpForwardBar() }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        adminButton("Place Kick") { game.placeStepNote(.kick) }
                        adminButton("Place Snare") { game.placeStepNote(.red) }
                        adminButton("Place Hat") { game.placeStepNote(.yellow) }
                        adminButton("Place Blue") { game.placeStepNote(.blue) }
                        adminButton("Place Green") { game.placeStepNote(.green) }
                    }
                }
            }

            GroupBox("Session") {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow("Audio", game.trackName)
                    statusRow("Chart", game.chartName)
                    statusRow("Transport", game.transportStateText)
                    statusRow("Time", game.playbackTimeText)
                    statusRow("Bar:Beat", game.barBeatText)
                    Text(game.chartStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.adminStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GroupBox("Lane Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Lane.allCases) { lane in
                        HStack {
                            Text(lane.displayName)
                            Spacer()
                            Text("\(game.noteCount(for: lane))")
                                .font(.headline.monospacedDigit())
                        }
                    }
                }
            }

            GroupBox("Manual Add / Fix") {
                VStack(alignment: .leading, spacing: 10) {
                    lanePicker
                    timeField
                    adminButton("Add Note") { game.addAdminNote() }
                }
            }

            GroupBox("Recorded Notes") {
                List {
                    ForEach(game.adminNotes) { note in
                        HStack {
                            Text(note.lane.displayName)
                                .frame(width: 80, alignment: .leading)
                            Text(String(format: "%.2fs", note.time))
                                .monospacedDigit()
                            Spacer()
                            Button("Delete") { game.deleteAdminNote(note.id) }
                                .buttonStyle(.borderless)
                                .focusable(false)
                        }
                    }
                }
                .frame(minHeight: 220)
            }
        }
    }

    private var lanePicker: some View {
        Picker("Lane", selection: $game.adminSelectedLane) {
            ForEach(Lane.allCases) { lane in Text(lane.displayName).tag(lane) }
        }
        .pickerStyle(.menu)
    }

    private var timeField: some View {
        HStack(spacing: 6) {
            Text("Time")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("0.00", value: $game.adminNoteTime, format: .number.precision(.fractionLength(2)))
                .frame(width: 90)
            Text("sec")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
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

    private func adminButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .focusable(false)
    }

    private func adminProminentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(BorderedProminentButtonStyle())
            .focusable(false)
    }

    @ViewBuilder
    private func playbackRateButton(_ title: String, rate: Float) -> some View {
        if game.isPlaybackRateSelected(rate) {
            Button(title) { game.setPlaybackRate(rate) }
                .buttonStyle(BorderedProminentButtonStyle())
                .focusable(false)
        } else {
            Button(title) { game.setPlaybackRate(rate) }
                .buttonStyle(BorderedButtonStyle())
                .focusable(false)
        }
    }
}
