import SwiftUI

struct AdminChartEditorView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Admin Chart Editor")
                        .font(.title2.bold())
                    Text("Author chart notes without touching MIDI directly.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button("New Empty Chart") {
                    game.startAdminChart()
                }
                .buttonStyle(.bordered)

                Button("Load Chart JSON") {
                    game.loadAdminChartDocument()
                }
                .buttonStyle(.bordered)

                Button("Save Chart JSON") {
                    game.saveAdminChartDocument()
                }
                .buttonStyle(.borderedProminent)
            }

            GroupBox("Chart Settings") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Current Chart")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(game.chartName)
                            .font(.headline)
                    }

                    HStack(spacing: 10) {
                        lanePicker
                        timeField
                        Button("Add Note") {
                            game.addAdminNote()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text(game.adminStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            GroupBox("Notes") {
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
                .frame(minHeight: 260)
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
}
