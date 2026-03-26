import SwiftUI

struct AdminChartEditorView: View {
    @EnvironmentObject private var game: PrototypeGameController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                HStack(alignment: .top, spacing: 14) {
                    leftPanel
                        .frame(maxWidth: .infinity)

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
                Text("Drag empty lane space to scrub. Drag a note to move it. Right-click a note to delete. Gameplay keys remain D, F, J, K, and Space.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            songSectionsSection

            GameplayContainerView(
                scene: game.scene,
                focusVersion: game.gameplayFocusVersion,
                game: game,
                isAdminInteractive: true
            )
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
            .frame(height: 440)

            recordedNotesSection
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Authoring Controls") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        adminButton("Choose Audio") { game.chooseAudioFile() }
                        if game.transportStateText == "Playing" {
                            adminProminentButton("Stop") { game.pauseTransport() }
                        } else {
                            adminProminentButton("Play") { game.playTransport() }
                        }
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
                    statusRow("BPM", String(format: "%.1f", game.bpm))
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

                    Divider()

                    Toggle("Snap note lane scrub to beat grid", isOn: $game.isNoteLaneSnapEnabled)

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
        }
    }

    private var songSectionsSection: some View {
        GroupBox("Song Sections") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    adminProminentButton("Add Section Here") { game.addSongSection() }
                    if game.customLoopRange != nil {
                        adminButton("Clear Loop") { game.clearSongSectionLoop() }
                    }
                }

                if game.adminSections.isEmpty {
                    Text("Create named song regions like Intro, Verse, and Chorus to speed up navigation, looping, and paste targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    GeometryReader { geometry in
                        let totalDuration = max(game.playbackDuration, game.adminNotes.map(\.time).max() ?? 0, game.adminSections.map(\.startTime).max() ?? 0, 1)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.12))
                            ForEach(Array(game.adminSections.enumerated()), id: \.element.id) { index, section in
                                let nextStart = index + 1 < game.adminSections.count ? game.adminSections[index + 1].startTime : totalDuration
                                let startX = geometry.size.width * CGFloat(max(0, min(1, section.startTime / totalDuration)))
                                let width = max(geometry.size.width * CGFloat(max(0.03, (nextStart - section.startTime) / totalDuration)), 44)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(section.id == game.selectedAdminSectionID ? Color.accentColor.opacity(0.65) : Color.accentColor.opacity(0.35))
                                    .frame(width: width, height: 26)
                                    .offset(x: min(startX, max(0, geometry.size.width - width)))
                                    .overlay(alignment: .leading) {
                                        Text(section.name)
                                            .font(.caption2.weight(.semibold))
                                            .lineLimit(1)
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 8)
                                            .frame(width: width, alignment: .leading)
                                            .offset(x: min(startX, max(0, geometry.size.width - width)))
                                    }
                                    .onTapGesture {
                                        game.selectSongSection(section.id)
                                        game.jumpToSongSection(section.id)
                                    }
                            }
                            Rectangle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 2)
                                .offset(x: min(max(0, geometry.size.width * CGFloat(game.currentPlaybackTime / totalDuration)), geometry.size.width - 2))
                        }
                    }
                    .frame(height: 30)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(game.adminSections) { section in
                            let isSelected = section.id == game.selectedAdminSectionID
                            VStack(alignment: .leading, spacing: 6) {
                                TextField(
                                    "Section name",
                                    text: Binding(
                                        get: { section.name },
                                        set: { game.renameSongSection(section.id, to: $0) }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                HStack(spacing: 6) {
                                    Text("\(game.sectionBarBeatText(for: section.startTime)) · \(game.displayTimeText(for: section.startTime))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }

                                HStack(spacing: 6) {
                                    Button("Jump") { game.jumpToSongSection(section.id) }
                                        .buttonStyle(.borderless)
                                    Button("Loop") { game.setLoopToSongSection(section.id) }
                                        .buttonStyle(.borderless)
                                    Button("Copy Notes") { game.copySongSectionNotes(section.id) }
                                        .buttonStyle(.borderless)
                                    Button("Paste Here") { game.pasteSongSectionNotes(atSection: section.id) }
                                        .buttonStyle(.borderless)
                                    Button("Delete") { game.deleteSongSection(section.id) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .padding(8)
                            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .onTapGesture { game.selectSongSection(section.id) }
                        }
                    }
                }
            }
        }
    }

    private var recordedNotesSection: some View {
        GroupBox("Recorded Notes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    adminButton("Delete Selected") { game.deleteSelectedAdminNotes() }
                    adminButton("Clear Selection") { game.clearAdminSelection() }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(game.adminNotes) { note in
                            HStack {
                                Text(note.lane.displayName)
                                    .frame(width: 80, alignment: .leading)
                                Text(String(format: "%.2fs", note.time))
                                    .monospacedDigit()
                                Spacer()
                                Button("Jump") {
                                    game.selectAdminNote(note.id)
                                    game.jumpToAdminNote(note.id)
                                }
                                .buttonStyle(.borderless)
                                .focusable(false)
                                Button("Delete") { game.deleteAdminNote(note.id) }
                                    .buttonStyle(.borderless)
                                    .focusable(false)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(game.adminSelectedNoteIDs.contains(note.id) ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let extendSelection = NSEvent.modifierFlags.contains(.shift)
                                game.selectAdminNote(note.id, extendSelection: extendSelection)
                            }
                        }
                    }
                }
                .frame(minHeight: 250, maxHeight: 320)
            }
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
