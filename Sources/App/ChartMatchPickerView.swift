import SwiftUI

struct ChartMatchPickerView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Matching Chart")
                .font(.title3.bold())

            Text("We found multiple likely charts for the current audio file. Pick the one you want to load.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(game.chartMatchCandidates) { candidate in
                Button {
                    game.selectChartMatch(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(candidate.url.lastPathComponent)
                                .font(.headline)
                            Spacer()
                            Text("score \(candidate.score)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(candidate.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(candidate.url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") {
                    game.dismissChartMatchPicker()
                }
                .buttonStyle(BorderedButtonStyle())
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
    }
}
