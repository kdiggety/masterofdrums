import SwiftUI

struct AdminChartEditorView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controlBar
                stepModePanel
                authoringWorkspace
                saveLoadRow
                manualFixPanel
                laneSummaryPanel
                recordedNotesPanel
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            game.isAdminPageActive = true
        }
        .onDisappear {
            game.isAdminPageActive = false
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Step + Record Mode")
                    .font(.title2.bold())
                Text("Gameplay keys stay the same here: D, F, J, K, and Space. Use transport buttons only; Space should be kick, not play/pause.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var controlBar: some View {
        GroupBox("Authoring Controls") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    adminButton("Choose Audio") {
                        game.chooseAudioFile()
                    }

                    adminProminentButton("Play") {
                        game.playTransport()
                    }

                    adminButton("Pause") {
                        game.pauseTransport()
                    }
                }

                HStack(spacing: 10) {
                    adminButton("New Empty Chart") {
                        game.startAdminChart()
                    }

                    adminProminentButton(game.isAdminRecordMode ? "Stop Recording" : "Arm Record") {
                        game.toggleAdminRecordMode()
                    }

                    adminButton("Clear Notes") {
                        game.clearAdminNotes()
                    }
                }
            }
        }
    }

    private var stepModePanel: some View {
        GroupBox("Step Mode") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text("Resolution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Resolution", selection: $game.stepResolution) {
                        ForEach(PrototypeGameController.StepResolution.allCases) { resolution in
                            Text(resolution.rawValue).tag(resolution)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Spacer()

                    Text(game.stepCursorDisplayText)
                        .font(.headline.monospacedDigit())
                }

                HStack(spacing: 10) {
                    adminButton("← Step Back") {
                        game.stepBackward()
                    }

                    adminButton("Sync To Playback") {
                        game.syncStepCursorToPlayback()
                    }

                    adminButton("Step Forward →") {
                        game.stepForward()
                    }
                }

                HStack(spacing: 10) {
                    adminButton("Place Kick") { game.placeStepNote(.kick) }
                    adminButton("Place Snare") { game.placeStepNote(.red) }
                    adminButton("Place Hat") { game.placeStepNote(.yellow) }
                    adminButton("Place Blue") { game.placeStepNote(.blue) }
                    adminButton("Place Green") { game.placeStepNote(.green) }
                }
            }
        }
    }

    private var authoringWorkspace: some View {
        HStack(alignment: .top, spacing: 14) {
            GameplayContainerView(scene: game.scene, focusVersion: game.gameplayFocusVersion)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 12) {
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
                    }
                }

                GroupBox("Workflow") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Step mode: move the cursor with buttons, then use D/F/J/K/Space or Place buttons to enter notes")
                        Text("Record mode: same gameplay keys, but captures live timing")
                        Text("Admin mode should not judge misses or combos")
                    }
                    .font(.subheadline)
                }

                GroupBox("Status") {
                    Text(game.adminStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 280)
        }
    }

    private var saveLoadRow: some View {
        HStack(spacing: 10) {
            adminButton("Load Chart JSON") {
                game.loadAdminChartDocument()
            }

            adminButton("Save Chart JSON") {
                game.saveAdminChartDocument()
            }
        }
    }

    private var manualFixPanel: some View {
        GroupBox("Manual Add / Fix") {
            HStack(spacing: 10) {
                lanePicker
                timeField
                adminButton("Add Note") {
                    game.addAdminNote()
                }
            }
        }
    }

    private var laneSummaryPanel: some View {
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
    }

    private var recordedNotesPanel: some View {
        GroupBox("Recorded Notes") {
            List {
                ForEach(game.adminNotes) { note in
                    HStack {
                        Text(note.lane.displayName)
                            .frame(width: 80, alignment: .leading)
                        Text(String(format: "%.2fs", note.time))
                            .monospacedDigit()
                        Spacer()
                        Button("Delete") {
                            game.deleteAdminNote(note.id)
                        }
                        .buttonStyle(.borderless)
                        .focusable(false)
                    }
                }
            }
            .frame(minHeight: 220)
        }
    }

    private var lanePicker: some View {
        Picker("Lane", selection: $game.adminSelectedLane) {
            ForEach(Lane.allCases) { lane in
                Text(lane.displayName).tag(lane)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 140)
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
            .buttonStyle(.borderedProminent)
            .focusable(false)
    }
}
