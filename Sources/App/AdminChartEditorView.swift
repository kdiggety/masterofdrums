import SwiftUI

struct AdminChartEditorView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Admin Record Mode")
                        .font(.title2.bold())
                    Text("Load audio, play the song, and use the gameplay keys to record a chart.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

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

            HStack(alignment: .top, spacing: 14) {
                GameplayContainerView(scene: game.scene)
                    .frame(maxWidth: .infinity, minHeight: 340)
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
                            Text("1. Choose Audio")
                            Text("2. Start a new empty chart")
                            Text("3. Arm Record")
                            Text("4. Press Play and hit D/F/J/K/Space in time")
                            Text("5. Save Chart JSON")
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
        .padding(16)
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
