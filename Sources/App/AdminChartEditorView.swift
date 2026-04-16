import SwiftUI

struct AdminChartEditorView: View {
    @EnvironmentObject private var game: PrototypeGameController
    @State private var editingSectionID: UUID?
    @State private var editingSectionName: String = ""
    @State private var activeSectionDrag: (id: UUID, edge: SongSectionEdge, anchorTime: Double)?
    @State private var sectionStripTargetTime: Double?
    @FocusState private var focusedSectionEditorID: UUID?

    var body: some View {
        ZStack {
            keyboardShortcutBindings
                .frame(width: 0, height: 0)
                .opacity(0)

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
                        adminButton(game.isAudioMuted ? "Unmute Audio" : "Mute Audio") { game.toggleAudioMute() }
                        adminButton("Unload Audio") { game.unloadAudio() }
                    }

                    HStack(spacing: 10) {
                        adminButton(game.isChartMuted ? "Unmute Chart" : "Mute Chart") { game.toggleChartMute() }
                        adminButton("Unload Chart") { game.unloadChart() }
                        adminButton(game.isMetronomeEnabled ? "Metronome On" : "Metronome Off") { game.toggleMetronome() }
                    }

                    HStack(spacing: 10) {
                        if game.transportStateText == "Playing" || game.transportStateText == "Chart Preview" {
                            adminProminentButton("Stop") { game.pauseTransport() }
                        } else {
                            adminProminentButton("Play") { game.playTransport() }
                        }
                        adminButton("Play from Start") { game.playFromStart() }
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

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Lane Audition Filters")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            adminButton("Clear") { game.clearAdminLaneFilters() }
                        }

                        ForEach(Lane.allCases) { lane in
                            HStack(spacing: 8) {
                                Text(lane.displayName)
                                    .frame(width: 56, alignment: .leading)
                                adminButton(game.adminMutedLanes.contains(lane) ? "Muted" : "Mute") {
                                    game.toggleAdminLaneMute(lane)
                                }
                                adminProminentButton(game.adminSoloedLanes.contains(lane) ? "Soloed" : "Solo") {
                                    game.toggleAdminLaneSolo(lane)
                                }
                            }
                        }

                        Text("Solo takes priority over mute during chart-only playback and step audition.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                }
            }

            GroupBox("Playback") {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow("BPM", String(format: "%.1f", game.bpm))
                    statusRow("BPM Source", game.bpmSourceText)
                    statusRow("Timing", game.timingSourceText)
                    statusRow("Time Sig", game.timeSignatureText)
                    statusRow("Ticks/Beat", game.ticksPerBeatText)
                    Text(game.timingOverrideStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.midiTempoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    statusRow("Analysis", game.bpmAnalysisStatusText)
                    Text(game.bpmAnalysisDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

                    HStack(spacing: 8) {
                        adminButton("BPM −") { game.nudgeBPM(by: -1) }
                        Text(String(format: "%.1f", game.bpm))
                            .font(.subheadline.monospacedDigit())
                            .frame(minWidth: 62, alignment: .center)
                        adminButton("BPM +") { game.nudgeBPM(by: 1) }
                    }

                    HStack(spacing: 8) {
                        adminButton("Offset −") { game.nudgeOffset(by: -0.01) }
                        Text(String(format: "%.2fs", game.songOffset))
                            .font(.subheadline.monospacedDigit())
                            .frame(minWidth: 62, alignment: .center)
                        adminButton("Offset +") { game.nudgeOffset(by: 0.01) }
                    }

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
                    .pickerStyle(.menu)
                    .help(game.stepResolution.helpText)

                    Text("Use triplet modes only when the passage really swings or lands on triplet subdivisions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        adminButton("← Back") { game.stepBackward() }
                        adminButton("Sync") { game.syncStepCursorToPlayback() }
                        adminButton("Next →") { game.stepForward() }
                    }
                    Text("Step navigation now auditions notes at the current step.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                    statusRow("Position", game.barBeatText)
                        .help("Position format: Bar.Beat.Division.Tick")
                    Text("Format: Bar.Beat.Division.Tick")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(game.chartStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(game.chartAssociationStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(game.chartAssociationStatusText)
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
                    adminProminentButton("Add Section Here") {
                        if let sectionID = game.addSongSection(),
                           let section = game.adminSections.first(where: { $0.id == sectionID }) {
                            beginEditingSection(section)
                        }
                    }
                    if game.customLoopRange != nil {
                        adminButton("Clear Loop") { game.clearSongSectionLoop() }
                    }
                }

                if game.adminSections.isEmpty {
                    Text("Create named song regions like Intro, Verse, and Chorus to speed up navigation, looping, and paste targets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Drag the white left/right handles on each section block to set explicit start and end points. Boundaries snap to the grid and can snap flush to adjacent sections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    GeometryReader { geometry in
                        let totalDuration = max(game.adminTimelineDuration, 1)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.secondary.opacity(0.12))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .onContinuousHover { phase in
                                    switch phase {
                                    case .active(let location):
                                        let normalized = min(max(location.x / max(geometry.size.width, 1), 0), 1)
                                        sectionStripTargetTime = Double(normalized) * totalDuration
                                    case .ended:
                                        break
                                    }
                                }
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            let hitSection = game.adminSections.contains { section in
                                                let startX = geometry.size.width * CGFloat(max(0, min(1, section.startTime / totalDuration)))
                                                let endX = geometry.size.width * CGFloat(max(0, min(1, section.endTime / totalDuration)))
                                                let width = max(endX - startX, 44)
                                                let offsetX = min(startX, max(0, geometry.size.width - width))
                                                return value.location.x >= offsetX && value.location.x <= offsetX + width
                                            }
                                            guard !hitSection else { return }
                                            let normalized = min(max(value.location.x / max(geometry.size.width, 1), 0), 1)
                                            let targetTime = Double(normalized) * totalDuration
                                            sectionStripTargetTime = targetTime
                                            game.seekSectionTimeline(to: targetTime)
                                        }
                                )
                                .contextMenu {
                                    Button("Paste Section") {
                                        if let targetTime = sectionStripTargetTime {
                                            game.pasteSongSection(atTime: targetTime)
                                        } else {
                                            game.pasteSongSectionAtPlayhead()
                                        }
                                    }
                                    Button("Add Section Here") {
                                        if let targetTime = sectionStripTargetTime,
                                           let sectionID = game.addSongSection(at: targetTime),
                                           let section = game.adminSections.first(where: { $0.id == sectionID }) {
                                            beginEditingSection(section)
                                        } else if let sectionID = game.addSongSection(),
                                                  let section = game.adminSections.first(where: { $0.id == sectionID }) {
                                            beginEditingSection(section)
                                        }
                                    }
                                }
                            ForEach(game.adminSections) { section in
                                sectionStripBlock(section, in: geometry.size.width, totalDuration: totalDuration)
                            }
                            Rectangle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 2)
                                .offset(x: min(max(0, geometry.size.width * CGFloat(game.currentPlaybackTime / totalDuration)), geometry.size.width - 2))
                        }
                    }
                    .frame(height: 30)
                }
            }
        }
    }

    private var keyboardShortcutBindings: some View {
        VStack {
            Button("Undo") { game.undoAdminEdit() }
                .keyboardShortcut("z", modifiers: [.command])
            Button("Redo") { game.redoAdminEdit() }
                .keyboardShortcut("Z", modifiers: [.command, .shift])
            Button("Copy") { game.copySelectedAdminNotes() }
                .keyboardShortcut("c", modifiers: [.command])
            Button("Cut") { game.cutSelectedAdminNotes() }
                .keyboardShortcut("x", modifiers: [.command])
            Button("Paste") { game.pasteAdminNotes() }
                .keyboardShortcut("v", modifiers: [.command])
        }
        .buttonStyle(PlainButtonStyle())
        .allowsHitTesting(false)
    }

    private var recordedNotesSection: some View {
        GroupBox("Recorded Notes") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    adminButton("Delete Selected") { game.deleteSelectedAdminNotes() }
                    adminButton("Clear Selection") { game.clearAdminSelection() }
                    adminButton(game.isRecordedNotesAutoscrollEnabled ? "Autoscroll On" : "Autoscroll Off") {
                        game.isRecordedNotesAutoscrollEnabled.toggle()
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(game.adminNotes) { note in
                                HStack {
                                    Text(note.displayLabel)
                                        .frame(width: 80, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.displayPositionText(for: note.time))
                                            .monospacedDigit()
                                        Text(String(format: "%.2fs", note.time))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    Button("Jump") {
                                        game.selectAdminNote(note.id)
                                        game.jumpToAdminNote(note.id)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                    .focusable(false)
                                    Button("Delete") { game.deleteAdminNote(note.id) }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .focusable(false)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background((game.adminSelectedNoteIDs.contains(note.id) || game.currentPlaybackNoteID == note.id) ? Color.accentColor.opacity(game.currentPlaybackNoteID == note.id ? 0.22 : 0.15) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .id(note.id)
                                .onTapGesture {
                                    let extendSelection = NSEvent.modifierFlags.contains(.shift)
                                    game.selectAdminNote(note.id, extendSelection: extendSelection)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 250, maxHeight: 320)
                    .onChange(of: game.currentPlaybackNoteID) { noteID in
                        guard game.isRecordedNotesAutoscrollEnabled, let noteID else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(noteID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionStripBlock(_ section: SongSection, in totalWidth: CGFloat, totalDuration: Double) -> some View {
        let startX = totalWidth * CGFloat(max(0, min(1, section.startTime / totalDuration)))
        let endX = totalWidth * CGFloat(max(0, min(1, section.endTime / totalDuration)))
        let width = max(endX - startX, 44)

        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if activeSectionDrag?.id != section.id || activeSectionDrag?.edge != .start {
                                activeSectionDrag = (section.id, .start, section.startTime)
                                game.beginSongSectionDrag()
                            }
                            let anchorTime = activeSectionDrag?.anchorTime ?? section.startTime
                            let proposedTime = max(0, anchorTime + (Double(value.translation.width / max(totalWidth, 1)) * totalDuration))
                            game.updateSongSectionBoundary(section.id, edge: .start, to: proposedTime)
                        }
                        .onEnded { _ in
                            activeSectionDrag = nil
                            game.endSongSectionDrag()
                        }
                )
            Group {
                if editingSectionID == section.id {
                    TextField(
                        "Section name",
                        text: $editingSectionName,
                        onCommit: { commitSectionName(for: section) }
                    )
                    .textFieldStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .focused($focusedSectionEditorID, equals: section.id)
                } else {
                    Text(section.name)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        guard editingSectionID != section.id else { return }
                        if activeSectionDrag?.id != section.id || activeSectionDrag?.edge != .move {
                            activeSectionDrag = (section.id, .move, section.startTime)
                            game.beginSongSectionDrag()
                        }
                        let anchorTime = activeSectionDrag?.anchorTime ?? section.startTime
                        let proposedTime = max(0, anchorTime + (Double(value.translation.width / max(totalWidth, 1)) * totalDuration))
                        game.updateSongSectionBoundary(section.id, edge: .move, to: proposedTime)
                    }
                    .onEnded { _ in
                        if activeSectionDrag?.id == section.id, activeSectionDrag?.edge == .move {
                            activeSectionDrag = nil
                            game.endSongSectionDrag()
                        }
                    }
            )
            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if activeSectionDrag?.id != section.id || activeSectionDrag?.edge != .end {
                                activeSectionDrag = (section.id, .end, section.endTime)
                                game.beginSongSectionDrag()
                            }
                            let anchorTime = activeSectionDrag?.anchorTime ?? section.endTime
                            let proposedTime = max(0, anchorTime + (Double(value.translation.width / max(totalWidth, 1)) * totalDuration))
                            game.updateSongSectionBoundary(section.id, edge: .end, to: proposedTime)
                        }
                        .onEnded { _ in
                            activeSectionDrag = nil
                            game.endSongSectionDrag()
                        }
                )
        }
        .frame(width: width, height: 26)
        .background(sectionColor(section).opacity(section.id == game.selectedAdminSectionID ? 0.75 : 0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .offset(x: min(startX, max(0, totalWidth - width)))
        .zIndex(section.id == game.selectedAdminSectionID ? 2 : 1)
        .onTapGesture {
            game.selectSongSection(section.id, movePlayhead: true)
        }
        .onTapGesture(count: 2) {
            beginEditingSection(section)
        }
        .help("\(section.name)\nStart: \(game.displayPositionText(for: section.startTime)) · \(game.displayTimeText(for: section.startTime))\nEnd: \(game.displayPositionText(for: section.endTime)) · \(game.displayTimeText(for: section.endTime))")
        .contextMenu {
            Button("Rename") { beginEditingSection(section) }
            Divider()
            ForEach(sectionColors, id: \.0) { colorName, color in
                Button {
                    game.updateSongSectionColor(section.id, colorName: colorName)
                } label: {
                    Label(colorName.capitalized, systemImage: section.colorName == colorName ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(color)
                }
            }
            Divider()
            Button("Loop") { game.setLoopToSongSection(section.id) }
            Button("Copy Section Notes") { game.copySongSectionNotes(section.id) }
            Button("Paste Section Notes") { game.pasteSongSectionNotes(atSection: section.id) }
            Divider()
            Button("Copy Section") { game.copySongSection(section.id) }
            Button("Delete", role: .destructive) { game.deleteSongSection(section.id) }
        }
    }

    private let sectionColors: [(String, Color)] = [
        ("blue", .blue),
        ("green", .green),
        ("orange", .orange),
        ("purple", .purple),
        ("pink", .pink),
        ("red", .red),
        ("yellow", .yellow)
    ]

    private func sectionColor(_ section: SongSection) -> Color {
        sectionColors.first(where: { $0.0 == section.colorName })?.1 ?? .blue
    }

    private func beginEditingSection(_ section: SongSection) {
        editingSectionID = section.id
        editingSectionName = section.name
        game.selectSongSection(section.id)
        DispatchQueue.main.async {
            focusedSectionEditorID = section.id
        }
    }

    private func commitSectionName(for section: SongSection) {
        let trimmedName = editingSectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            game.renameSongSection(section.id, to: trimmedName)
        }
        editingSectionID = nil
        focusedSectionEditorID = nil
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
            .buttonStyle(BorderedButtonStyle())
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
