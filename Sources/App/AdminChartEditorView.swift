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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Admin Step + Record Mode")
                    .font(.title2.bold())
                Text("Build charts by stepping through the song and placing notes at a cursor, or record in real time when useful.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var controlBar: some View {
        GroupBox("Authoring Controls") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("Choose Audio") {
                        game.chooseAudioFile()
                    }
                    .buttonStyle(.bordered)

                    Button("Play") {
                        game.playTransport()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Pause") {
                        game.pauseTransport()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("New Empty Chart") {
                        game.startAdminChart()
                    }
                    .buttonStyle(.bordered)

                    Button(game.isAdminRecordMode ? "Stop Recording" : "Arm Record") {
                        game.toggleAdminRecordMode()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear Notes") {
                        game.clearAdminNotes()
                    }
                    .buttonStyle(.bordered)
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
                    Button("← Step Back") {
                        game.stepBackward()
                    }
                    .buttonStyle(.bordered)

                    Button("Sync To Playback") {
                        game.syncStepCursorToPlayback()
                    }
                    .buttonStyle(.bordered)

                    Button("Step Forward →") {
                        game.stepForward()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 10) {
                    Button("Place Kick") { game.placeStepNote(.kick) }
                        .buttonStyle(.bordered)
                    Button("Place Snare") { game.placeStepNote(.red) }
                        .buttonStyle(.bordered)
                    Button("Place Hat") { game.placeStepNote(.yellow) }
                        .buttonStyle(.bordered)
                    Button("Place Blue") { game.placeStepNote(.blue) }
                        .buttonStyle(.bordered)
                    Button("Place Green") { game.placeStepNote(.green) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var authoringWorkspace: some View {
        HStack(alignment: .top, spacing: 14) {
            GameplayContainerView(scene: game.scene)
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
                        Text("Step mode: step, place notes, step again")
                        Text("Record mode: only use if live capture is convenient")
                        Text("Save Chart JSON when the section looks right")
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
            Button("Load Chart JSON") {
                game.loadAdminChartDocument()
            }
            .buttonStyle(.bordered)

            Button("Save Chart JSON") {
                game.saveAdminChartDocument()
            }
            .buttonStyle(.bordered)
        }
    }

    private var manualFixPanel: some View {
        GroupBox("Manual Add / Fix") {
            HStack(spacing: 10) {
                lanePicker
                timeField
                Button("Add Note") {
                    game.addAdminNote()
                }
                .buttonStyle(.bordered)
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
}
